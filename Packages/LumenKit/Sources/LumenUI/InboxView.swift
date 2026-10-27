import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// «Входящие»: быстрые заметки, которые ещё не разложены по разделам.
struct InboxView: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void
    var onNewNote: () -> Void

    @State private var notes: [PagePreview] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(notes) { note in
                    Button {
                        onOpen(note.page.id)
                    } label: {
                        PagePreviewCard(preview: note)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            Task { try? await database.movePage(note.page.id, toParent: nil) }
                        } label: {
                            Label("Перенести в страницы", systemImage: "folder")
                        }
                        Button(role: .destructive) {
                            Task { try? await database.trashPage(note.page.id) }
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView {
                    Label("Во входящих пусто", systemImage: "tray")
                } description: {
                    Text("Сюда попадают быстрые заметки. Нажмите ⌘N или кнопку ниже.")
                } actions: {
                    Button("Новая заметка", action: onNewNote)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(ThemedBackground())
        .navigationTitle("Входящие")
        .task { await observe() }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try InboxQuery.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation { notes = value }
            }
        } catch {
            print("Inbox observation failed: \(error)")
        }
    }
}

/// Корзина: восстановить страницу или удалить всё навсегда.
struct TrashView: View {
    let database: AppDatabase

    @State private var pages: [Page] = []
    @State private var isConfirmingEmpty = false

    var body: some View {
        List {
            ForEach(pages) { page in
                HStack {
                    PageLabel(page: page)
                    Spacer()
                    Button("Восстановить") {
                        Task { try? await database.restorePage(page.id) }
                    }
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if pages.isEmpty {
                ContentUnavailableView("Корзина пуста", systemImage: "trash")
            }
        }
        .background(ThemedBackground())
        .navigationTitle("Корзина")
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Очистить", role: .destructive) { isConfirmingEmpty = true }
                    .disabled(pages.isEmpty)
            }
        }
        .confirmationDialog("Удалить все страницы из корзины навсегда?", isPresented: $isConfirmingEmpty) {
            Button("Удалить навсегда", role: .destructive) {
                Task { try? await database.emptyTrash() }
            }
        }
        .task { await observe() }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try TrashQuery.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                pages = value
            }
        } catch {
            print("Trash observation failed: \(error)")
        }
    }
}
