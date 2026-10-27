import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

struct SidebarView: View {
    let database: AppDatabase
    @Binding var selection: SidebarItem?
    var onNewPage: (UUID?) -> Void

    @State private var snapshot = SidebarSnapshot.empty

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

            Section("Страницы") {
                OutlineGroup(snapshot.tree, children: \.childrenOrNil) { node in
                    PageLabel(page: node.page)
                        .tag(SidebarItem.page(node.id))
                        .contextMenu { menu(for: node.page) }
                }
                Button {
                    onNewPage(nil)
                } label: {
                    Label("Новая страница", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Section {
                Label("Корзина", systemImage: "trash")
                    .badge(snapshot.trashCount)
                    .tag(SidebarItem.trash)
            }
        }
        .navigationTitle("Lumen")
        .task { await observe() }
    }

    @ViewBuilder
    private func menu(for page: Page) -> some View {
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
