import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
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
    /// К какому краю сейчас держат вкладку, и ширина области панелей для расчёта краёв.
    @State private var tabDropSide: TabDropSide?
    @State private var panesWidth: CGFloat = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme

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
        .preferredColorScheme(.dark)
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

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(
                database: database,
                selection: Binding { selection } set: { selection = $0 },
                onNewPage: openNewPage,
                onNewFolder: openNewFolder,
                onNewDataTable: openNewDataTable
            )
        } detail: {
            workspaceDetail
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: workspace.goBack) {
                            Label("Назад", systemImage: "chevron.left")
                        }
                        .keyboardShortcut("[", modifiers: .command)
                        .disabled(!workspace.canGoBack)
                        .help("Назад (⌘[)")

                        Button(action: workspace.goForward) {
                            Label("Вперёд", systemImage: "chevron.right")
                        }
                        .keyboardShortcut("]", modifiers: .command)
                        .disabled(!workspace.canGoForward)
                        .help("Вперёд (⌘])")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Label("Поиск", systemImage: "magnifyingglass")
                        }
                        .keyboardShortcut("k", modifiers: .command)

                        Button(action: newQuickNote) {
                            Label("Быстрая заметка", systemImage: "square.and.pencil")
                        }
                        .keyboardShortcut("n", modifiers: .command)

                        Button {
                            withAnimation(.snappy) { workspace.toggleSplit() }
                        } label: {
                            Label(
                                workspace.isSplit ? "Одна панель" : "Разделить экран",
                                systemImage: workspace.isSplit ? "rectangle" : "rectangle.split.2x1"
                            )
                        }
                        .keyboardShortcut("\\", modifiers: .command)
                        .help(workspace.isSplit ? "Убрать вторую панель (⌘\\)" : "Разделить экран на две панели (⌘\\)")
                    }
                }
        }
        .environment(\.workspaceActions, workspaceActions)
        .task(id: workspace.referencedItems) { await removeMissingItems() }
        .sheet(isPresented: $isSearchPresented) {
            SearchView(
                database: database,
                onOpen: { pageId in
                    isSearchPresented = false
                    selection = .page(pageId)
                },
                onOpenSource: { sourceId, highlightId in
                    isSearchPresented = false
                    selection = .source(sourceId, highlight: highlightId)
                }
            )
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
                onOpenPage: { open(.page($0)) },
                onClose: { workspace.remove { $0 == .page(id) } },
                onOpenSource: { open(.source($0, highlight: $1)) }
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
            WorkspaceTabStrip(database: database, workspace: workspace)
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
        .background { tabShortcuts }
    }

    @ViewBuilder
    private var panes: some View {
        let tab = workspace.selectedTab
        if tab.isSplit {
            #if os(macOS)
            HSplitView {
                pane(0, of: tab).frame(minWidth: 320, maxWidth: .infinity)
                pane(1, of: tab).frame(minWidth: 320, maxWidth: .infinity)
            }
            #else
            HStack(spacing: 0) {
                pane(0, of: tab)
                Divider()
                pane(1, of: tab)
            }
            #endif
        } else {
            pane(0, of: tab)
        }
    }

    /// Сочетания клавиш для вкладок, как в браузере. Кнопки невидимые: в панели окна им места нет.
    private var tabShortcuts: some View {
        ZStack {
            Button("Новая вкладка") { withAnimation(.snappy) { workspace.newTab() } }
                .keyboardShortcut("t", modifiers: .command)
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
                .environment(\.besidePageId, besidePageId(of: index, in: tab))
                // Щелчок в панели делает её активной. Без разделения жест выключен.
                .simultaneousGesture(
                    TapGesture().onEnded { workspace.focus(pane: index) },
                    including: tab.isSplit ? .all : .subviews
                )
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
