import LumenCore
import LumenReader
import LumenStorage
import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Читалка: книга или документ слева, заметки к ним справа. На iPhone заметки выезжают шторкой.
/// Выделенный текст можно покрасить или одним нажатием отправить в заметки выпиской,
/// а выписка потом открывает книгу ровно на этом месте.
/// Книга, содержание и заметки лежат отдельными мягкими листами с зазорами между ними.
struct ReaderView: View {
    @State private var model: ReaderModel
    let highlightId: UUID?
    var onOpenPage: (UUID) -> Void
    var onOpenSource: (UUID, UUID?) -> Void
    var onShowInfo: () -> Void
    var onClose: () -> Void

    @AppStorage("reader.palette") private var paletteRaw = ReaderAppearance.Palette.night.rawValue
    @AppStorage("reader.fontSize") private var fontSize = 18
    @AppStorage("reader.typeface") private var typefaceRaw = ReaderAppearance.Typeface.serif.rawValue
    @AppStorage("reader.notesOpen") private var showsNotes = true
    @AppStorage("reader.notesFraction") private var notesFraction = 0.42
    @State private var isNotesSheetPresented = false
    @State private var showsHighlights = false
    @State private var isAppearancePresented = false
    @AppStorage("reader.tocOpen") private var showsToc = false
    @State private var isTocSheetPresented = false
    @State private var dragStartFraction: Double?
    @State private var isHandleHovered = false
    @State private var isPagePickerPresented = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    init(
        database: AppDatabase,
        sourceId: UUID,
        highlightId: UUID?,
        onOpenPage: @escaping (UUID) -> Void,
        onOpenSource: @escaping (UUID, UUID?) -> Void,
        onShowInfo: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: ReaderModel(database: database, sourceId: sourceId, highlightId: highlightId))
        self.highlightId = highlightId
        self.onOpenPage = onOpenPage
        self.onOpenSource = onOpenSource
        self.onShowInfo = onShowInfo
        self.onClose = onClose
    }

    private var appearance: ReaderAppearance {
        ReaderAppearance(
            palette: ReaderAppearance.Palette(rawValue: paletteRaw) ?? .night,
            fontSize: fontSize,
            typeface: ReaderAppearance.Typeface(rawValue: typefaceRaw) ?? .serif
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let isWide = isWide(geometry.size.width)
            let notesWidth: CGFloat = geometry.size.width * CGFloat(notesFraction)
            let showsNotesPane: Bool = isWide && showsNotes && model.notes != nil
            // Содержание встаёт отдельной колонкой, только если книге останется достаточно места.
            let tocAsColumn: Bool = showsToc && !isCompact && !model.toc.isEmpty
                && geometry.size.width - (showsNotesPane ? notesWidth : 0) - 300 > 460
            HStack(spacing: 0) {
                if tocAsColumn {
                    tableOfContents
                        .frame(width: 260)
                        .padding(.trailing, ReaderStyle.gap)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                readerPane(tocOverlay: !tocAsColumn)
                if showsNotesPane, let notes = model.notes {
                    splitHandle(totalWidth: geometry.size.width)
                    notesPane(notes)
                        .frame(width: notesWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, isCompact ? 8 : ReaderStyle.gap)
            .padding(.top, isCompact ? 4 : 6)
            .padding(.bottom, isCompact ? 8 : ReaderStyle.gap)
            .onChange(of: isWide) { _, wide in
                if wide { isNotesSheetPresented = false }
            }
        }
        .fontDesign(.rounded)
        .background(ThemedBackground())
        .navigationTitle(model.source?.displayTitle ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .sheet(isPresented: $isTocSheetPresented) {
            TableOfContents(model: model, closesOnSelect: true, isCard: false) { isTocSheetPresented = false }
                .fontDesign(.rounded)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $isNotesSheetPresented) {
            if let notes = model.notes {
                NavigationStack {
                    VStack(spacing: 0) {
                        notesHeader(notes, closes: false)
                        PageEditorView(model: notes, onOpenPage: openSidePage, onOpenSource: openSource)
                            .id(notes.pageId)
                    }
                    .padding(.top, 6)
                    #if os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
                }
                .fontDesign(.rounded)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationCornerRadius(34)
            }
        }
        .task {
            model.web.setAppearance(appearance)
            model.pdf.setPageStyle(appearance.palette.pdfStyle)
            await model.load()
        }
        .task { await model.observeHighlights() }
        .onChange(of: appearance) { _, appearance in
            model.web.setAppearance(appearance)
            model.pdf.setPageStyle(appearance.palette.pdfStyle)
        }
        .onChange(of: highlightId) { _, id in
            if let id { model.reveal(id: id) }
        }
        .onDisappear {
            Task { await model.flush() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Свернули приложение: место чтения и время сохраняются сразу.
            if phase != .active { Task { await model.flush() } }
        }
    }

    /// Узкий экран iPhone: панели открываются шторками, кнопки собраны в нижнюю панель.
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private func isWide(_ width: CGFloat) -> Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && width > 700
        #else
        return width > 720
        #endif
    }

    private func openPage(_ id: UUID) {
        isNotesSheetPresented = false
        onOpenPage(id)
    }

    /// Ссылки из заметки рядом открываются там же, рядом с книгой.
    private func openSidePage(_ id: UUID) {
        isPagePickerPresented = false
        LumenSounds.play(.navigate)
        Task { await model.openSidePage(id) }
    }

    /// Выписка из этой же книги прокручивает к месту, из другой открывает ту книгу.
    private func openSource(_ sourceId: UUID, _ highlightId: UUID?) {
        if sourceId == model.sourceId {
            if let highlightId {
                LumenSounds.play(.navigate)
                model.reveal(id: highlightId)
            }
        } else {
            isNotesSheetPresented = false
            onOpenSource(sourceId, highlightId)
        }
    }

    // MARK: Книга

    private var isWebContent: Bool {
        if case .web = model.content { return true }
        return false
    }

    /// Темы страницы работают для книг в HTML и для PDF.
    private var hasPageThemes: Bool {
        isWebContent || model.content == .pdf
    }

    /// Цвет листа, на котором лежит книга.
    private var sheetColors: [Color] {
        switch model.content {
        case .web:
            return appearance.palette.sheetColors
        case .pdf:
            let backdrop = Color(hex: appearance.palette.pdfStyle.backdrop)
            return [backdrop, backdrop]
        default:
            return [theme.cardFill.opacity(0.7), theme.cardFill.opacity(0.5)]
        }
    }

    /// Цвет подписей поверх листа: тёмный на светлой бумаге, светлый ночью.
    private var ink: Color {
        if case .web = model.content { return appearance.palette.ink }
        if model.content == .pdf, appearance.palette != .original { return appearance.palette.ink }
        return theme.textPrimary
    }

    /// Полоса глав стоит под текстом, а не поверх него, поэтому никогда не закрывает строки.
    /// Поверх книги всплывают только временные плашки: выделение, уведомление.
    private func readerPane(tocOverlay: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    document
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 10) {
                        if let toast = model.toast {
                            Label(toast, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if model.selection != nil {
                            SelectionBar(model: model, isCompact: isCompact)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if let id = model.activeHighlightId, let highlight = model.highlights.first(where: { $0.id == id }) {
                            HighlightBar(model: model, highlight: highlight, isCompact: isCompact)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, isCompact ? 10 : 18)
                    .padding(.bottom, isCompact ? 10 : 16)
                    .animation(.spring(duration: 0.3), value: model.selection)
                    .animation(.spring(duration: 0.3), value: model.activeHighlightId)
                    .animation(.spring(duration: 0.3), value: model.toast)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .readerSheet(sheetColors, radius: isCompact ? 30 : ReaderStyle.sheetRadius)
            .overlay(alignment: .leading) {
                // На узком окне содержание плавает над книгой и не сдвигает текст.
                if tocOverlay, showsToc, !model.toc.isEmpty, !isCompact {
                    tableOfContents
                        .frame(width: 280)
                        .frame(maxHeight: .infinity)
                        .padding(12)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            if isCompact {
                dock
            }
        }
    }

    private var tableOfContents: some View {
        TableOfContents(model: model) {
            LumenSounds.play(.panelClose)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { showsToc = false }
        }
    }

    @ViewBuilder
    private var document: some View {
        switch model.content {
        case .loading:
            ProgressView("Открываю…")
                .tint(ReaderStyle.peach)
        case .web:
            WebReaderView(controller: model.web)
        case .pdf:
            PDFReaderView(controller: model.pdf)
        case .image:
            if let source = model.source {
                ScrollView([.horizontal, .vertical]) {
                    AttachmentImage(name: source.file, attachments: model.database.attachments)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(24)
                }
            }
        case .quickLook(let url):
            QuickLookView(url: url)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не открывается", systemImage: "book.closed")
            } description: {
                Text(message)
            } actions: {
                Button("В библиотеку", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderStyle.peachDeep)
            }
        }
    }

    /// Мягкая полоса внизу листа, под текстом: главы, прогресс и место в книге.
    /// На iPhone без названия главы, чтобы влезли стрелки.
    @ViewBuilder
    private var footer: some View {
        let sections = model.sections
        switch model.content {
        case .web, .pdf:
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            HStack(spacing: 12) {
                if sections.count > 1 {
                    Button {
                        model.openSection(model.section - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(SheetRoundButtonStyle(ink: ink))
                    .disabled(model.section == 0)
                    .help("Предыдущая глава")
                }
                if !isCompact, let title = model.currentTocEntry?.title {
                    Text(title)
                        .lineLimit(1)
                        .frame(maxWidth: 170, alignment: .leading)
                }
                SoftProgressTrack(progress: model.progress, marks: sections.count <= 30 ? sections.count : 0, ink: ink)
                    .frame(minWidth: 80)
                Text(model.positionLabel)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                if sections.count > 1 {
                    Button {
                        model.openSection(model.section + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(SheetRoundButtonStyle(ink: ink))
                    .disabled(model.section >= sections.count - 1)
                    .help("Следующая глава")
                }
            }
            .font(.system(size: isCompact ? 12 : 13, weight: .bold, design: .rounded))
            .foregroundStyle(ink.opacity(0.68))
            .padding(.horizontal, isCompact ? 8 : 12)
            .padding(.vertical, isCompact ? 7 : 10)
            .background(ink.opacity(0.07), in: shape)
            .frame(maxWidth: 680)
            .padding(.horizontal, isCompact ? 10 : 18)
            .padding(.top, 6)
            .padding(.bottom, isCompact ? 10 : 16)
        default:
            EmptyView()
        }
    }

    /// Нижняя панель на iPhone: всё под большим пальцем.
    private var dock: some View {
        HStack(spacing: 0) {
            Button {
                toggleToc()
            } label: {
                Label("Содержание", systemImage: "list.bullet.indent")
            }
            .disabled(model.toc.isEmpty)
            Spacer(minLength: 0)
            Button {
                isAppearancePresented = true
            } label: {
                Label("Оформление", systemImage: "textformat.size")
            }
            .disabled(!hasPageThemes)
            .popover(isPresented: $isAppearancePresented) { appearancePanel }
            Spacer(minLength: 0)
            ProgressRing(progress: model.progress)
            Spacer(minLength: 0)
            Button {
                showsHighlights = true
            } label: {
                Label("Выделения", systemImage: "highlighter")
            }
            .popover(isPresented: $showsHighlights) { highlightsList }
            Spacer(minLength: 0)
            Button {
                toggleNotes()
            } label: {
                Label("Заметки", systemImage: "note.text")
            }
        }
        .buttonStyle(ReaderRoundButtonStyle(size: 44, tint: theme.textPrimary))
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 10)
        .frame(height: 60)
        .frame(maxWidth: 440)
        .background(theme.cardFill.opacity(0.55), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
            lineWidth: 1
        ))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
    }

    private var appearancePanel: some View {
        ReaderAppearancePanel(paletteRaw: $paletteRaw, fontSize: $fontSize, typefaceRaw: $typefaceRaw, showsTextOptions: isWebContent)
            .presentationDetents([.height(isWebContent ? 340 : 190)])
            .presentationCornerRadius(34)
            .presentationCompactAdaptation(.sheet)
    }

    private var highlightsList: some View {
        HighlightsList(model: model) { showsHighlights = false }
            .frame(minWidth: 320, minHeight: 360)
            .presentationCornerRadius(34)
            .presentationCompactAdaptation(.sheet)
    }

    // MARK: Заметки

    private func notesPane(_ notes: PageEditorModel) -> some View {
        VStack(spacing: 0) {
            notesHeader(notes, closes: true)
            PageEditorView(model: notes, onOpenPage: openSidePage, onOpenSource: openSource)
                .id(notes.pageId)
        }
        .readerGlassCard(theme)
    }

    /// Шапка панели заметок: какая заметка открыта и кнопка выбрать другую.
    private func notesHeader(_ notes: PageEditorModel, closes: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                isPagePickerPresented.toggle()
            } label: {
                HStack(spacing: 7) {
                    if model.showsBookNotes {
                        Image(systemName: "book")
                        Text("Заметки к книге").lineLimit(1)
                    } else {
                        Text(notes.page?.icon ?? "📄")
                        Text(notes.isLoaded ? sideTitle(notes) : "").lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(theme.textSecondary)
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .padding(.leading, 11)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Открыть рядом другую заметку")
            .popover(isPresented: $isPagePickerPresented, arrowEdge: .bottom) {
                SidePagePicker(
                    database: model.database,
                    source: model.source,
                    currentPageId: notes.pageId,
                    bookNotesPageId: model.bookNotesPageId,
                    onOpen: openSidePage,
                    onCreate: {
                        isPagePickerPresented = false
                        Task { await model.createSidePage() }
                    }
                )
                .presentationCompactAdaptation(.sheet)
            }
            Spacer(minLength: 4)
            if model.showsBookNotes {
                if !model.highlights.isEmpty {
                    Text(Self.highlightsCount(model.highlights.count))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(ReaderStyle.peach)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ReaderStyle.peach.opacity(0.16), in: Capsule())
                }
            } else {
                headerButton("book", help: "Вернуться к заметкам к книге") {
                    LumenSounds.play(.navigate)
                    Task { await model.openBookNotes() }
                }
                headerButton("arrow.up.forward", help: "Открыть заметку целиком") {
                    openPage(notes.pageId)
                }
            }
            if closes {
                headerButton("xmark", help: "Скрыть заметки") { setNotes(false) }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// «1 выделение», «3 выделения», «7 выделений».
    nonisolated static func highlightsCount(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        let word: String
        if mod10 == 1, mod100 != 11 {
            word = "выделение"
        } else if (2...4).contains(mod10), !(12...14).contains(mod100) {
            word = "выделения"
        } else {
            word = "выделений"
        }
        return "\(count) \(word)"
    }

    private func sideTitle(_ notes: PageEditorModel) -> String {
        let title = notes.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Без названия" : title
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Ручка в зазоре между книгой и заметками: тянется, чтобы поменять ширину колонок.
    private func splitHandle(totalWidth: CGFloat) -> some View {
        Capsule()
            .fill(theme.textSecondary.opacity(isHandleHovered || dragStartFraction != nil ? 0.6 : 0.22))
            .frame(width: 4, height: 40)
            .frame(width: ReaderStyle.gap)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHandleHovered = hovering }
                #if os(macOS)
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                #endif
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartFraction ?? notesFraction
                        if dragStartFraction == nil { dragStartFraction = start }
                        notesFraction = min(max(start - value.translation.width / max(totalWidth, 1), 0.25), 0.65)
                    }
                    .onEnded { _ in dragStartFraction = nil }
            )
            .accessibilityLabel("Ширина заметок")
    }

    private func setNotes(_ isOpen: Bool) {
        LumenSounds.play(isOpen ? .panelOpen : .panelClose)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            showsNotes = isOpen
        }
    }

    // MARK: Панель

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if model.hasOriginalMode {
                Picker("Вид", selection: $model.documentMode) {
                    ForEach(ReaderModel.DocumentMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Текст можно выделять и выписывать, оригинал показывает файл как есть")
            }
            // На iPhone эти кнопки живут в нижней панели.
            if !isCompact {
                if !model.toc.isEmpty {
                    Button {
                        toggleToc()
                    } label: {
                        Label("Содержание", systemImage: "list.bullet.indent")
                    }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .help("Содержание (⌥⌘T)")
                }
                if hasPageThemes {
                    Button {
                        isAppearancePresented.toggle()
                    } label: {
                        Label("Оформление", systemImage: "textformat.size")
                    }
                    .help("Тема страницы, размер и шрифт")
                    .popover(isPresented: $isAppearancePresented) { appearancePanel }
                }
                Button {
                    showsHighlights = true
                } label: {
                    Label("Выделения", systemImage: "highlighter")
                }
                .popover(isPresented: $showsHighlights) { highlightsList }
                Button {
                    toggleNotes()
                } label: {
                    Label("Заметки", systemImage: "sidebar.right")
                }
                .help("Заметки рядом с книгой")
            }
            Button {
                Task {
                    await model.flush()
                    onShowInfo()
                }
            } label: {
                Label("О книге", systemImage: "chart.bar")
            }
            .help("Прогресс, время чтения и все заметки по книге")
        }
    }

    private func toggleToc() {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            isTocSheetPresented.toggle()
            return
        }
        #endif
        LumenSounds.play(showsToc ? .panelClose : .panelOpen)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            showsToc.toggle()
        }
    }

    private func toggleNotes() {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            isNotesSheetPresented.toggle()
            return
        }
        #endif
        setNotes(!showsNotes)
    }
}

/// Круглая кнопка на листе книги: перелистнуть главу.
private struct SheetRoundButtonStyle: ButtonStyle {
    let ink: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: 30, height: 30)
            .background(ink.opacity(configuration.isPressed ? 0.16 : 0.09), in: Circle())
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.35)
    }
}

// MARK: - Действия с выделением

/// Цветной кружок для выбора цвета выделения.
private struct HighlightSwatch: View {
    let color: HighlightColor
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: color.hex))
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(
                    isSelected ? AnyShapeStyle(Color.white.opacity(0.95)) : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .center)),
                    lineWidth: isSelected ? 2.5 : 1
                ))
                .shadow(color: Color(hex: color.hex).opacity(0.45), radius: 5, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.title)
        .accessibilityLabel("Выделить: \(color.title)")
    }
}

/// Мягкая плашка действий над выделением. На Mac и iPad это капсула в одну строку,
/// на iPhone две строки: цвета сверху и крупная кнопка «В заметки» снизу.
private struct HighlightActionBar<Extra: View>: View {
    var selectedColor: HighlightColor?
    var isCompact: Bool
    var onColor: (HighlightColor) -> Void
    var onExcerpt: () -> Void
    var onClose: () -> Void
    @ViewBuilder var extra: () -> Extra
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if isCompact {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        swatches
                        Spacer(minLength: 4)
                        extra()
                    }
                    HStack(spacing: 10) {
                        excerptButton(expands: true)
                        closeButton
                    }
                }
            } else {
                HStack(spacing: 10) {
                    swatches
                    Capsule().fill(.white.opacity(0.15)).frame(width: 1, height: 22)
                    excerptButton(expands: false)
                    extra()
                    closeButton
                }
            }
        }
        .buttonStyle(ReaderPillButtonStyle())
        .readerBarStyle(theme, isCompact: isCompact)
    }

    private var swatches: some View {
        ForEach(HighlightColor.allCases) { color in
            HighlightSwatch(color: color, isSelected: color == selectedColor) { onColor(color) }
        }
    }

    private func excerptButton(expands: Bool) -> some View {
        Button(action: onExcerpt) {
            Label("В заметки", systemImage: "quote.opening")
                .font(.system(size: expands ? 16 : 14, weight: .heavy, design: .rounded))
        }
        .buttonStyle(ReaderPillButtonStyle(isProminent: true, expands: expands))
        .keyboardShortcut("e", modifiers: .command)
        .help("Выделить и вставить цитату в заметки (⌘E)")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(ReaderPillButtonStyle(size: isCompact ? 46 : 34))
        .help("Закрыть")
    }
}

/// Плашка под выделенным текстом: покрасить, отправить в заметки, скопировать.
private struct SelectionBar: View {
    let model: ReaderModel
    var isCompact = false

    var body: some View {
        HighlightActionBar(
            selectedColor: nil,
            isCompact: isCompact,
            onColor: { color in Task { await model.highlightSelection(color) } },
            onExcerpt: { Task { await model.excerptSelection() } },
            onClose: { model.clearSelection() }
        ) {
            Button {
                if let text = model.selection?.text { copyToPasteboard(text) }
                model.showToast("Скопировано")
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Скопировать")
        }
    }
}

/// Плашка для уже сохранённого выделения: другой цвет, выписка, удаление.
private struct HighlightBar: View {
    let model: ReaderModel
    let highlight: Highlight
    var isCompact = false

    var body: some View {
        HighlightActionBar(
            selectedColor: highlight.color,
            isCompact: isCompact,
            onColor: { color in model.setColor(color, of: highlight.id) },
            onExcerpt: {
                model.addExcerpt(highlight)
                model.activeHighlightId = nil
            },
            onClose: { model.activeHighlightId = nil }
        ) {
            Button {
                model.deleteHighlight(highlight.id)
            } label: {
                Image(systemName: "trash")
            }
            .help("Удалить выделение")
        }
    }
}

/// Содержание книги: вложенные пункты, текущий в персиковой «таблетке», нажатие переходит к месту.
private struct TableOfContents: View {
    let model: ReaderModel
    /// В шторке на iPhone содержание закрывается сразу после перехода.
    var closesOnSelect = false
    /// Рядом с книгой содержание лежит стеклянной карточкой, в шторке фон даёт сама шторка.
    var isCard = true
    var onClose: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let current = model.currentTocEntry
        let currentIndex = current.flatMap { model.toc.firstIndex(of: $0) }
        let baseLevel = model.toc.map(\.level).min() ?? 0
        let content = VStack(spacing: 0) {
            HStack {
                Label("Содержание", systemImage: "list.bullet.indent")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Скрыть содержание")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.toc.enumerated()), id: \.element.id) { index, entry in
                            let isCurrent = index == currentIndex
                            let isRead = currentIndex.map { index < $0 } ?? false
                            let level = max(entry.level - baseLevel, 0)
                            Button {
                                model.open(entry)
                                if closesOnSelect { onClose() }
                            } label: {
                                row(entry, level: level, isCurrent: isCurrent, isRead: isRead)
                            }
                            .buttonStyle(.plain)
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
                }
                .onAppear {
                    if let current { proxy.scrollTo(current.id, anchor: .center) }
                }
                .onChange(of: current?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        if isCard {
            content.readerGlassCard(theme)
        } else {
            content
        }
    }

    private func row(_ entry: TocEntry, level: Int, isCurrent: Bool, isRead: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isCurrent ? ReaderStyle.peach : isRead ? ReaderStyle.peach.opacity(0.55) : Color.white.opacity(0.18))
                .frame(width: level == 0 ? 8 : 6, height: level == 0 ? 8 : 6)
                .background {
                    if isCurrent {
                        Circle().fill(ReaderStyle.peach.opacity(0.22)).frame(width: 16, height: 16)
                    }
                }
            Text(entry.title)
                .font(.system(size: level == 0 ? 14 : 13.5, weight: level == 0 || isCurrent ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isCurrent ? theme.textPrimary : theme.textPrimary.opacity(level == 0 ? 0.85 : 0.68))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12 + CGFloat(min(level, 4)) * 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [ReaderStyle.peach.opacity(0.26), ReaderStyle.lilac.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Все выделения книги: нажатие прокручивает к месту.
private struct HighlightsList: View {
    let model: ReaderModel
    var onClose: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if model.highlights.isEmpty {
                ContentUnavailableView {
                    Label("Выделений пока нет", systemImage: "highlighter")
                } description: {
                    Text("Выделите текст в книге: его можно покрасить или сразу отправить в заметки.")
                }
            } else {
                List {
                    ForEach(model.highlights) { highlight in
                        Button {
                            onClose()
                            LumenSounds.play(.navigate)
                            model.reveal(highlight)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Capsule()
                                    .fill(Color(hex: highlight.color.hex))
                                    .frame(width: 4)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(highlight.text)
                                        .font(.system(.callout, design: .serif))
                                        .lineLimit(4)
                                        .foregroundStyle(theme.textPrimary)
                                    Text(highlight.label)
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                model.addExcerpt(highlight)
                            } label: {
                                Label("В заметки", systemImage: "quote.opening")
                            }
                            Button {
                                copyToPasteboard(highlight.text)
                            } label: {
                                Label("Скопировать", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) {
                                model.deleteHighlight(highlight.id)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(ThemedBackground())
    }
}

private struct ReaderPillButtonStyle: ButtonStyle {
    var isProminent = false
    /// Растянуть на всю ширину: крупная кнопка «В заметки» на iPhone.
    var expands = false
    var size: CGFloat = 34
    @Environment(\.lumenTheme) private var theme

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isProminent ? ReaderStyle.onPeach : theme.textPrimary)
            .padding(.horizontal, isProminent ? 14 : 0)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(minWidth: size, minHeight: expands ? 46 : size)
            .background {
                if isProminent {
                    Capsule()
                        .fill(ReaderStyle.peachGradient)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                        .shadow(color: ReaderStyle.peachDeep.opacity(0.55), radius: 8, y: 4)
                } else {
                    Circle().fill(.white.opacity(0.08))
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

private extension View {
    func readerBarStyle(_ theme: Theme, isCompact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: isCompact ? 30 : 28, style: .continuous)
        return self
            .padding(.leading, isCompact ? 14 : 14)
            .padding(.trailing, isCompact ? 12 : 8)
            .padding(.vertical, isCompact ? 12 : 8)
            .background(theme.cardFill.opacity(0.5), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            ))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }
}

@MainActor
func copyToPasteboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}
