import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let database: AppDatabase
    @Binding var selection: SidebarItem?
    var onNewPage: (UUID?) -> Void
    var onNewFolder: (UUID?) -> Void

    @State private var snapshot = SidebarSnapshot.empty
    @State private var renaming: Page?
    @State private var renamingFolder: Folder?
    @State private var newTitle = ""
    @Environment(\.workspaceActions) private var workspaceActions

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Главная", systemImage: "sparkles")
                    .tag(SidebarItem.home)
                Label("Входящие", systemImage: "tray")
                    .badge(snapshot.inboxCount)
                    .tag(SidebarItem.inbox)
                Label("Библиотека", systemImage: "books.vertical")
                    .tag(SidebarItem.library(nil))
                    .dropDestination(for: PageDragItem.self) { items, _ in
                        move(items, toFolder: nil)
                    }
            }

            if !snapshot.favorites.isEmpty {
                Section("Избранное") {
                    ForEach(snapshot.favorites) { page in
                        PageLabel(page: page)
                            .tag(SidebarItem.page(page.id))
                            .contextMenu { menu(for: page) }
                            .draggable(PageDragItem(pageId: page.id)) {
                                PageLabel(page: page).padding(6)
                            }
                    }
                }
            }

            Section {
                OutlineGroup(snapshot.folders, children: \.childrenOrNil) { node in
                    FolderLabel(folder: node.folder)
                        .tag(SidebarItem.library(node.id))
                        .contextMenu { folderMenu(for: node.folder) }
                        // Перетащите страницу из избранного на папку, чтобы положить её туда.
                        .dropDestination(for: PageDragItem.self) { items, _ in
                            move(items, toFolder: node.id)
                        }
                }
                Button {
                    onNewFolder(nil)
                } label: {
                    Label("Новая папка", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } header: {
                Text("Папки")
            }

            Section {
                Label("Корзина", systemImage: "trash")
                    .badge(snapshot.trashCount)
                    .tag(SidebarItem.trash)
            }
        }
        .navigationTitle("Lumen")
        .task { await observe() }
        .alert("Переименовать страницу", isPresented: isRenaming) {
            TextField("Название", text: $newTitle)
            Button("Готово") {
                if let page = renaming {
                    let title = newTitle
                    Task { try? await database.renamePage(page.id, title: title) }
                }
                renaming = nil
            }
            Button("Отмена", role: .cancel) { renaming = nil }
        }
        .alert("Переименовать папку", isPresented: isRenamingFolder) {
            TextField("Название", text: $newTitle)
            Button("Готово") {
                if let folder = renamingFolder {
                    let name = newTitle
                    Task { try? await database.renameFolder(folder.id, name: name) }
                }
                renamingFolder = nil
            }
            Button("Отмена", role: .cancel) { renamingFolder = nil }
        }
    }

    private var isRenamingFolder: Binding<Bool> {
        Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func move(_ items: [PageDragItem], toFolder folderId: UUID?) -> Bool {
        let ids = items.map(\.pageId)
        guard !ids.isEmpty else { return false }
        LumenSounds.play(.dropIntoFolder)
        Task {
            for id in ids {
                try? await database.movePage(id, toFolder: folderId)
            }
        }
        return true
    }

    /// «В новой вкладке» и «Рядом», как ссылка в браузере.
    @ViewBuilder
    private func openElsewhereButtons(_ item: SidebarItem) -> some View {
        if let workspaceActions {
            Button {
                workspaceActions.openInNewTab(item)
            } label: {
                Label("Открыть в новой вкладке", systemImage: "plus.square.on.square")
            }
            Button {
                workspaceActions.openBeside(item)
            } label: {
                Label("Открыть рядом", systemImage: "rectangle.split.2x1")
            }
            Divider()
        }
    }

    @ViewBuilder
    private func folderMenu(for folder: Folder) -> some View {
        openElsewhereButtons(.library(folder.id))
        Button {
            newTitle = folder.name
            renamingFolder = folder
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Button {
            onNewFolder(folder.id)
        } label: {
            Label("Новая папка внутри", systemImage: "folder.badge.plus")
        }
        Picker(selection: Binding(
            get: { folder.color },
            set: { color in Task { try? await database.setFolderColor(folder.id, color: color) } }
        )) {
            ForEach(FolderPalette.names.indices, id: \.self) { index in
                Text(FolderPalette.names[index]).tag(index)
            }
        } label: {
            Label("Цвет", systemImage: "paintpalette")
        }
        if folder.parentId != nil {
            Button {
                Task { try? await database.moveFolder(folder.id, toParent: nil) }
            } label: {
                Label("В корень библиотеки", systemImage: "arrow.up.to.line")
            }
        }
        Divider()
        Button(role: .destructive) {
            if selection == .library(folder.id) { selection = .library(nil) }
            LumenSounds.play(.trash)
            Task { try? await database.trashFolder(folder.id) }
        } label: {
            Label("В корзину", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func menu(for page: Page) -> some View {
        openElsewhereButtons(.page(page.id))
        Button {
            newTitle = page.title
            renaming = page
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Button {
            onNewPage(page.id)
        } label: {
            Label("Новая подстраница", systemImage: "doc.badge.plus")
        }
        Button {
            Task { try? await database.setFavorite(page.id, !page.isFavorite) }
        } label: {
            if page.isFavorite {
                Label("Убрать из избранного", systemImage: "star.slash")
            } else {
                Label("В избранное", systemImage: "star")
            }
        }
        if page.parentId != nil {
            Button {
                Task { try? await database.movePage(page.id, toParent: nil) }
            } label: {
                Label("На верхний уровень", systemImage: "arrow.up.to.line")
            }
        }
        Divider()
        Button(role: .destructive) {
            if selection == .page(page.id) { selection = .home }
            LumenSounds.play(.trash)
            Task { try? await database.trashPage(page.id) }
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                snapshot = value
            }
        } catch {
            print("Sidebar observation failed: \(error)")
        }
    }
}

/// Значок и название папки.
struct FolderLabel: View {
    let folder: Folder

    var body: some View {
        Label {
            Text(folder.displayName)
                .lineLimit(1)
        } icon: {
            FolderGlyph(color: folder.color)
        }
    }
}

/// Что переносится при перетаскивании страницы в сайдбаре.
struct PageDragItem: Codable, Transferable {
    let pageId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .lumenPage)
    }
}

extension UTType {
    static let lumenPage = UTType(exportedAs: "app.lumen.page")
}

/// Иконка и название страницы.
struct PageLabel: View {
    let page: Page

    var body: some View {
        Label {
            Text(page.displayTitle)
                .lineLimit(1)
        } icon: {
            if let icon = page.icon, !icon.isEmpty {
                Text(icon)
            } else {
                Image(systemName: "doc.text")
            }
        }
    }
}
