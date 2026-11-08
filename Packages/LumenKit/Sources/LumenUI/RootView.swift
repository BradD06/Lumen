import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

/// Пункт сайдбара и одновременно то, что показано в основной области.
public enum SidebarItem: Hashable, Codable, Sendable {
    case home
    case inbox
    /// База задач, открытая на «Сегодня».
    case tasks
    /// Библиотека, открытая на папке (`nil` это корень).
    case library(UUID?)
    case trash
    case page(UUID)
    /// Книга или файл в читалке, `highlight` прокручивает к выделению.
    case source(UUID, highlight: UUID?)
    /// Дашборд книги: прогресс, время чтения, заметки и выделения.
    case sourceInfo(UUID)
}

/// Корневой экран: сайдбар с разделами и деревом страниц, справа выбранный раздел.
/// Справа вкладки, у каждой своя история «Назад / Вперёд», вкладку можно разделить на две панели.
/// На iPhone (узкий экран) вместо сайдбара вкладки внизу, см. `PhoneRootView`.
public struct RootView: View {
    private let database: AppDatabase
    /// Вкладки и история переходов. UI-тесты начинают с чистого листа и ничего не сохраняют.
    @State private var workspace = Workspace(
        storageKey: ProcessInfo.processInfo.arguments.contains("-uiTesting") ? nil : "workspace.v1"
    )
    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    /// Окно выбора книги или файла из «Создать».
    @State private var isImportingBook = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// Ширина окна: на узком iPad (вертикально) вместо сайдбара полоса значков.
    @State private var windowWidth: CGFloat = 0
    private let focusMode = FocusModeState.shared
    /// К какому краю сейчас держат вкладку, и ширина области панелей для расчёта краёв.
    /// Минута дыхания поверх всего окна.
    @State private var isBreathing = false
    /// ⌘J: буквы на всём, что можно нажать.
    @State private var keyHints = KeyHintCenter()
    /// «Переместить в папку…» из ⌘K.
    @State private var paletteMove: PaletteMove?
    @State private var tabDropSide: TabDropSide?
    @State private var panesWidth: CGFloat = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme
    @AppStorage(ScreenOptions.tabStripKey) private var tabStripMode = TabStripMode.multiple
    @AppStorage(ScreenOptions.windowButtonsKey) private var showsWindowButtons = ScreenOptions.windowButtonsDefault

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Что открыто в активной панели. Выбор в сайдбаре и переходы открывают там же,
    /// а прошлое место уходит в историю, куда ведёт «Назад».
    private var selection: SidebarItem? {
        get { workspace.current }
        nonmutating set {
            if let newValue { workspace.open(newValue) }
        }
    }

    public var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                PhoneRootView(database: database)
                    // Плашка над вкладками, а не поверх них.
                    .lumenNotices(bottomPadding: 64)
            } else {
                splitView
                    .lumenNotices()
            }
            #else
            splitView
                .lumenNotices()
            #endif
        }
        .tint(theme.accent)
        .task { await purgeOldTrash() }
    }

    /// Что лежит в корзине дольше 30 дней, удаляется само при запуске.
    private func purgeOldTrash() async {
        do {
            let count = try await database.purgeTrash()
            if count > 0 { lumenLog.info("Removed \(count) old items from the trash") }
        } catch {
            lumenLog.error("Trash cleanup failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Темы «Бумага», «Монохром», «Кабинет» и «Дзен» держат всё на экране сами:
    /// сайдбар у них всегда закрыт, и открыть его нельзя (ни кнопкой, ни жестом с края).
    private var visibleColumns: Binding<NavigationSplitViewVisibility> {
        Binding {
            theme.layout.hidesSidebar ? .detailOnly : columnVisibility
        } set: { newValue in
            guard !theme.layout.hidesSidebar else { return }
            columnVisibility = newValue
        }
    }

    /// Переводит клавиши в панель: курсор уходит из текста прежней, а в заметку возвращается туда, где был.
    private func focusPane(_ index: Int) {
        guard workspace.isSplit else { return }
        withAnimation(.snappy) { workspace.focus(pane: index) }
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
        if case .page(let id) = workspace.selectedTab.panes[index].current,
           let editor = OpenPageEditors.shared.model(for: id) {
            editor.focusAgain()
        }
    }

    private func toggleSplit() {
        withAnimation(.snappy) { workspace.toggleSplit() }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: visibleColumns) {
            SidebarView(
                database: database,
                selection: Binding { selection } set: { selection = $0 },
                onNewPage: openNewPage,
                onNewFolder: openNewFolder,
                onNewDataTable: openNewDataTable,
                onSearch: { isSearchPresented = true },
                onCreate: create,
                onSettings: { isSettingsPresented = true }
            )
            // В темах со своей навигацией сайдбара нет совсем, и кнопки, открывающей его, тоже.
            .toolbar(removing: theme.layout.hidesSidebar ? .sidebarToggle : nil)
        } detail: {
            workspaceDetail
                .themedToolbar()
                .safeAreaInset(edge: .top, spacing: 0) { topBar }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // «Монохром»: вместо сайдбара командная строка, до всего дотягиваются через ⌘K.
                    if isCommandLine, !focusMode.isOn {
                        CommandLineBar(location: locationTitle) { isSearchPresented = true }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottom) { zenOrb }
                .safeAreaInset(edge: .leading, spacing: 0) {
                    if showsRail {
                        IconRail(
                            selection: selection,
                            onSelect: { selection = $0 },
                            onCreate: create,
                            onSearch: { isSearchPresented = true },
                            onSettings: { isSettingsPresented = true }
                        )
                        .transition(.move(edge: .leading))
                    }
                }
                .toolbar {
                    // Сочетания ⌘[ ⌘] ⌘\ живут в `tabShortcuts`: кнопки можно спрятать в настройках.
                    if showsWindowButtons {
                        ToolbarItemGroup(placement: .navigation) {
                            Button(action: workspace.goBack) {
                                Label("Назад", systemImage: "chevron.left")
                            }
                            .disabled(!workspace.canGoBack)
                            .help("Назад (⌘[)")

                            Button(action: workspace.goForward) {
                                Label("Вперёд", systemImage: "chevron.right")
                            }
                            .disabled(!workspace.canGoForward)
                            .help("Вперёд (⌘])")
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Label("Поиск", systemImage: "magnifyingglass")
                        }
                        .keyboardShortcut("k", modifiers: .command)

                        Menu {
                            ForEach(CreateKind.allCases) { kind in
                                Button {
                                    create(kind)
                                } label: {
                                    Label(kind.title, systemImage: kind.systemImage)
                                }
                            }
                        } label: {
                            Label("Создать", systemImage: "plus")
                        } primaryAction: {
                            newQuickNote()
                        }
                        .help("Новая заметка (⌘N). Удерживайте, чтобы выбрать, что создать")

                        if showsWindowButtons {
                            Button(action: toggleSplit) {
                                Label(
                                    workspace.isSplit ? "Одна панель" : "Разделить экран",
                                    systemImage: workspace.isSplit ? "rectangle" : "rectangle.split.2x1"
                                )
                            }
                            .help(workspace.isSplit ? "Убрать вторую панель (⌘\\)" : "Разделить экран на две панели (⌘\\)")
                        }
                    }
                }
        }
        .overlay {
            if isBreathing {
                BreathingView {
                    withAnimation(.easeInOut(duration: 0.6)) { isBreathing = false }
                }
                .transition(.opacity)
            }
        }
        .keyHintHost(keyHints)
        .environment(\.workspaceActions, workspaceActions)
        .environment(\.appActions, appActions(pane: nil))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .onChange(of: focusMode.isOn) { _, isOn in
            withAnimation(.easeInOut(duration: 0.3)) {
                columnVisibility = isOn ? .detailOnly : .automatic
            }
        }
        .task(id: workspace.referencedItems) { await removeMissingItems() }
        .sheet(isPresented: $isSearchPresented) {
            CommandPalette(
                database: database,
                commands: PaletteCommand.standard(actions: appActions(pane: nil), extra: paletteExtras),
                onOpen: { item, beside in
                    isSearchPresented = false
                    if beside {
                        withAnimation(.snappy) { workspace.openBeside(item) }
                    } else {
                        selection = item
                    }
                },
                onDismiss: { isSearchPresented = false }
            )
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet(database: database) { isSettingsPresented = false }
        }
        .sheet(item: $paletteMove) { move in
            MoveToFolderSheet(database: database, item: move.item, currentFolderId: move.folderId) {
                paletteMove = nil
            }
        }
        .fileImporter(
            isPresented: $isImportingBook,
            allowedContentTypes: SourceImporter.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                creator(pane: nil).importBooks(urls)
            }
        }
        // Книги из «Файлов» и Finder, ссылки lumen:// на страницы, книги и цитаты.
        .opensIncomingLinks(database: database) { selection = $0 }
    }

    /// Один экран в панели. Переходы с него открываются в этой же панели.
    @ViewBuilder
    private func detail(_ item: SidebarItem, pane: Int) -> some View {
        let open: (SidebarItem) -> Void = { workspace.open($0, inPane: pane) }
        switch item {
        case .home:
            HomeView(
                database: database,
                onOpen: { open(.page($0)) },
                onOpenSource: { open(.source($0, highlight: nil)) },
                onNewNote: newQuickNote,
                onShowInbox: { open(.inbox) },
                onShowLibrary: { open(.library(nil)) }
            )
        case .inbox:
            InboxView(database: database, onOpen: { open(.page($0)) }, onNewNote: newQuickNote)
        case .tasks:
            TasksScreen(database: database, onOpenPage: { open(.page($0)) })
        case .library(let folderId):
            LibraryView(
                database: database,
                folderId: folderId,
                onOpenFolder: { open(.library($0)) },
                onOpenPage: { open(.page($0)) },
                onOpenSource: { open(.source($0, highlight: nil)) },
                onShowSourceInfo: { open(.sourceInfo($0)) }
            )
            .id(folderId)
        case .trash:
            TrashView(database: database)
        case .page(let id):
            PageScreen(
                database: database,
                pageId: id,
                onOpenPage: { openLink(.page($0), from: pane) },
                onClose: { workspace.remove { $0 == .page(id) } },
                onOpenSource: { openLink(.source($0, highlight: $1), from: pane) }
            )
            .id(id)
        case .source(let id, let highlight):
            ReaderView(
                database: database,
                sourceId: id,
                highlightId: highlight,
                onOpenPage: { open(.page($0)) },
                onOpenSource: { open(.source($0, highlight: $1)) },
                onShowInfo: { open(.sourceInfo(id)) },
                onClose: { closeScreen(pane: pane, fallback: .library(nil)) }
            )
            .id(id)
        case .sourceInfo(let id):
            SourceDashboardView(
                database: database,
                sourceId: id,
                onRead: { open(.source(id, highlight: $0)) },
                onOpenPage: { open(.page($0)) }
            )
            .id(id)
        }
    }

    /// «Открыть в новой вкладке» и «Открыть рядом» для меню сайдбара и библиотеки.
    private var workspaceActions: WorkspaceActions {
        let workspace = workspace
        return WorkspaceActions(
            openInNewTab: { item in withAnimation(.snappy) { workspace.newTab(item) } },
            openBeside: { item in withAnimation(.snappy) { workspace.openBeside(item) } }
        )
    }

    /// Вкладки сверху, под ними одна или две панели.
    private var workspaceDetail: some View {
        VStack(spacing: 0) {
            if !focusMode.isOn, tabStripMode.shows(tabCount: workspace.tabs.count) {
                WorkspaceTabStrip(database: database, workspace: workspace)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            panes
                // Своя вкладка у каждого набора панелей: при переключении экраны создаются заново.
                .id(workspace.selectedTabId)
                // Вкладку можно бросить к левому или правому краю: она откроется рядом.
                // Подсветка только пока вкладку держат: после броска или отмены она гаснет.
                .overlay { TabDropHighlight(side: workspace.draggingTabId == nil ? nil : tabDropSide) }
                .onChange(of: workspace.draggingTabId) { _, id in
                    if id == nil { tabDropSide = nil }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { panesWidth = $0 }
                .onDrop(
                    of: [.lumenTab],
                    delegate: TabEdgeDropDelegate(workspace: workspace, width: panesWidth, side: $tabDropSide)
                )
        }
        .background {
            // Под вкладками и в просвете между панелями виден фон темы.
            // При разделении он приглушён, чтобы карточки панелей читались отдельно.
            ThemedBackground()
                .overlay(Color.black.opacity(workspace.isSplit ? 0.28 : 0).ignoresSafeArea())
        }
        .background { tabShortcuts }
    }

    @ViewBuilder
    private var panes: some View {
        let tab = workspace.selectedTab
        if tab.isSplit {
            // Две скруглённые карточки с просветом, сквозь который виден приглушённый фон темы.
            PaneSplit {
                pane(0, of: tab).paneCard(isFocused: tab.focusedPane == 0)
            } trailing: {
                pane(1, of: tab).paneCard(isFocused: tab.focusedPane == 1)
            }
            .padding(PaneStyle.inset)
        } else {
            pane(0, of: tab)
        }
    }

    /// Сочетания клавиш для вкладок, как в браузере. Кнопки невидимые: в панели окна им места нет.
    private var tabShortcuts: some View {
        ZStack {
            Button("Новая вкладка") { withAnimation(.snappy) { workspace.newTab() } }
                .keyboardShortcut("t", modifiers: .command)
            Button("Назад") { workspace.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!workspace.canGoBack)
            Button("Вперёд") { workspace.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!workspace.canGoForward)
            Button("Разделить экран", action: toggleSplit)
                .keyboardShortcut("\\", modifiers: .command)
            // Книга и заметка рядом: ⌥⌘← в левую панель, ⌥⌘→ в правую.
            Button("Левая панель") { focusPane(0) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Правая панель") { focusPane(1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            // ⌘W закрывает вкладку, а последнюю вкладку закрывает вместе с окном, как обычно.
            Button("Закрыть вкладку") { withAnimation(.snappy) { workspace.closeTab(workspace.selectedTabId) } }
                .keyboardShortcut(workspace.tabs.count > 1 ? KeyboardShortcut("w", modifiers: .command) : nil)
            Button("Следующая вкладка") { workspace.selectNextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Предыдущая вкладка") { workspace.selectPreviousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Следующая вкладка") { workspace.selectNextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Предыдущая вкладка") { workspace.selectPreviousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Новая заметка") { newQuickNote() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Новая задача") { create(.task) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Добавить книгу") { create(.book) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Режим фокуса") { focusMode.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            ForEach(1...9, id: \.self) { number in
                Button("Вкладка \(number)") { workspace.select(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pane(_ index: Int, of tab: WorkspaceTab) -> some View {
        let isActive = !tab.isSplit || tab.focusedPane == index
        return VStack(spacing: 0) {
            if tab.isSplit {
                PaneHeader(database: database, workspace: workspace, pane: index)
            }
            detail(tab.panes[index].current, pane: index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.isActivePane, isActive)
                .environment(\.isSplitScreen, tab.isSplit)
                .environment(\.besidePageId, besidePageId(of: index, in: tab))
                .environment(\.appActions, appActions(pane: index))
                // Щелчок в панели делает её активной. Без разделения жест выключен.
                .simultaneousGesture(
                    TapGesture().onEnded { workspace.focus(pane: index) },
                    including: tab.isSplit ? .all : .subviews
                )
        }
    }

    /// Ссылка из заметки. В разделённом экране она открывается во второй половине,
    /// а заметка остаётся на месте, чтобы писать дальше. Без разделения в той же панели.
    private func openLink(_ item: SidebarItem, from pane: Int) {
        let alreadyOpen = workspace.openLink(item, from: pane)
        // Эта книга уже открыта рядом: она прокручивается к выписке, а не открывается заново.
        if alreadyOpen, case .source(let id, let highlight?) = item {
            OpenReaders.shared.model(for: id)?.reveal(id: highlight)
        }
    }

    /// Страница в соседней панели, слева она или справа.
    private func besidePageId(of index: Int, in tab: WorkspaceTab) -> UUID? {
        guard tab.isSplit else { return nil }
        let other = index == 0 ? 1 : 0
        guard tab.panes.indices.contains(other), case .page(let id) = tab.panes[other].current else { return nil }
        return id
    }

    /// Закрыть экран: на шаг назад, а если идти некуда, туда, куда вёл старый «закрыть».
    private func closeScreen(pane: Int, fallback: SidebarItem) {
        workspace.focus(pane: pane)
        if workspace.canGoBack {
            workspace.goBack()
        } else {
            workspace.open(fallback, inPane: pane)
        }
    }

    /// Удалённые и убранные в корзину страницы, книги и папки пропадают из вкладок и истории.
    private func removeMissingItems() async {
        let items = workspace.referencedItems
        let observation = ValueObservation.tracking { db in try MissingItemsQuery.fetch(db, items: items) }
        do {
            for try await missing in observation.values(in: database.reader) where !missing.isEmpty {
                workspace.remove { missing.contains($0) }
            }
        } catch {}
    }

    /// Навигация сверху для тем без сайдбара: строка разделов «Бумаги» или комнаты «Кабинета».
    @ViewBuilder
    private var topBar: some View {
        if !focusMode.isOn {
            switch theme.layout {
            case .sectionBar:
                SectionBar(
                    database: database,
                    selection: selection,
                    onSelect: { selection = $0 },
                    onSettings: { isSettingsPresented = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            case .rooms:
                RoomsBar(
                    database: database,
                    selection: selection,
                    onSelect: { selection = $0 },
                    onSearch: { isSearchPresented = true },
                    onSettings: { isSettingsPresented = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            case .standard, .commandLine, .orb:
                EmptyView()
            }
        }
    }

    /// «Дзен»: вся навигация в одной дышащей точке внизу.
    @ViewBuilder
    private var zenOrb: some View {
        if theme.layout == .orb, !focusMode.isOn {
            ZenOrb(
                selection: selection,
                onSelect: { selection = $0 },
                onCreate: { newQuickNote() },
                onSearch: { isSearchPresented = true },
                onBreathe: startBreathing,
                onSettings: { isSettingsPresented = true }
            )
            .padding(.bottom, 18)
            .transition(.opacity)
        }
    }

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 0.6)) { isBreathing = true }
    }

    /// Тема устроена как командная строка («Монохром»): без сайдбара и полосы значков.
    private var isCommandLine: Bool { theme.layout == .commandLine }

    /// Короткое «где я» для командной строки.
    private var locationTitle: String {
        let place: String
        switch selection {
        case .home, nil: place = "сегодня"
        case .inbox: place = "входящие"
        case .tasks: place = "задачи"
        case .library: place = "библиотека"
        case .trash: place = "корзина"
        case .page: place = "страница"
        case .source: place = "книга"
        case .sourceInfo: place = "о книге"
        }
        return "lumen / \(place)"
    }

    /// Полоса значков вместо сайдбара: только на iPad, когда сайдбар спрятан.
    private var showsRail: Bool {
        #if os(iOS)
        guard horizontalSizeClass == .regular, !focusMode.isOn, !theme.layout.hidesSidebar else { return false }
        return columnVisibility == .detailOnly || (columnVisibility == .automatic && windowWidth > 0 && windowWidth < 1000)
        #else
        return false
        #endif
    }

    /// Открыть в панели `pane` (или в активной, если `nil`).
    private func open(_ item: SidebarItem, pane: Int?) {
        if let pane {
            workspace.open(item, inPane: pane)
        } else {
            selection = item
        }
    }

    private func creator(pane: Int?) -> Creator {
        Creator(database: database) { item in open(item, pane: pane) }
    }

    private func appActions(pane: Int?) -> AppActions {
        AppActions(
            open: { open($0, pane: pane) },
            create: { kind in
                if kind == .book {
                    isImportingBook = true
                } else {
                    creator(pane: pane).create(kind)
                }
            },
            capture: { text, asTask in creator(pane: pane).capture(text, asTask: asTask) },
            search: { isSearchPresented = true },
            settings: { isSettingsPresented = true },
            breathe: startBreathing
        )
    }

    private func create(_ kind: CreateKind) {
        appActions(pane: nil).create(kind)
    }

    /// Действия ⌘K, которым нужно окно: панели и режим фокуса.
    private var paletteExtras: [PaletteCommand] {
        var list: [PaletteCommand] = [
            PaletteCommand(
                id: "breathe",
                title: "Минута дыхания",
                systemImage: "wind",
                shortcut: nil,
                keywords: ["дзен", "тишина", "успокоиться", "пауза", "вдох"],
                run: startBreathing
            ),
            PaletteCommand(
                id: "split",
                title: workspace.isSplit ? "Убрать вторую панель" : "Разделить экран на две панели",
                systemImage: "rectangle.split.2x1",
                shortcut: "⌘\\",
                keywords: ["рядом", "две", "панели"],
                run: { withAnimation(.snappy) { workspace.toggleSplit() } }
            ),
            PaletteCommand(
                id: "focus",
                title: focusMode.isOn ? "Выйти из режима фокуса" : "Режим фокуса",
                systemImage: "viewfinder",
                shortcut: "⇧⌘F",
                keywords: ["тишина", "сосредоточиться", "писать"],
                run: { focusMode.toggle() }
            ),
            PaletteCommand(
                id: "key-hints",
                title: "Нажать на экране без мыши",
                systemImage: "keyboard",
                shortcut: "⌘J",
                keywords: ["клавиатура", "буквы", "подсказки", "мышь", "кнопка"],
                run: showKeyHintsSoon
            ),
            PaletteCommand(
                id: "new-tab",
                title: "Новая вкладка",
                systemImage: "plus.square.on.square",
                shortcut: "⌘T",
                keywords: ["вкладки"],
                run: { withAnimation(.snappy) { workspace.newTab() } }
            ),
            PaletteCommand(
                id: "next-tab",
                title: "Следующая вкладка",
                systemImage: "arrow.right.square",
                shortcut: "⌃⇥",
                keywords: ["вкладки", "переключить"],
                run: { workspace.selectNextTab() }
            ),
            PaletteCommand(
                id: "back",
                title: "Назад",
                systemImage: "chevron.left",
                shortcut: "⌘[",
                keywords: ["вернуться", "история"],
                run: { workspace.goBack() }
            ),
            PaletteCommand(
                id: "forward",
                title: "Вперёд",
                systemImage: "chevron.right",
                shortcut: "⌘]",
                keywords: ["история"],
                run: { workspace.goForward() }
            ),
        ]
        if workspace.tabs.count > 1 {
            list.append(PaletteCommand(
                id: "close-tab",
                title: "Закрыть вкладку",
                systemImage: "xmark.square",
                shortcut: "⌘W",
                keywords: ["вкладки"],
                run: { withAnimation(.snappy) { workspace.closeTab(workspace.selectedTabId) } }
            ))
        }
        if workspace.isSplit {
            list.append(PaletteCommand(
                id: "other-pane",
                title: "Перейти в соседнюю панель",
                systemImage: "rectangle.righthalf.inset.filled",
                shortcut: "⌥⌘→",
                keywords: ["панели", "рядом", "переключить"],
                run: { focusPane(workspace.selectedTab.focusedPane == 0 ? 1 : 0) }
            ))
        }
        list += currentItemCommands
        list += Theme.all.map { option in
            PaletteCommand(
                id: "theme-\(option.id)",
                title: "Тема: \(option.name)",
                systemImage: option.id == theme.id ? "checkmark.circle.fill" : "paintpalette",
                keywords: ["тема", "оформление", "цвет", "вид"],
                run: { UserDefaults.standard.set(option.id, forKey: Theme.storageKey) }
            )
        }
        list.append(
            PaletteCommand(
                id: "triage",
                title: "Разобрать входящие",
                systemImage: "rectangle.stack",
                keywords: ["входящие", "по одной"],
                run: { selection = .inbox }
            )
        )
        return list
    }

    /// Что можно сделать с открытой заметкой или книгой: то же, что в меню «Ещё», но с клавиатуры.
    private var currentItemCommands: [PaletteCommand] {
        let pane = workspace.selectedTab.focusedPane
        switch workspace.current {
        case .page(let id):
            let editor = OpenPageEditors.shared.model(for: id)
            var list: [PaletteCommand] = []
            if let editor {
                let isFavorite = editor.page?.isFavorite == true
                list.append(PaletteCommand(
                    id: "page-favorite",
                    title: isFavorite ? "Заметка: убрать из избранного" : "Заметка: в избранное",
                    systemImage: isFavorite ? "star.slash" : "star",
                    keywords: ["избранное", "звезда"],
                    run: { editor.toggleFavorite() }
                ))
            }
            list.append(PaletteCommand(
                id: "page-move",
                title: "Заметка: переместить в папку…",
                systemImage: "folder",
                keywords: ["папка", "перенести", "переместить", "разложить"],
                run: { moveSoon(.page(id)) }
            ))
            list.append(PaletteCommand(
                id: "page-link",
                title: "Заметка: скопировать ссылку",
                systemImage: "link",
                keywords: ["ссылка", "поделиться"],
                run: { copyLink(.page(id)) }
            ))
            if let editor {
                list.append(PaletteCommand(
                    id: "page-trash",
                    title: "Заметка: удалить",
                    systemImage: "trash",
                    keywords: ["корзина", "стереть"],
                    run: {
                        Task {
                            await editor.trash()
                            closeScreen(pane: pane, fallback: .home)
                        }
                    }
                ))
            }
            return list
        case .source(let id, _):
            return [
                PaletteCommand(
                    id: "source-info",
                    title: "Книга: о книге",
                    systemImage: "chart.bar",
                    shortcut: "⌥⌘I",
                    keywords: ["прогресс", "статистика", "время"],
                    run: { workspace.open(.sourceInfo(id)) }
                ),
                PaletteCommand(
                    id: "source-move",
                    title: "Книга: переместить в папку…",
                    systemImage: "folder",
                    keywords: ["папка", "перенести", "переместить"],
                    run: { moveSoon(.source(id)) }
                ),
                PaletteCommand(
                    id: "source-link",
                    title: "Книга: скопировать ссылку",
                    systemImage: "link",
                    keywords: ["ссылка", "поделиться"],
                    run: { copyLink(.source(id)) }
                ),
            ]
        default:
            return []
        }
    }

    /// Окно папок открывается, когда палитра уже закрылась: два листа сразу не показать.
    private func moveSoon(_ item: LibraryItemID) {
        Task {
            var folderId: UUID?
            switch item {
            case .page(let id): folderId = try? await database.page(id)?.folderId
            case .source(let id): folderId = try? await database.source(id)?.folderId
            case .folder: folderId = nil
            }
            try? await Task.sleep(for: .milliseconds(350))
            paletteMove = PaletteMove(item: item, folderId: folderId)
        }
    }

    /// Из ⌘K: сначала закрывается палитра, потом на экране появляются буквы.
    private func showKeyHintsSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            keyHints.activate()
        }
    }

    /// Главный сценарий: «+» и сразу пишешь, заметка попадает во «Входящие».
    private func newQuickNote() {
        Task {
            do {
                let page = try await database.createPage(inInbox: true)
                LumenSounds.play(.create)
                selection = .page(page.id)
            } catch {
                NoticeCenter.shared.report("Не удалось создать заметку", error)
            }
        }
    }

    private func openNewFolder(parentId: UUID?) {
        Task {
            do {
                let folder = try await database.createFolder(name: "Новая папка", parentId: parentId)
                LumenSounds.play(.create)
                selection = .library(folder.id)
            } catch {
                NoticeCenter.shared.report("Не удалось создать папку", error)
            }
        }
    }

    private func openNewDataTable() {
        Task {
            if let table = await NoticeCenter.shared.perform("Не удалось создать базу", {
                try await database.createDataTable(title: "Новая база", icon: "📋")
            }) {
                LumenSounds.play(.create)
                selection = .page(table.pageId)
            }
        }
    }

    private func openNewPage(parentId: UUID?) {
        Task {
            do {
                let page = try await database.createPage(parentId: parentId)
                LumenSounds.play(.create)
                selection = .page(page.id)
            } catch {
                NoticeCenter.shared.report("Не удалось создать страницу", error)
            }
        }
    }
}

#Preview {
    RootView(database: .preview())
}

/// Что переносят в папку из ⌘K и где оно лежит сейчас.
private struct PaletteMove: Identifiable {
    var item: LibraryItemID
    var folderId: UUID?
    var id: LibraryItemID { item }
}
