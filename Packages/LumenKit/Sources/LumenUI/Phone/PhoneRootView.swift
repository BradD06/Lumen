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

/// iPhone: вместо сайдбара вкладки внизу экрана, у каждой свой стек экранов.
/// Сами экраны те же, что на Mac и iPad, они подстраиваются под узкую ширину.
/// Что на Mac лежит в сайдбаре, на телефоне в библиотеке: избранное в начале списка,
/// корзина и iCloud в её меню.
struct PhoneRootView: View {
    let database: AppDatabase

    @State private var tab: PhoneTab = .home
    @State private var paths: [PhoneTab: [PhoneRoute]] = [:]
    @State private var isCreating = false
    @State private var isImportingBook = false
    @State private var isSettingsPresented = false
    /// Минута дыхания «Дзена» поверх всего.
    @State private var isBreathing = false
    /// Команды и поиск «Монохрома» и «Дзена» (на Mac это ⌘K).
    @State private var isPaletteOpen = false
    /// Пока набирают текст, точка «Дзена» и строка «Монохрома» прячутся.
    @State private var isKeyboardShown = false
    @Environment(\.lumenTheme) private var theme

    /// «Кабинет»: вкладки называются как комнаты.
    private var isStudy: Bool { theme.layout == .rooms }

    /// «Дзен» и «Монохром»: панели вкладок нет, вся навигация в одном месте внизу экрана,
    /// как на Mac: дышащая точка или командная строка.
    private var isMinimal: Bool { theme.layout == .orb || theme.layout == .commandLine }

    var body: some View {
        TabView(selection: $tab) {
            Tab(isStudy ? "Стол" : "Сегодня", systemImage: isStudy ? "lamp.desk" : "sun.max", value: PhoneTab.home) {
                stack(.home) {
                    HomeView(
                        database: database,
                        onOpen: { push(.page($0)) },
                        onOpenSource: { push(.source($0, highlight: nil)) },
                        onNewNote: newQuickNote,
                        onShowInbox: { tab = .inbox },
                        onShowLibrary: { tab = .library }
                    )
                    .toolbar {
                        if !isMinimal { settingsButton }
                    }
                    .overlay(alignment: .bottomTrailing) { createButton }
                }
            }
            Tab(isStudy ? "Записки" : "Входящие", systemImage: isStudy ? "envelope" : "tray", value: PhoneTab.inbox) {
                stack(.inbox) {
                    InboxView(database: database, onOpen: { push(.page($0)) }, onNewNote: newQuickNote)
                        .overlay(alignment: .bottomTrailing) { createButton }
                }
            }
            Tab(isStudy ? "Дела" : "Задачи", systemImage: "checklist", value: PhoneTab.tasks) {
                stack(.tasks) {
                    TasksScreen(database: database, onOpenPage: { push(.page($0)) })
                }
            }
            Tab(isStudy ? "Полка" : "Библиотека", systemImage: "books.vertical", value: PhoneTab.library) {
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardShown = false
        }
        .sheet(isPresented: $isPaletteOpen) {
            CommandPalette(
                database: database,
                commands: PaletteCommand.standard(actions: appActions, extra: paletteExtras),
                onOpen: { item, _ in
                    isPaletteOpen = false
                    openIncoming(item)
                },
                onDismiss: { isPaletteOpen = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if isBreathing {
                BreathingView {
                    withAnimation(.easeInOut(duration: 0.6)) { isBreathing = false }
                }
                .transition(.opacity)
            }
        }
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
            search: {
                if isMinimal {
                    isPaletteOpen = true
                } else {
                    tab = .search
                }
            },
            settings: { isSettingsPresented = true },
            breathe: startBreathing
        )
    }

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 0.6)) { isBreathing = true }
    }

    /// Круглая «+» над вкладками: создать что угодно одним касанием.
    /// В «Дзене» и «Монохроме» её нет: создают из точки или из командной строки.
    @ViewBuilder
    private var createButton: some View {
        if !isMinimal {
            PhoneCreateButton { isCreating = true }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
        }
    }

    /// Нижняя полоса вместо вкладок: точка «Дзена» или командная строка «Монохрома».
    @ViewBuilder
    private var minimalBar: some View {
        if !isKeyboardShown {
            switch theme.layout {
            case .orb:
                // Место внизу под точку постоянное: раскрытое меню всплывает над текстом,
                // а не сдвигает его.
                Color.clear
                    .frame(height: 54)
                    .overlay(alignment: .bottom) {
                        ZenOrb(
                            selection: currentItem,
                            onSelect: goTo,
                            onCreate: newQuickNote,
                            onSearch: { isPaletteOpen = true },
                            onBreathe: startBreathing,
                            onSettings: { isSettingsPresented = true }
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                    }
            case .commandLine:
                PhoneCommandBar(
                    location: "lumen / \(SidebarItem.commandLinePlace(currentItem))",
                    onOpen: { isPaletteOpen = true },
                    onNewNote: newQuickNote
                )
            case .standard, .sectionBar, .rooms:
                EmptyView()
            }
        }
    }

    /// Экран с нижней полосой: в «Дзене» и «Монохроме» вместо вкладок точка или строка.
    /// Книга открывается во весь экран без них.
    private func withMinimalBar<Content: View>(_ content: Content, isReader: Bool = false) -> some View {
        content
            .toolbar(isMinimal || isReader ? .hidden : .automatic, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isMinimal, !isReader {
                    minimalBar
                }
            }
    }

    /// Действия, которые на телефоне есть только в командах.
    private var paletteExtras: [PaletteCommand] {
        var list: [PaletteCommand] = [.breathe(startBreathing)]
        if paths[tab]?.isEmpty == false {
            list.append(PaletteCommand(id: "back", title: "Назад", systemImage: "chevron.left", keywords: ["вернуться"], run: pop))
        }
        list.append(PaletteCommand(id: "triage", title: "Разобрать входящие", systemImage: "rectangle.stack", keywords: ["входящие", "по одной"], run: { goTo(.inbox) }))
        list += PaletteCommand.themes(current: theme.id)
        return list
    }

    /// Где сейчас: верх стека текущей вкладки или сама вкладка.
    private var currentItem: SidebarItem? {
        if let route = paths[tab]?.last {
            switch route {
            case .page(let id): return .page(id)
            case .source(let id, let highlight): return .source(id, highlight: highlight)
            case .sourceInfo(let id): return .sourceInfo(id)
            case .folder(let id): return .library(id)
            case .inbox: return .inbox
            case .trash: return .trash
            }
        }
        switch tab {
        case .home: return .home
        case .inbox: return .inbox
        case .tasks: return .tasks
        case .library: return .library(nil)
        case .search: return nil
        }
    }

    /// Переход из точки «Дзена»: на главный экран раздела. Если уже в нём, к его началу.
    private func goTo(_ item: SidebarItem) {
        let target: PhoneTab
        switch item {
        case .home: target = .home
        case .inbox: target = .inbox
        case .tasks: target = .tasks
        case .library(nil): target = .library
        default:
            openIncoming(item)
            return
        }
        if tab == target {
            paths[target] = []
        } else {
            tab = target
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
            withMinimalBar(root().themedToolbar())
                .navigationDestination(for: PhoneRoute.self) { route in
                    withMinimalBar(destination(route).themedToolbar(), isReader: route.isReader)
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
            // Книга во весь экран: панель вкладок ей только мешает.
            .toolbar(.hidden, for: .tabBar)
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
