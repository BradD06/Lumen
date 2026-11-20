import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

#if os(iOS)
import Combine
import UIKit

/// Куда можно перейти внутри вкладки на iPhone. Каждый переход кладётся в стек вкладки,
/// поэтому «Назад» возвращает туда, откуда пришли: из книги в заметку, из заметки в папку.
enum PhoneRoute: Hashable {
    case page(UUID)
    case source(UUID, highlight: UUID?)
    /// Дашборд книги: прогресс, время чтения, заметки и выделения.
    case sourceInfo(UUID)
    case folder(UUID)
    case inbox
    case trash
    /// «Чтение»: время по всем книгам, открывается с полки и со стола.
    case reading
}

extension PhoneRoute {
    /// Заметка и книга открыты во весь экран, без капсулы разделов внизу.
    var hidesTabCapsule: Bool {
        switch self {
        case .page, .source: true
        default: false
        }
    }
}

enum PhoneTab: Hashable {
    case home
    case inbox
    case tasks
    case library
    case search
}

/// iPhone: внизу слева стеклянная капсула с четырьмя разделами, справа отдельные круглые
/// кнопки поиска и «+», под большим пальцем. У каждого раздела свой стек экранов.
/// Сами экраны те же, что на Mac и iPad, они подстраиваются под узкую ширину.
/// Избранное на телефоне в начале списка на полке, корзина и iCloud в её меню.
struct PhoneRootView: View {
    let database: AppDatabase

    @State private var tab: PhoneTab = .home
    @State private var paths: [PhoneTab: [PhoneRoute]] = [:]
    @State private var isCreating = false
    @State private var isImportingBook = false
    @State private var isSettingsPresented = false
    /// Пока открыта клавиатура, капсула разделов прячется: иначе она ехала бы над клавиатурой.
    @State private var isKeyboardShown = false

    var body: some View {
        // Разделы те же, что в острове на Mac и iPad: названия и значки из `StudyRoom`.
        TabView(selection: $tab) {
            Tab(StudyRoom.desk.title, systemImage: StudyRoom.desk.systemImage, value: PhoneTab.home) {
                stack(.home) {
                    HomeView(
                        database: database,
                        onOpen: { push(.page($0)) },
                        onOpenSource: { push(.source($0, highlight: nil)) },
                        onNewNote: newQuickNote,
                        onShowInbox: { tab = .inbox },
                        onShowLibrary: { tab = .library }
                    )
                    .toolbar { settingsButton }
                }
            }
            Tab(StudyRoom.notes.title, systemImage: StudyRoom.notes.systemImage, value: PhoneTab.inbox) {
                stack(.inbox) {
                    InboxView(database: database, onOpen: { push(.page($0)) }, onNewNote: newQuickNote)
                }
            }
            Tab(StudyRoom.tasks.title, systemImage: StudyRoom.tasks.systemImage, value: PhoneTab.tasks) {
                stack(.tasks) {
                    TasksScreen(database: database, onOpenPage: { push(.page($0)) })
                }
            }
            Tab(StudyRoom.shelf.title, systemImage: StudyRoom.shelf.systemImage, value: PhoneTab.library) {
                stack(.library) {
                    library(folderId: nil)
                        .toolbar {
                            readingButton
                        }
                }
            }
            Tab("Поиск", systemImage: "magnifyingglass", value: PhoneTab.search) {
                stack(.search) {
                    SearchView(
                        database: database,
                        isEmbedded: true,
                        onOpen: { push(.page($0)) },
                        onOpenSource: { push(.source($0, highlight: $1)) }
                    )
                }
            }
        }
        // Системная полоса вкладок спрятана (`stack`), вместо неё капсула «Острова».
        // Место под неё экраны оставляют сами (`capsuleRoom`).
        .overlay(alignment: .bottom) {
            if showsTabCapsule {
                PhoneTabCapsule(
                    database: database,
                    selection: tab,
                    onSelect: select,
                    onSearch: { select(.search) },
                    onCreate: { isCreating = true }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(LumenMotion.standard, value: showsTabCapsule)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardShown = false
        }
        .overlay { LampLight() }
        // Книги из «Файлов», Telegram и «Поделиться», ссылки lumen:// на страницы, книги и цитаты.
        .opensIncomingLinks(database: database, open: openIncoming)
        .environment(\.appActions, appActions)
        .sheet(isPresented: $isCreating) {
            CreateSheet(
                onCapture: { text, asTask in creator.capture(text, asTask: asTask) },
                onSelect: { appActions.create($0) }
            )
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet(database: database) { isSettingsPresented = false }
        }
        .fileImporter(
            isPresented: $isImportingBook,
            allowedContentTypes: SourceImporter.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                creator.importBooks(urls)
            }
        }
    }

    private var creator: Creator {
        Creator(database: database, open: openIncoming)
    }

    private var appActions: AppActions {
        AppActions(
            owner: "phone",
            open: openIncoming,
            create: { kind in
                if kind == .book {
                    // Окно выбора файла открывается после того, как закроется окно «Создать».
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        isImportingBook = true
                    }
                } else {
                    creator.create(kind)
                }
            },
            capture: { text, asTask in creator.capture(text, asTask: asTask) },
            search: { tab = .search },
            settings: { isSettingsPresented = true }
        )
    }

    /// Капсула разделов видна на экранах разделов и папок. Заметка и книга открыты
    /// во весь экран, и пока печатаешь, капсула тоже не мешает.
    private var showsTabCapsule: Bool {
        !isKeyboardShown && paths[tab]?.last?.hidesTabCapsule != true
    }

    /// Пустое место внизу экрана раздела, чтобы конец списка не прятался под капсулой.
    private func capsuleRoom(_ shows: Bool) -> some View {
        Color.clear.frame(height: shows && !isKeyboardShown ? PhoneTabCapsule.footprint : 0)
    }

    /// Повторное касание открытого раздела возвращает к его началу, как у системных вкладок.
    private func select(_ newTab: PhoneTab) {
        if newTab == tab {
            paths[newTab] = []
        } else {
            tab = newTab
        }
    }

    /// «Чтение» на iPhone живёт на полке: отдельной вкладке внизу нет места.
    private var readingButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                push(.reading)
            } label: {
                Label("Чтение", systemImage: "chart.bar.xaxis")
            }
        }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isSettingsPresented = true
            } label: {
                Label("Настройки", systemImage: "gearshape")
            }
        }
    }

    private func stack<Root: View>(_ tab: PhoneTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path(for: tab)) {
            root()
                .themedToolbar()
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { capsuleRoom(true) }
                .navigationDestination(for: PhoneRoute.self) { route in
                    destination(route)
                        .themedToolbar()
                        .toolbar(.hidden, for: .tabBar)
                        .safeAreaInset(edge: .bottom, spacing: 0) { capsuleRoom(!route.hidesTabCapsule) }
                }
        }
    }

    private func path(for tab: PhoneTab) -> Binding<[PhoneRoute]> {
        Binding(
            get: { paths[tab] ?? [] },
            set: { paths[tab] = $0 }
        )
    }

    @ViewBuilder
    private func destination(_ route: PhoneRoute) -> some View {
        switch route {
        case .page(let id):
            PageScreen(
                database: database,
                pageId: id,
                onOpenPage: { push(.page($0)) },
                onClose: pop,
                onOpenSource: { push(.source($0, highlight: $1)) }
            )
        case .source(let id, let highlight):
            ReaderView(
                database: database,
                sourceId: id,
                highlightId: highlight,
                onOpenPage: { push(.page($0)) },
                onOpenSource: { push(.source($0, highlight: $1)) },
                onShowInfo: { push(.sourceInfo(id)) },
                onClose: pop
            )
        case .sourceInfo(let id):
            SourceDashboardView(
                database: database,
                sourceId: id,
                onRead: { push(.source(id, highlight: $0)) },
                onOpenPage: { push(.page($0)) }
            )
        case .folder(let id):
            library(folderId: id)
        case .inbox:
            InboxView(database: database, onOpen: { push(.page($0)) }, onNewNote: newQuickNote)
        case .trash:
            TrashView(database: database)
        case .reading:
            ReadingOverviewView(database: database, onOpenSource: { push(.sourceInfo($0)) })
        }
    }

    private func library(folderId: UUID?) -> some View {
        LibraryView(
            database: database,
            folderId: folderId,
            onOpenFolder: openFolder,
            onOpenPage: { push(.page($0)) },
            onOpenSource: { push(.source($0, highlight: nil)) },
            onShowSourceInfo: { push(.sourceInfo($0)) },
            onOpenTrash: { push(.trash) }
        )
    }


    // MARK: Переходы

    private func push(_ route: PhoneRoute) {
        paths[tab, default: []].append(route)
    }

    private func pop() {
        guard paths[tab]?.isEmpty == false else { return }
        paths[tab]?.removeLast()
    }

    /// Папка, которая уже есть в стеке (например, родитель из «хлебных крошек»), открывается
    /// возвратом к ней, а не новым экраном. Корень библиотеки это вкладка «Библиотека».
    private func openFolder(_ id: UUID?) {
        guard let id else {
            if tab == .library {
                paths[.library] = []
            } else {
                tab = .library
            }
            return
        }
        let path = paths[tab] ?? []
        if let index = path.lastIndex(of: .folder(id)) {
            paths[tab] = Array(path.prefix(through: index))
        } else {
            push(.folder(id))
        }
    }

    /// Открытое снаружи: книга встаёт поверх библиотеки, страница поверх текущей вкладки.
    /// Если та же книга уже открыта сверху, второй экран не нужен.
    private func openIncoming(_ item: SidebarItem) {
        let route: PhoneRoute
        switch item {
        case .page(let id): route = .page(id)
        case .source(let id, let highlight):
            tab = .library
            route = .source(id, highlight: highlight)
        case .sourceInfo(let id): route = .sourceInfo(id)
        case .library(let id):
            guard let id else {
                tab = .library
                return
            }
            route = .folder(id)
        case .home:
            tab = .home
            return
        case .inbox:
            tab = .inbox
            return
        case .tasks:
            tab = .tasks
            return
        case .trash: route = .trash
        case .reading:
            route = .reading
        }
        if case .source(let id, _) = route, case .source(id, _)? = paths[tab]?.last {
            paths[tab]?.removeLast()
        }
        push(route)
    }

    private func newQuickNote() {
        Task {
            do {
                let page = try await database.createPage(inInbox: true)
                LumenSounds.play(.create)
                push(.page(page.id))
            } catch {
                NoticeCenter.shared.report("Не удалось создать заметку", error)
            }
        }
    }
}

/// Низ экрана iPhone: одна стеклянная капсула во всю ширину. Четыре раздела, «Поиск» и «Создать»,
/// у каждой кнопки значок и подпись. Открытый раздел (и поиск) выпрыгивает кружком над капсулой,
/// под ним вырез, как в острове на Mac и iPad.
private struct PhoneTabCapsule: View {
    let database: AppDatabase
    let selection: PhoneTab
    var onSelect: (PhoneTab) -> Void
    var onSearch: () -> Void
    var onCreate: () -> Void

    @Environment(\.lumenTheme) private var theme
    /// Ширина капсулы: от неё ширина кнопок и место кружка. Меняется только при повороте.
    @State private var width: CGFloat = 0
    /// Неразобранные записки: число на «Записках», как в острове.
    @State private var inboxCount = 0

    static let height: CGFloat = 62
    /// Сколько места капсула занимает над краем экрана вместе с кружком.
    static let footprint: CGFloat = height + BubbleMetrics.lift + 10
    private static let padding: CGFloat = 6

    private static let tabs: [PhoneTab] = [.home, .inbox, .tasks, .library, .search]
    /// Кнопок шесть: пять вкладок и «Создать».
    private static let slots: CGFloat = 6

    /// Названия и значки те же, что у разделов острова на Mac и iPad.
    private static func room(_ tab: PhoneTab) -> StudyRoom {
        switch tab {
        case .home, .search: .desk
        case .inbox: .notes
        case .tasks: .tasks
        case .library: .shelf
        }
    }

    private static func title(_ tab: PhoneTab) -> String {
        tab == .search ? "Поиск" : room(tab).title
    }

    private static func systemImage(_ tab: PhoneTab) -> String {
        tab == .search ? "magnifyingglass" : room(tab).systemImage
    }

    private var bubbleX: CGFloat? {
        guard width > 0, let index = Self.tabs.firstIndex(of: selection) else { return nil }
        let slot = (width - Self.padding * 2) / Self.slots
        return Self.padding + (CGFloat(index) + 0.5) * slot
    }

    var body: some View {
        BubbleBar(
            height: Self.height,
            bubbleX: bubbleX,
            bubbleImage: Self.systemImage(selection),
            bubbleCount: selection == .inbox ? inboxCount : 0
        ) {
            HStack(spacing: 0) {
                ForEach(Self.tabs, id: \.self) { tab in
                    tabButton(tab)
                }
                Button(action: onCreate) {
                    BubbleBarLabel(
                        title: "Создать",
                        systemImage: "plus",
                        tint: theme.accent,
                        width: nil,
                        height: Self.height,
                        iconSize: 20,
                        fontSize: 10.5
                    )
                }
                .accessibilityLabel("Создать")
            }
            .padding(.horizontal, Self.padding)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task { await observeInbox() }
        .animation(LumenMotion.standard, value: selection)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, BubbleMetrics.lift + 4)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: PhoneTab) -> some View {
        let isOn = selection == tab
        let count = tab == .inbox ? inboxCount : 0
        return Button {
            if tab == .search { onSearch() } else { onSelect(tab) }
        } label: {
            BubbleBarLabel(
                title: Self.title(tab),
                systemImage: Self.systemImage(tab),
                isOn: isOn,
                count: count,
                width: nil,
                height: Self.height,
                iconSize: 20,
                fontSize: 10.5
            )
        }
        .accessibilityLabel(count > 0 ? "\(Self.title(tab)), \(count)" : Self.title(tab))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func observeInbox() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetchCounts(db).inboxCount }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) where value != inboxCount {
                withAnimation(LumenMotion.standard) { inboxCount = value }
            }
        } catch {
            lumenLog.error("Phone capsule observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

#endif
