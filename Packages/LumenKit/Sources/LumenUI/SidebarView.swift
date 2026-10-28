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

    @State private var snapshot = SidebarSnapshot.empty
    @State private var renaming: Page?
    @State private var newTitle = ""

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Главная", systemImage: "sparkles")
                    .tag(SidebarItem.home)
                Label("Входящие", systemImage: "tray")
                    .badge(snapshot.inboxCount)
                    .tag(SidebarItem.inbox)
            }

            if !snapshot.favorites.isEmpty {
                Section("Избранное") {
                    ForEach(snapshot.favorites) { page in
                        PageLabel(page: page)
                            .tag(SidebarItem.page(page.id))
                            .contextMenu { menu(for: page) }
                    }
                }
            }

            Section {
                OutlineGroup(snapshot.tree, children: \.childrenOrNil) { node in
                    PageLabel(page: node.page)
                        .tag(SidebarItem.page(node.id))
                        .contextMenu { menu(for: node.page) }
                        // Перетащите страницу на другую, чтобы сделать её подстраницей.
                        .draggable(PageDragItem(pageId: node.id)) {
                            PageLabel(page: node.page).padding(6)
                        }
                        .dropDestination(for: PageDragItem.self) { items, _ in
                            move(items, to: node.id)
                        }
                }
                Button {
                    onNewPage(nil)
                } label: {
                    Label("Новая страница", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } header: {
                // Бросьте страницу на заголовок раздела, чтобы поднять её на верхний уровень.
                Text("Страницы")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .dropDestination(for: PageDragItem.self) { items, _ in
                        move(items, to: nil)
                    }
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
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func move(_ items: [PageDragItem], to parentId: UUID?) -> Bool {
        let ids = items.map(\.pageId).filter { $0 != parentId }
        guard !ids.isEmpty else { return false }
        Task {
            for id in ids {
                // Нельзя положить страницу внутрь её же подстраницы: такие перемещения просто пропускаем.
                try? await database.movePage(id, toParent: parentId)
            }
        }
        return true
    }

    @ViewBuilder
    private func menu(for page: Page) -> some View {
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
