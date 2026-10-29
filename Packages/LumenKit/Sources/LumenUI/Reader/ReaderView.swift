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
struct ReaderView: View {
    @State private var model: ReaderModel
    let highlightId: UUID?
    var onOpenPage: (UUID) -> Void
    var onOpenSource: (UUID, UUID?) -> Void
    var onClose: () -> Void

    @AppStorage("reader.palette") private var paletteRaw = ReaderAppearance.Palette.night.rawValue
    @AppStorage("reader.fontSize") private var fontSize = 18
    @AppStorage("reader.serif") private var serif = true
    @AppStorage("reader.notesOpen") private var showsNotes = true
    @AppStorage("reader.notesFraction") private var notesFraction = 0.42
    @State private var isNotesSheetPresented = false
    @State private var showsHighlights = false
    @AppStorage("reader.tocOpen") private var showsToc = false
    @State private var isTocSheetPresented = false
    @State private var dragStartFraction: Double?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme

    init(
        database: AppDatabase,
        sourceId: UUID,
        highlightId: UUID?,
        onOpenPage: @escaping (UUID) -> Void,
        onOpenSource: @escaping (UUID, UUID?) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: ReaderModel(database: database, sourceId: sourceId, highlightId: highlightId))
        self.highlightId = highlightId
        self.onOpenPage = onOpenPage
        self.onOpenSource = onOpenSource
        self.onClose = onClose
    }

    private var appearance: ReaderAppearance {
        ReaderAppearance(palette: ReaderAppearance.Palette(rawValue: paletteRaw) ?? .night, fontSize: fontSize, serif: serif)
    }

    var body: some View {
        GeometryReader { geometry in
            let isWide = isWide(geometry.size.width)
            HStack(spacing: 0) {
                readerPane
                if isWide, showsNotes, let notes = model.notes {
                    splitHandle(totalWidth: geometry.size.width)
                    notesPane(notes)
                        .frame(width: geometry.size.width * notesFraction)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .onChange(of: isWide) { _, wide in
                if wide { isNotesSheetPresented = false }
            }
        }
        .background(ThemedBackground())
        .navigationTitle(model.source?.displayTitle ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .sheet(isPresented: $isTocSheetPresented) {
            TableOfContents(model: model, closesOnSelect: true) { isTocSheetPresented = false }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isNotesSheetPresented) {
            if let notes = model.notes {
                NavigationStack {
                    PageEditorView(model: notes, onOpenPage: openPage, onOpenSource: openSource)
                        .navigationTitle("Заметки")
                }
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .task {
            model.web.setAppearance(appearance)
            await model.load()
        }
        .task { await model.observeHighlights() }
        .onChange(of: appearance) { _, appearance in
            model.web.setAppearance(appearance)
        }
        .onChange(of: highlightId) { _, id in
            if let id { model.reveal(id: id) }
        }
        .onDisappear {
            Task { await model.flush() }
        }
    }

    /// Узкий экран iPhone: панели открываются шторками.
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

    private var readerPane: some View {
        ZStack(alignment: .bottom) {
            pageBackground
            document
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    // Содержание плавает над книгой слева и не сдвигает текст.
                    if showsToc, !model.toc.isEmpty, !isCompact {
                        TableOfContents(model: model) {
                            LumenSounds.play(.panelClose)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { showsToc = false }
                        }
                        .frame(width: 290)
                        .frame(maxHeight: .infinity)
                        .padding(.leading, 12)
                        .padding(.vertical, 12)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            VStack(spacing: 10) {
                if let toast = model.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if model.selection != nil {
                    SelectionBar(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let id = model.activeHighlightId, let highlight = model.highlights.first(where: { $0.id == id }) {
                    HighlightBar(model: model, highlight: highlight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .animation(.spring(duration: 0.3), value: model.selection)
            .animation(.spring(duration: 0.3), value: model.activeHighlightId)
            .animation(.spring(duration: 0.3), value: model.toast)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pageBackground: some View {
        if case .web = model.content, let hex = appearance.backgroundHex {
            Color(hex: hex).ignoresSafeArea()
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var document: some View {
        switch model.content {
        case .loading:
            ProgressView("Открываю…")
                .tint(theme.accent)
        case .web:
            WebReaderView(controller: model.web)
        case .pdf:
            PDFReaderView(controller: model.pdf)
        case .image:
            if let source = model.source {
                ScrollView([.horizontal, .vertical]) {
                    AttachmentImage(name: source.file, attachments: model.database.attachments)
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
            }
        }
    }

    /// Прогресс и переход по главам.
    @ViewBuilder
    private var footer: some View {
        let sections = model.sections
        if case .web = model.content {
            HStack(spacing: 12) {
                if sections.count > 1 {
                    Button {
                        model.openSection(model.section - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(model.section == 0)
                    .help("Предыдущая глава")
                }
                progressBar
                if sections.count > 1 {
                    Button {
                        model.openSection(model.section + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(model.section >= sections.count - 1)
                    .help("Следующая глава")
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(footerColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
            .frame(maxWidth: 520)
        } else if case .pdf = model.content {
            progressBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
                .frame(maxWidth: 420)
        }
    }

    private var progressBar: some View {
        HStack(spacing: 10) {
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .tint(theme.accent)
            Text(model.positionLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(footerColor.opacity(0.8))
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var footerColor: Color {
        appearance.palette == .night || model.content == .pdf ? theme.textPrimary : Color(hex: 0x3B2E25)
    }

    // MARK: Заметки

    private func notesPane(_ notes: PageEditorModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("Заметки", systemImage: "note.text")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("\(model.highlights.count) выдел.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                Button {
                    setNotes(false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(theme.cardFill, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Скрыть заметки")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider().opacity(0.4)
            PageEditorView(model: notes, onOpenPage: openPage, onOpenSource: openSource)
        }
        .background(.ultraThinMaterial)
        .background(theme.cardFill.opacity(0.4))
    }

    /// Ручка между книгой и заметками: тянется, чтобы поменять ширину колонок.
    private func splitHandle(totalWidth: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(theme.cardStroke).frame(width: 1)
            Capsule()
                .fill(theme.textSecondary.opacity(0.5))
                .frame(width: 4, height: 36)
        }
        .frame(width: 10)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering in
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        #endif
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
            if !model.toc.isEmpty {
                Button {
                    toggleToc()
                } label: {
                    Label("Содержание", systemImage: "list.bullet.indent")
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .help("Содержание (⌥⌘T)")
            }
            if case .web = model.content {
                appearanceMenu
            }
            Button {
                showsHighlights = true
            } label: {
                Label("Выделения", systemImage: "highlighter")
            }
            .popover(isPresented: $showsHighlights) {
                HighlightsList(model: model) { showsHighlights = false }
                    .frame(minWidth: 320, minHeight: 360)
                    .presentationCompactAdaptation(.sheet)
            }
            Button {
                toggleNotes()
            } label: {
                Label("Заметки", systemImage: "sidebar.right")
            }
            .help("Заметки рядом с книгой")
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

    private var appearanceMenu: some View {
        Menu {
            Picker("Тема", selection: $paletteRaw) {
                ForEach(ReaderAppearance.Palette.allCases) { palette in
                    Text(palette.title).tag(palette.rawValue)
                }
            }
            Divider()
            Button {
                fontSize = max(fontSize - 1, ReaderAppearance.fontSizes.lowerBound)
            } label: {
                Label("Мельче", systemImage: "textformat.size.smaller")
            }
            Button {
                fontSize = min(fontSize + 1, ReaderAppearance.fontSizes.upperBound)
            } label: {
                Label("Крупнее", systemImage: "textformat.size.larger")
            }
            Toggle("Шрифт с засечками", isOn: $serif)
        } label: {
            Label("Оформление", systemImage: "textformat.size")
        }
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
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.95 : 0.25), lineWidth: isSelected ? 2.5 : 1))
                .shadow(color: Color(hex: color.hex).opacity(0.5), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help(color.title)
        .accessibilityLabel("Выделить: \(color.title)")
    }
}

/// Плашка под выделенным текстом: покрасить, отправить в заметки, скопировать.
private struct SelectionBar: View {
    let model: ReaderModel
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HighlightColor.allCases) { color in
                HighlightSwatch(color: color) {
                    Task { await model.highlightSelection(color) }
                }
            }
            Divider().frame(height: 22)
            Button {
                Task { await model.excerptSelection() }
            } label: {
                Label("В заметки", systemImage: "quote.opening")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(ReaderPillButtonStyle(isProminent: true))
            .keyboardShortcut("e", modifiers: .command)
            .help("Выделить и вставить цитату в заметки (⌘E)")
            Button {
                if let text = model.selection?.text { copyToPasteboard(text) }
                model.showToast("Скопировано")
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(ReaderPillButtonStyle())
            .help("Скопировать")
            Button {
                model.clearSelection()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(ReaderPillButtonStyle())
            .help("Снять выделение")
        }
        .readerBarStyle(theme)
    }
}

/// Плашка для уже сохранённого выделения: другой цвет, выписка, удаление.
private struct HighlightBar: View {
    let model: ReaderModel
    let highlight: Highlight
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HighlightColor.allCases) { color in
                HighlightSwatch(color: color, isSelected: color == highlight.color) {
                    model.setColor(color, of: highlight.id)
                }
            }
            Divider().frame(height: 22)
            Button {
                model.addExcerpt(highlight)
                model.activeHighlightId = nil
            } label: {
                Label("В заметки", systemImage: "quote.opening")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(ReaderPillButtonStyle(isProminent: true))
            Button {
                model.deleteHighlight(highlight.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(ReaderPillButtonStyle())
            .help("Удалить выделение")
            Button {
                model.activeHighlightId = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(ReaderPillButtonStyle())
        }
        .readerBarStyle(theme)
    }
}

/// Содержание книги: вложенные пункты, текущий подсвечен, нажатие переходит к месту.
private struct TableOfContents: View {
    let model: ReaderModel
    /// В шторке на iPhone содержание закрывается сразу после перехода.
    var closesOnSelect = false
    var onClose: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let current = model.currentTocEntry
        let baseLevel = model.toc.map(\.level).min() ?? 0
        VStack(spacing: 0) {
            HStack {
                Label("Содержание", systemImage: "list.bullet.indent")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(theme.cardFill, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Скрыть содержание")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.toc) { entry in
                            let isCurrent = entry == current
                            let level = max(entry.level - baseLevel, 0)
                            Button {
                                model.open(entry)
                                if closesOnSelect { onClose() }
                            } label: {
                                Text(entry.title)
                                    .font(level == 0 ? .callout.weight(isCurrent ? .bold : .semibold) : .callout.weight(isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isCurrent ? theme.textPrimary : theme.textPrimary.opacity(level == 0 ? 0.92 : 0.72))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 10 + CGFloat(min(level, 4)) * 14)
                                    .padding(.trailing, 10)
                                    .padding(.vertical, 7)
                                    .background {
                                        if isCurrent {
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(theme.accent.opacity(0.24))
                                                .overlay(alignment: .leading) {
                                                    Capsule().fill(theme.accent).frame(width: 3).padding(.vertical, 6)
                                                }
                                        }
                                    }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
            LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
            lineWidth: 1
        ))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
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
    @Environment(\.lumenTheme) private var theme

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isProminent ? theme.vividCard(0).foreground : theme.textPrimary)
            .padding(.horizontal, isProminent ? 12 : 8)
            .frame(minWidth: 30, minHeight: 30)
            .background {
                if isProminent {
                    Capsule().fill(LinearGradient(colors: theme.vividCard(0).colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Capsule().fill(theme.cardFill)
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private extension View {
    func readerBarStyle(_ theme: Theme) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            ))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
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
