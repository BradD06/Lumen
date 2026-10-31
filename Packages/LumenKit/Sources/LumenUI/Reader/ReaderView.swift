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
    @AppStorage("reader.notesFraction") var notesFraction = 0.42
    @State private var isNotesSheetPresented = false
    @State var showsHighlights = false
    @State var isAppearancePresented = false
    @AppStorage("reader.tocOpen") var showsToc = false
    @State private var isTocSheetPresented = false
    @Environment(\.isActivePane) private var isActivePane
    @State var dragStartFraction: Double?
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

    func toggleToc() {
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

    func toggleNotes() {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            isNotesSheetPresented.toggle()
            return
        }
        #endif
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
