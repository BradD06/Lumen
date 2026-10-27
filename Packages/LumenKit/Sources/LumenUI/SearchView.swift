import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Быстрый переход по ⌘K: полнотекстовый поиск по названиям и тексту страниц.
struct SearchView: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(results) { result in
                Button {
                    onOpen(result.pageId)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title.isEmpty ? "Без названия" : result.title)
                            .font(.headline)
                        if !result.snippet.isEmpty {
                            Text(result.snippet)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        "Поиск по заметкам",
                        systemImage: "magnifyingglass",
                        description: Text("Ищет по названиям и тексту всех страниц")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Найти страницу или текст")
            .task(id: query) { await runSearch() }
            .navigationTitle("Поиск")
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

    private func runSearch() async {
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let found = (try? await database.search(query)) ?? []
        guard !Task.isCancelled else { return }
        results = found
    }
}
