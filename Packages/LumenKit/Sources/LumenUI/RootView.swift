import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Пункт сайдбара и одновременно то, что показано в основной области.
public enum SidebarItem: Hashable, Sendable {
    case home
    case inbox
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
            } else {
                splitView
            }
            #else
            splitView
            #endif
        }
        .tint(theme.accent)
        .preferredColorScheme(.dark)
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(database: database, selection: $selection, onNewPage: openNewPage, onNewFolder: openNewFolder)
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
            SearchView(database: database) { pageId in
                isSearchPresented = false
                selection = .page(pageId)
            }
        }
        // Книги из «Файлов» и Finder, ссылки lumen:// на страницы, книги и цитаты.
        .opensIncomingLinks(database: database) { selection = $0 }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .home:
            HomeView(
                database: database,
                onOpen: { selection = .page($0) },
                onNewNote: newQuickNote,
                onShowInbox: { selection = .inbox }
            )
        case .inbox:
            InboxView(database: database, onOpen: { selection = .page($0) }, onNewNote: newQuickNote)
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
            PageEditorView(
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
            if let page = try? await database.createPage(inInbox: true) {
                LumenSounds.play(.create)
                selection = .page(page.id)
            }
        }
    }

    private func openNewFolder(parentId: UUID?) {
        Task {
            if let folder = try? await database.createFolder(name: "Новая папка", parentId: parentId) {
                LumenSounds.play(.create)
                selection = .library(folder.id)
            }
        }
    }

    private func openNewPage(parentId: UUID?) {
        Task {
            if let page = try? await database.createPage(parentId: parentId) {
                LumenSounds.play(.create)
                selection = .page(page.id)
            }
        }
    }
}

#Preview {
    RootView(database: .preview())
}
