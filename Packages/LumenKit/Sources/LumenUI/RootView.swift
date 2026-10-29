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
}

/// Корневой экран: сайдбар с разделами и деревом страниц, справа выбранный раздел.
/// На iPhone `NavigationSplitView` сам превращается в стек.
public struct RootView: View {
    private let database: AppDatabase
    @State private var selection: SidebarItem? = .home
    @State private var isSearchPresented = false
    @Environment(\.lumenTheme) private var theme

    public init(database: AppDatabase) {
        self.database = database
    }

    public var body: some View {
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
        .tint(theme.accent)
        .preferredColorScheme(.dark)
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
                onOpenPage: { selection = .page($0) }
            )
            .id(folderId)
        case .trash:
            TrashView(database: database)
        case .page(let id):
            PageEditorView(
                database: database,
                pageId: id,
                onOpenPage: { selection = .page($0) },
                onClose: { selection = .home }
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
