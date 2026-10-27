import Foundation
import GRDB
import LumenCore

public struct SearchResult: Identifiable, Hashable, Sendable {
    public var pageId: UUID
    public var title: String
    public var snippet: String

    public var id: UUID { pageId }
}

extension AppDatabase {
    /// Полнотекстовый поиск по названиям и тексту страниц (FTS5). Слова ищутся по префиксу.
    public func search(_ query: String, limit: Int = 30) async throws -> [SearchResult] {
        guard let pattern = Self.ftsPattern(query) else { return [] }
        return try await reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT pageId, title, snippet(pageSearch, 2, '', '', '…', 12) AS snippet
                FROM pageSearch
                WHERE pageSearch MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [pattern, limit])
            .compactMap { row -> SearchResult? in
                let idText: String = row["pageId"]
                guard let id = UUID(uuidString: idText) else { return nil }
                return SearchResult(pageId: id, title: row["title"] ?? "", snippet: row["snippet"] ?? "")
            }
        }
    }

    /// Превращает пользовательский ввод в безопасный запрос FTS5: каждое слово в кавычках и с `*`.
    static func ftsPattern(_ query: String) -> String? {
        let tokens = query
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
