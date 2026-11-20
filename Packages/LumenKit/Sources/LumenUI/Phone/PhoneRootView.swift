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
        Color.clear.frame(height: shows && !isKeyboardShown ? PhoneTabCapsule.height + 10 : 0)
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

/// Низ экрана iPhone: слева стеклянная капсула с разделами, справа круглый поиск и «+».
private struct PhoneTabCapsule: View {
    let selection: PhoneTab
    var onSelect: (PhoneTab) -> Void
    var onSearch: () -> Void
    var onCreate: () -> Void

    @Environment(\.lumenTheme) private var theme
    @Namespace private var markSpace

    static let height: CGFloat = 60

    private static let tabs: [PhoneTab] = [.home, .inbox, .tasks, .library]

    /// Названия и значки те же, что у разделов острова на Mac и iPad.
    private static func room(_ tab: PhoneTab) -> StudyRoom {
        switch tab {
        case .home, .search: .desk
        case .inbox: .notes
        case .tasks: .tasks
        case .library: .shelf
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Self.tabs, id: \.self) { tab in
                    roomButton(Self.room(tab), tab: tab)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 60)
            .lumenGlass(Capsule())
            .animation(LumenMotion.standard, value: selection)
            Spacer(minLength: 0)
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selection == .search ? theme.textPrimary : theme.textSecondary)
                    .frame(width: 60, height: 60)
                    .lumenGlass(Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Поиск")
            .accessibilityAddTraits(selection == .search ? .isSelected : [])
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 60, height: 60)
                    .background(theme.accent, in: Circle())
                    .shadow(color: .black.opacity(theme.shadowOpacity * 1.6), radius: 14, y: 8)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Создать")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func roomButton(_ room: StudyRoom, tab: PhoneTab) -> some View {
        let isOn = selection == tab
        return Button {
            onSelect(tab)
        } label: {
            Image(systemName: room.systemImage)
                .font(.system(size: 20, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? theme.textPrimary : theme.textSecondary)
                .frame(width: 52, height: 48)
                .background {
                    if isOn {
                        Capsule()
                            .fill(theme.surface2)
                            .matchedGeometryEffect(id: "mark", in: markSpace)
                    }
                }
                .contentShape(Capsule())
        }
        .accessibilityLabel(room.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#endif
