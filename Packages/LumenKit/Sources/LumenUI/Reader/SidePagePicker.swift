import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Выбор заметки для панели рядом с книгой: заметки к книге, страницы из её папки,
/// недавние страницы и поиск по всем.
struct SidePagePicker: View {
    let database: AppDatabase
    let source: Source?
    let currentPageId: UUID?
    let bookNotesPageId: UUID?
    var onOpen: (UUID) -> Void
    var onCreate: () -> Void

    @State private var pages: [Page] = []
    @State private var folderName: String?
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @Environment(\.lumenTheme) private var theme

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Страницы из той же папки, что и книга. Заметки к книгам в библиотеке не лежат, их здесь нет.
    private var folderPages: [Page] {
        pages.filter { $0.folderId == source?.folderId && $0.sourceId == nil && $0.id != bookNotesPageId }
    }

    private var recentPages: [Page] {
        let shown = Set(folderPages.map(\.id))
        return Array(pages.filter { !shown.contains($0.id) && $0.id != bookNotesPageId }.prefix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.textSecondary)
                TextField("Найти заметку", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if isSearching {
                        let live = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        let found = results.compactMap { live[$0.pageId] }
                        if found.isEmpty {
                            Text("Ничего не нашлось")
                                .font(.callout)
                                .foregroundStyle(theme.textSecondary)
                                .padding(16)
                        }
                        ForEach(found) { row($0) }
                    } else {
                        if let bookNotesPageId {
                            Button {
                                onOpen(bookNotesPageId)
                            } label: {
                                rowLabel(
                                    icon: "📖",
                                    title: "Заметки к книге",
                                    isCurrent: currentPageId == bookNotesPageId
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: onCreate) {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .frame(width: 24)
                                    .foregroundStyle(theme.accent)
                                Text(folderName.map { "Новая заметка в «\($0)»" } ?? "Новая заметка")
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !folderPages.isEmpty {
                            header(folderName.map { "В папке «\($0)»" } ?? "В библиотеке")
                            ForEach(folderPages) { row($0) }
                        }
                        if !recentPages.isEmpty {
                            header("Недавние")
                            ForEach(recentPages) { row($0) }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
        }
        .frame(minWidth: 300, idealWidth: 340, minHeight: 320, idealHeight: 440)
        .task { await loadPages() }
        .task(id: query) { await runSearch() }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func row(_ page: Page) -> some View {
        Button {
            onOpen(page.id)
        } label: {
            rowLabel(
                icon: page.icon ?? (page.sourceId != nil ? "📖" : "📄"),
                title: page.displayTitle,
                isCurrent: page.id == currentPageId
            )
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(icon: String, title: String, isCurrent: Bool) -> some View {
        HStack(spacing: 10) {
            Text(icon).frame(width: 24)
            Text(title)
                .lineLimit(1)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isCurrent ? theme.cardFill : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private func loadPages() async {
        let folderId = source?.folderId
        do {
            let (pages, folder) = try await database.reader.read { db in
                let pages = try Page
                    .filter(Column("deletedAt") == nil)
                    .order(Column("updatedAt").desc)
                    .fetchAll(db)
                let folder = try folderId.flatMap { try Folder.fetchOne(db, key: $0) }
                return (pages, folder)
            }
            self.pages = pages
            folderName = folder?.name
        } catch {
            print("Failed to load pages for the side pane: \(error)")
        }
    }

    private func runSearch() async {
        guard isSearching else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        results = (try? await database.search(query)) ?? []
    }
}
