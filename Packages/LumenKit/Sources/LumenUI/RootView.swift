import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Пункт сайдбара и одновременно то, что показано в основной области.
public enum SidebarItem: Hashable, Sendable {
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
/// На iPhone (узкий экран) вместо сайдбара вкладки внизу, см. `PhoneRootView`.
public struct RootView: View {
    private let database: AppDatabase
    @State private var selection: SidebarItem? = .home
    @State private var isSearchPresented = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme

    public init(database: AppDatabase) {
        self.database = database
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
                selection: $selection,
                onNewPage: openNewPage,
                onNewFolder: openNewFolder,
                onNewDataTable: openNewDataTable
            )
        } detail: {
            detail
                .toolbar {
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
                    }
                }
        }
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
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .home:
            HomeView(
                database: database,
                onOpen: { selection = .page($0) },
                onOpenSource: { selection = .source($0, highlight: nil) },
                onNewNote: newQuickNote,
                onShowInbox: { selection = .inbox },
                onShowLibrary: { selection = .library(nil) }
            )
        case .inbox:
            InboxView(database: database, onOpen: { selection = .page($0) }, onNewNote: newQuickNote)
        case .tasks:
            TasksScreen(database: database, onOpenPage: { selection = .page($0) })
        case .library(let folderId):
            LibraryView(
                database: database,
                folderId: folderId,
                onOpenFolder: { selection = .library($0) },
                onOpenPage: { selection = .page($0) },
                onOpenSource: { selection = .source($0, highlight: nil) },
                onShowSourceInfo: { selection = .sourceInfo($0) }
            )
            .id(folderId)
        case .trash:
            TrashView(database: database)
        case .page(let id):
            PageScreen(
                database: database,
                pageId: id,
                onOpenPage: { selection = .page($0) },
                onClose: { selection = .home },
                onOpenSource: { selection = .source($0, highlight: $1) }
            )
            .id(id)
        case .source(let id, let highlight):
            ReaderView(
                database: database,
                sourceId: id,
                highlightId: highlight,
                onOpenPage: { selection = .page($0) },
                onOpenSource: { selection = .source($0, highlight: $1) },
                onShowInfo: { selection = .sourceInfo(id) },
                onClose: { selection = .library(nil) }
            )
            .id(id)
        case .sourceInfo(let id):
            SourceDashboardView(
                database: database,
                sourceId: id,
                onRead: { selection = .source(id, highlight: $0) },
                onOpenPage: { selection = .page($0) }
            )
            .id(id)
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
