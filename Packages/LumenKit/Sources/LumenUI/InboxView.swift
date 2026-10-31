import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// «Входящие»: быстрые заметки, которые ещё не разложены по разделам.
/// Свайп влево удаляет заметку, вправо раскладывает по папке. То же есть в меню по правой кнопке.
struct InboxView: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void
    var onNewNote: () -> Void

    @State private var notes: [PagePreview] = []
    /// Заметка, для которой открыто окно «Разложить по папке».
    @State private var filing: PagePreview?

    var body: some View {
        List {
            ForEach(notes) { note in
                Button {
                    onOpen(note.page.id)
                } label: {
                    PagePreviewCard(preview: note)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .contextMenu { menu(for: note) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        trash(note)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        filing = note
                    } label: {
                        Label("В папку", systemImage: "folder")
                    }
                    .tint(.indigo)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView {
                    Label("Во входящих пусто", systemImage: "tray")
                } description: {
                    Text(Self.emptyHint)
                } actions: {
                    Button("Новая заметка", action: onNewNote)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(ThemedBackground())
        .navigationTitle("Входящие")
        .sheet(item: $filing) { note in
            MoveToFolderSheet(database: database, item: .page(note.page.id), currentFolderId: nil, isFromInbox: true) {
                filing = nil
            }
        }
        .task { await observe() }
    }

    #if os(macOS)
    private static let emptyHint = "Сюда попадают быстрые заметки. Нажмите ⌘N или кнопку ниже."
    #else
    private static let emptyHint = "Сюда попадают быстрые заметки. Нажмите кнопку ниже, чтобы записать мысль."
    #endif

    @ViewBuilder
    private func menu(for note: PagePreview) -> some View {
        Button {
            filing = note
        } label: {
            Label("Разложить по папке…", systemImage: "folder")
        }
        Button {
            Task {
                await NoticeCenter.shared.attempt("Не удалось перенести заметку") {
                    try await database.movePage(note.page.id, toFolder: nil)
                }
            }
        } label: {
            Label("В библиотеку", systemImage: "books.vertical")
        }
        Divider()
        Button(role: .destructive) {
            trash(note)
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }

    private func trash(_ note: PagePreview) {
        NoticeCenter.shared.moveToTrash(.page(note.page.id), in: database)
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try InboxQuery.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation { notes = value }
            }
        } catch {
            lumenLog.error("Inbox observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Корзина: восстановить папку, страницу или книгу, удалить одну вещь или всё навсегда.
/// Что лежит здесь дольше 30 дней, удаляется само.
struct TrashView: View {
    let database: AppDatabase

    @State private var trash = TrashSnapshot.empty
    @State private var isConfirmingEmpty = false
    @Environment(\.isActivePane) private var isActivePane
    /// Вещь, которую собираются удалить навсегда: сначала спрашиваем.
    @State private var deleting: TrashEntry?
    @Environment(\.lumenTheme) private var theme

    /// Строка корзины: что это, как называется и когда удалено.
    private struct TrashEntry: Identifiable {
        var item: LibraryItemID
        var title: String
        var deletedAt: Date?

        var id: LibraryItemID { item }
    }

    var body: some View {
        List {
            if !trash.isEmpty {
                Text("Удалённое хранится \(AppDatabase.trashRetentionDays) дней, потом исчезает само.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(trash.folders) { folder in
                row(TrashEntry(item: .folder(folder.id), title: folder.displayName, deletedAt: folder.deletedAt)) {
                    FolderLabel(folder: folder)
                }
            }
            ForEach(trash.sources) { source in
                row(TrashEntry(item: .source(source.id), title: source.displayTitle, deletedAt: source.deletedAt)) {
                    Label(source.displayTitle, systemImage: source.format.symbolName)
                }
            }
            ForEach(trash.pages) { page in
                row(TrashEntry(item: .page(page.id), title: page.displayTitle, deletedAt: page.deletedAt)) {
                    PageLabel(page: page)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if trash.isEmpty {
                ContentUnavailableView("Корзина пуста", systemImage: "trash")
            }
        }
        .background(ThemedBackground())
        .navigationTitle("Корзина")
        .toolbar {
            if isActivePane {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Очистить", role: .destructive) { isConfirmingEmpty = true }
                        .disabled(trash.isEmpty)
                }
            }
        }
        .confirmationDialog("Удалить всё из корзины навсегда?", isPresented: $isConfirmingEmpty) {
            Button("Удалить навсегда", role: .destructive) {
                Task {
                    await NoticeCenter.shared.attempt("Не удалось очистить корзину") {
                        try await database.emptyTrash()
                    }
                }
            }
        }
        .confirmationDialog(
            deleting.map { "Удалить «\($0.title)» навсегда?" } ?? "",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить навсегда", role: .destructive) {
                guard let entry = deleting else { return }
                deleting = nil
                Task {
                    await NoticeCenter.shared.attempt("Не удалось удалить") {
                        try await database.deleteForever(entry.item)
                    }
                }
            }
        } message: {
            Text("Вернуть будет нельзя.")
        }
        .task { await observe() }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func row<Title: View>(_ entry: TrashEntry, @ViewBuilder title: () -> Title) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                title()
                if let deletedAt = entry.deletedAt {
                    Text("Удалено \(deletedAt.lumenRelative)")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
            Button("Восстановить") { restore(entry.item) }
                .buttonStyle(.bordered)
            Button {
                deleting = entry
            } label: {
                Image(systemName: "trash.slash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.textSecondary)
            .help("Удалить навсегда")
        }
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("Восстановить") { restore(entry.item) }
            Button("Удалить навсегда…", role: .destructive) { deleting = entry }
        }
        .swipeActions {
            Button(role: .destructive) {
                deleting = entry
            } label: {
                Label("Удалить навсегда", systemImage: "trash.slash")
            }
        }
    }

    private func restore(_ item: LibraryItemID) {
        Task {
            let restored = await NoticeCenter.shared.attempt("Не удалось восстановить") {
                switch item {
                case .folder(let id): try await database.restoreFolder(id)
                case .page(let id): try await database.restorePage(id)
                case .source(let id): try await database.restoreSource(id)
                }
            }
            if restored { LumenSounds.play(.restore) }
        }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try TrashSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                trash = value
            }
        } catch {
            lumenLog.error("Trash observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}
