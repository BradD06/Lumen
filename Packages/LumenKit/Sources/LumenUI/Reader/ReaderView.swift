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
    @State var model: ReaderModel
    let highlightId: UUID?
    var onOpenPage: (UUID) -> Void
    var onOpenSource: (UUID, UUID?) -> Void
    var onShowInfo: () -> Void
    var onClose: () -> Void

    @AppStorage("reader.palette") var paletteRaw = ReaderAppearance.Palette.night.rawValue
    @AppStorage("reader.fontSize") var fontSize = 18
    @AppStorage("reader.typeface") var typefaceRaw = ReaderAppearance.Typeface.serif.rawValue
    @AppStorage("reader.notesOpen") var showsNotes = true
    /// Где заметки: рядом с книгой или под ней и с какой стороны. Своё у каждой книги.
    @State var arrangement: PaneArrangement
    /// Читалка выше, чем шире (iPad стоя): заметки тогда сами встают под книгу.
    @State var isTallReader = false
    /// Заметки сейчас на экране рядом с книгой или под ней (не шторкой).
    @State var isNotesPaneShown = false
    @State private var isNotesSheetPresented = false
    @State var showsHighlights = false
    @State var isAppearancePresented = false
    @AppStorage("reader.tocOpen") var showsToc = false
    /// Полоса прогресса под книгой: всегда или только под мышью (настройки, «Что показывать на экране»).
    @AppStorage(ScreenOptions.readerProgressKey) var progressMode = ReaderProgressMode.defaultMode
    @State var isFooterHovered = false
    @State private var isTocSheetPresented = false
    @Environment(\.isActivePane) private var isActivePane
    @Environment(\.isSplitScreen) private var isSplitScreen
    #if os(macOS)
    /// Стрелки листают книгу, ⌥⌘← → переходят между книгой и заметками сбоку.
    @State private var keys = ReaderKeys()
    #endif
    @Environment(\.besidePageId) private var besidePageId
    @State var dragStartFraction: Double?
    /// Доля заметок, пока тянут ручку. В настройки она уходит, когда ручку отпустили:
    /// запись в UserDefaults на каждый сдвиг мыши заставляла перестраиваться весь экран.
    @State var dragFraction: Double?
    @State var isHandleHovered = false
    @State var isPagePickerPresented = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) var theme
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
        _arrangement = State(initialValue: ReaderLayoutStore.load(sourceId))
        self.highlightId = highlightId
        self.onOpenPage = onOpenPage
        self.onOpenSource = onOpenSource
        self.onShowInfo = onShowInfo
        self.onClose = onClose
    }

    var appearance: ReaderAppearance {
        ReaderAppearance(
            palette: ReaderAppearance.Palette(rawValue: paletteRaw) ?? .night,
            fontSize: fontSize,
            typeface: ReaderAppearance.Typeface(rawValue: typefaceRaw) ?? .serif
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let isTall = PaneArrangement.isTall(width: Double(size.width), height: Double(size.height))
            let axis = arrangement.axis(isTall: isTall)
            let fraction = dragFraction ?? arrangement.fraction(for: axis)
            // Панель видна и до первой заметки: в ней кнопка начать заметку.
            let canShowPane = axis == .stacked ? canStack(size) : isWide(size.width)
            let showsNotesPane: Bool = canShowPane && showsNotes && model.source != nil
            let notesWidth: CGFloat = showsNotesPane && axis == .sideBySide ? (size.width * CGFloat(fraction)).rounded() : 0
            // Содержание встаёт отдельной колонкой, только если книге останется достаточно места.
            let tocAsColumn: Bool = showsToc && !isCompact && !model.toc.isEmpty
                && size.width - notesWidth - 300 > 460
            let paneLength: CGFloat = axis == .stacked
                ? size.height
                : size.width - (tocAsColumn ? 260 + ReaderStyle.gap : 0)
            HStack(spacing: 0) {
                if tocAsColumn {
                    tableOfContents
                        .frame(width: 260)
                        .padding(.trailing, ReaderStyle.gap)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                // Книга, ручка и заметки всегда в одном порядке: раскладка сама ставит их
                // рядом или друг под другом, и книга при этом не открывается заново.
                TwoPaneLayout(
                    axis: axis,
                    isSwapped: arrangement.isSwapped,
                    secondFraction: CGFloat(fraction),
                    gap: ReaderStyle.gap,
                    minLength: axis == .stacked ? 180 : 300
                ) {
                    readerPane(tocOverlay: !tocAsColumn)
                    if showsNotesPane {
                        splitHandle(axis: axis, length: paneLength)
                        notesPane(model.notes)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
            }
            .padding(.horizontal, isCompact ? 8 : ReaderStyle.gap)
            .padding(.top, isCompact ? 4 : 6)
            .padding(.bottom, isCompact ? 8 : ReaderStyle.gap)
            .onChange(of: canShowPane) { _, canShow in
                if canShow { isNotesSheetPresented = false }
            }
            .onChange(of: isTall, initial: true) { _, tall in isTallReader = tall }
            .onChange(of: showsNotesPane, initial: true) { _, shown in
                isNotesPaneShown = shown
                #if os(macOS)
                keys.hasNotesBeside = shown
                #endif
            }
        }
        .fontDesign(.rounded)
        .background(ThemedBackground())
        .navigationTitle(model.source?.displayTitle ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // В разделённом экране кнопки читалки только у активной панели.
            if isActivePane { toolbar }
        }
        .sheet(isPresented: $isTocSheetPresented) {
            TableOfContents(model: model, closesOnSelect: true, isCard: false) { isTocSheetPresented = false }
                .fontDesign(.rounded)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $isNotesSheetPresented) {
            NavigationStack {
                VStack(spacing: 0) {
                    notesHeader(model.notes, closes: false)
                    notesBody(model.notes)
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
        .task {
            model.web.setAppearance(appearance)
            model.pdf.setPageStyle(appearance.palette.pdfStyle)
            await model.load()
        }
        .task { await model.observeHighlights() }
        .onAppear { OpenReaders.shared.register(model, id: model.sourceId) }
        #if os(macOS)
        .onAppear { keys.install(model: model) }
        .onDisappear { keys.remove() }
        .onChange(of: isActivePane, initial: true) { _, active in keys.isActive = active }
        .onChange(of: isSplitScreen, initial: true) { _, split in keys.isSplitScreen = split }
        #endif
        .onChange(of: besidePageId, initial: true) { _, id in model.besidePageId = id }
        .onChange(of: arrangement) { _, arrangement in
            ReaderLayoutStore.save(arrangement, for: model.sourceId)
        }
        .onChange(of: appearance) { _, appearance in
            model.web.setAppearance(appearance)
            model.pdf.setPageStyle(appearance.palette.pdfStyle)
        }
        .onChange(of: highlightId) { _, id in
            if let id { model.reveal(id: id) }
        }
        .onDisappear {
            OpenReaders.shared.unregister(model, id: model.sourceId)
            Task { await model.flush() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Свернули приложение: место чтения и время сохраняются сразу.
            if phase != .active { Task { await model.flush() } }
        }
    }

    /// Узкий экран iPhone: панели открываются шторками, кнопки собраны в нижнюю панель.
    var isCompact: Bool {
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

    /// Заметки под книгой помещаются: обоим листам хватает высоты.
    private func canStack(_ size: CGSize) -> Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && size.height > 560 && size.width > 400
        #else
        return size.height > 520 && size.width > 420
        #endif
    }

    /// Текущая ось: рядом или друг под другом, для окна, какое оно сейчас.
    var notesAxis: PaneArrangement.Axis {
        arrangement.axis(isTall: isTallReader)
    }

    func setNotesAxis(_ axis: PaneArrangement.Axis) {
        guard axis != notesAxis else { return }
        LumenSounds.play(.toggle)
        withAnimation(LumenMotion.standard) {
            arrangement.setAxis(axis, isTall: isTallReader)
        }
    }

    func swapNotesSide() {
        LumenSounds.play(.toggle)
        withAnimation(LumenMotion.standard) {
            arrangement.swap()
        }
    }

    /// Значок кнопки «Заметки»: с той стороны, где заметки встанут.
    private var notesSymbol: String {
        switch (notesAxis, arrangement.isSwapped) {
        case (.sideBySide, false): "sidebar.right"
        case (.sideBySide, true): "sidebar.left"
        case (.stacked, false): "rectangle.bottomhalf.inset.filled"
        case (.stacked, true): "rectangle.tophalf.inset.filled"
        }
    }

    func openPage(_ id: UUID) {
        isNotesSheetPresented = false
        onOpenPage(id)
    }

    /// Ссылки из заметки рядом открываются там же, рядом с книгой.
    func openSidePage(_ id: UUID) {
        isPagePickerPresented = false
        LumenSounds.play(.navigate)
        Task { await model.openSidePage(id) }
    }

    /// Выписка из этой же книги прокручивает к месту, из другой открывает ту книгу.
    func openSource(_ sourceId: UUID, _ highlightId: UUID?) {
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

    // MARK: Панель

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if model.hasOriginalMode {
                if isCompact {
                    // На iPhone в верхней панели мало места: вместо двух кнопок одна, с выбором в меню.
                    Menu {
                        Picker("Вид", selection: $model.documentMode) {
                            ForEach(ReaderModel.DocumentMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                    } label: {
                        Label("Вид: \(model.documentMode.title)", systemImage: model.documentMode.systemImage)
                    }
                } else {
                    Picker("Вид", selection: $model.documentMode) {
                        ForEach(ReaderModel.DocumentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help(model.source?.format == .pdf
                        ? "Текст: как книга, по главам и с любым размером шрифта. Оригинал: страницы как в файле"
                        : "Текст можно выделять и выписывать, оригинал показывает файл как есть")
                }
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
                    .keyboardShortcut("a", modifiers: [.command, .option])
                    .help("Тема страницы, размер и шрифт (⌥⌘A)")
                    .popover(isPresented: $isAppearancePresented) { appearancePanel }
                }
                Button {
                    showsHighlights = true
                } label: {
                    Label("Выделения", systemImage: "highlighter")
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .help("Выделения в этой книге (⌥⌘L)")
                .popover(isPresented: $showsHighlights) { highlightsList }
                if isNotesPaneShown {
                    PaneArrangementControls(
                        axis: notesAxis,
                        subject: "книгу и заметки",
                        onAxis: setNotesAxis,
                        onSwap: swapNotesSide
                    )
                }
                Button {
                    toggleNotes()
                } label: {
                    Label("Заметки", systemImage: notesSymbol)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .help(notesAxis == .stacked ? "Заметки под книгой (⌥⌘N)" : "Заметки рядом с книгой (⌥⌘N)")
            }
            Button {
                Task {
                    await model.flush()
                    onShowInfo()
                }
            } label: {
                Label("О книге", systemImage: "chart.bar")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Прогресс, время чтения и все заметки по книге (⌥⌘I)")
        }
    }

    func toggleToc() {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            isTocSheetPresented.toggle()
            return
        }
        #endif
        LumenSounds.play(showsToc ? .panelClose : .panelOpen)
        withAnimation(LumenMotion.standard) {
            showsToc.toggle()
        }
    }

    func toggleNotes() {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            // Открыли редактор заметок: тут заметки к книге и заводятся, если их ещё не было.
            if !isNotesSheetPresented { Task { await model.ensureNotes() } }
            isNotesSheetPresented.toggle()
            return
        }
        #endif
        if !showsNotes { Task { await model.ensureNotes() } }
        setNotes(!showsNotes)
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
