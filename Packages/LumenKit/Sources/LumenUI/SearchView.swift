import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Быстрый переход по ⌘K: страницы по названию и тексту, книги по названию и автору,
/// выделения из книг по цитате и комментарию.
struct SearchView: View {
    let database: AppDatabase
    /// Вкладка «Поиск» на iPhone: без своего стека навигации и кнопки «Закрыть».
    var isEmbedded = false
    var onOpen: (UUID) -> Void
    /// Открыть книгу, а если указано выделение, то на его месте.
    var onOpenSource: (UUID, UUID?) -> Void

    @State private var query = ""
    @State private var results = LibrarySearchResults.empty
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { dismiss() }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 420)
            #endif
        }
    }

    private var content: some View {
        List {
            if !results.pages.isEmpty {
                Section("Страницы") {
                    ForEach(results.pages) { result in
                        Button {
                            onOpen(result.pageId)
                        } label: {
                            row(
                                title: result.title.isEmpty ? "Без названия" : result.title,
                                detail: result.snippet,
                                systemImage: "doc.text"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.sources.isEmpty {
                Section("Книги и файлы") {
                    ForEach(results.sources) { source in
                        Button {
                            onOpenSource(source.id, nil)
                        } label: {
                            row(
                                title: source.displayTitle,
                                detail: [source.author, progressText(source)].compactMap { $0 }.joined(separator: " · "),
                                systemImage: source.format.symbolName
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.highlights.isEmpty {
                Section("Выделения") {
                    ForEach(results.highlights) { match in
                        Button {
                            onOpenSource(match.highlight.sourceId, match.highlight.id)
                        } label: {
                            HighlightSearchRow(match: match)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView(
                    "Поиск по всему",
                    systemImage: "magnifyingglass",
                    description: Text("Ищет по страницам, книгам и выделениям из книг")
                )
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Страница, книга или цитата")
        .task(id: query) { await runSearch() }
        .navigationTitle("Поиск")
    }

    private func row(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func progressText(_ source: Source) -> String? {
        guard source.progress > 0 else { return nil }
        return "прочитано \(Int((source.progress * 100).rounded()))%"
    }

    private func runSearch() async {
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let found: LibrarySearchResults
        do {
            found = try await database.searchEverything(query)
        } catch {
            lumenLog.error("Search failed: \(String(describing: error), privacy: .public)")
            found = .empty
        }
        guard !Task.isCancelled else { return }
        results = found
    }
}

/// Найденное выделение: цветная полоска, цитата, комментарий и откуда она.
private struct HighlightSearchRow: View {
    let match: HighlightMatch

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Color(hex: match.highlight.color.hex))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(match.highlight.text)
                    .font(.system(.callout, design: .serif))
                    .lineLimit(3)
                if let note = match.highlight.note {
                    Label(note, systemImage: "text.bubble")
                        .font(.caption)
                        .lineLimit(2)
                }
                Text([match.sourceTitle, match.highlight.label].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
