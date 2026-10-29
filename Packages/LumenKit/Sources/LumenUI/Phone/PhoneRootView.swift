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
    case folder(UUID)
    case inbox
    case trash
}

enum PhoneTab: Hashable {
    case home
    case inbox
    case library
    case more
    case search
}

/// iPhone: вместо сайдбара вкладки внизу экрана, у каждой свой стек экранов.
/// Сами экраны те же, что на Mac и iPad, они подстраиваются под узкую ширину.
struct PhoneRootView: View {
    let database: AppDatabase

    @State private var tab: PhoneTab = .home
    @State private var paths: [PhoneTab: [PhoneRoute]] = [:]

    var body: some View {
        TabView(selection: $tab) {
            Tab("Главная", systemImage: "sparkles", value: PhoneTab.home) {
                stack(.home) {
                    HomeView(
                        database: database,
                        onOpen: { push(.page($0)) },
                        onNewNote: newQuickNote,
                        onShowInbox: { tab = .inbox }
                    )
                    .toolbar { newNoteButton }
                }
            }
            Tab("Входящие", systemImage: "tray", value: PhoneTab.inbox) {
                stack(.inbox) {
                    InboxView(database: database, onOpen: { push(.page($0)) }, onNewNote: newQuickNote)
                        .toolbar { newNoteButton }
                }
            }
            Tab("Библиотека", systemImage: "books.vertical", value: PhoneTab.library) {
                stack(.library) {
                    library(folderId: nil)
                }
            }
            Tab("Ещё", systemImage: "square.grid.2x2", value: PhoneTab.more) {
                stack(.more) {
                    PhoneMoreView(database: database)
                }
            }
            Tab(value: PhoneTab.search, role: .search) {
                stack(.search) {
                    SearchView(database: database, isEmbedded: true) { push(.page($0)) }
                }
            }
        }
    }

    private func stack<Root: View>(_ tab: PhoneTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path(for: tab)) {
            root()
                .navigationDestination(for: PhoneRoute.self) { route in
                    destination(route)
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
            PageEditorView(
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
                onClose: pop
            )
            // Книга во весь экран: панель вкладок ей только мешает.
            .toolbar(.hidden, for: .tabBar)
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
            onOpenSource: { push(.source($0, highlight: nil)) }
        )
    }

    private var newNoteButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: newQuickNote) {
                Label("Быстрая заметка", systemImage: "square.and.pencil")
            }
        }
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

    private func newQuickNote() {
        Task {
            if let page = try? await database.createPage(inInbox: true) {
                LumenSounds.play(.create)
                push(.page(page.id))
            }
        }
    }
}

/// Вкладка «Ещё»: избранное, дерево папок, корзина и синхронизация. На Mac это сайдбар.
struct PhoneMoreView: View {
    let database: AppDatabase

    @State private var snapshot = SidebarSnapshot.empty

    var body: some View {
        List {
            if !snapshot.favorites.isEmpty {
                Section("Избранное") {
                    ForEach(snapshot.favorites) { page in
                        NavigationLink(value: PhoneRoute.page(page.id)) {
                            PageLabel(page: page)
                        }
                    }
                }
            }

            Section("Папки") {
                if snapshot.folders.isEmpty {
                    Text("Папки появятся здесь, когда вы создадите их в библиотеке.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                OutlineGroup(snapshot.folders, children: \.childrenOrNil) { node in
                    NavigationLink(value: PhoneRoute.folder(node.id)) {
                        FolderLabel(folder: node.folder)
                    }
                }
            }

            Section {
                NavigationLink(value: PhoneRoute.trash) {
                    Label("Корзина", systemImage: "trash")
                        .badge(snapshot.trashCount)
                }
            }

            Section {
                SyncStatusRow()
            } header: {
                Text("iCloud")
            }
        }
        .scrollContentBackground(.hidden)
        .background(ThemedBackground())
        .navigationTitle("Ещё")
        .task { await observe() }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                snapshot = value
            }
        } catch {
            print("More observation failed: \(error)")
        }
    }
}
#endif
