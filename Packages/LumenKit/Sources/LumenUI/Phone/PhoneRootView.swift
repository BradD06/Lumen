import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

#if os(iOS)

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
}

extension PhoneRoute {
    /// Книга открыта во весь экран, без нижних панелей.
    var isReader: Bool {
        if case .source = self { true } else { false }
    }
}

enum PhoneTab: Hashable {
    case home
    case inbox
    case tasks
    case library
    case search
}

/// iPhone: вместо табло с комнатами вкладки внизу экрана, у каждой свой стек экранов.
/// Сами экраны те же, что на Mac и iPad, они подстраиваются под узкую ширину.
/// Избранное на телефоне в начале списка на полке, корзина и iCloud в её меню.
struct PhoneRootView: View {
    let database: AppDatabase

    @State private var tab: PhoneTab = .home
    @State private var paths: [PhoneTab: [PhoneRoute]] = [:]
    @State private var isCreating = false
    @State private var isImportingBook = false
    @State private var isSettingsPresented = false

    var body: some View {
        // Вкладки называются как комнаты «Кабинета».
        TabView(selection: $tab) {
            Tab("Стол", systemImage: "lamp.desk", value: PhoneTab.home) {
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
                    .overlay(alignment: .bottomTrailing) { createButton }
                }
            }
            Tab("Записки", systemImage: "envelope", value: PhoneTab.inbox) {
                stack(.inbox) {
                    InboxView(database: database, onOpen: { push(.page($0)) }, onNewNote: newQuickNote)
                        .overlay(alignment: .bottomTrailing) { createButton }
                }
            }
            Tab("Дела", systemImage: "checklist", value: PhoneTab.tasks) {
                stack(.tasks) {
                    TasksScreen(database: database, onOpenPage: { push(.page($0)) })
                }
            }
            Tab("Полка", systemImage: "books.vertical", value: PhoneTab.library) {
                stack(.library) {
                    library(folderId: nil)
                }
            }
            Tab(value: PhoneTab.search, role: .search) {
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

    /// Круглая «+» над вкладками: создать что угодно одним касанием.
    private var createButton: some View {
        PhoneCreateButton { isCreating = true }
            .padding(.trailing, 20)
            .padding(.bottom, 16)
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
                .navigationDestination(for: PhoneRoute.self) { route in
                    destination(route)
                        .themedToolbar()
                        // Книга во весь экран: панель вкладок ей только мешает.
                        .toolbar(route.isReader ? .hidden : .automatic, for: .tabBar)
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

/// Круглая кнопка «Создать» в углу экрана.
private struct PhoneCreateButton: View {
    var action: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.vividCard(0).foreground)
                .frame(width: 60, height: 60)
                .background(LinearGradient(colors: theme.vividCard(0).colors, startPoint: .top, endPoint: .bottom), in: Circle())
                .shadow(color: (theme.vividCard(0).colors.last ?? .orange).opacity(0.45), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Создать")
    }
}

#endif
