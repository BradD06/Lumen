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

/// Выделение из книги, найденное поиском, вместе с названием книги для подписи.
public struct HighlightMatch: Identifiable, Hashable, Sendable {
    public var highlight: Highlight
    public var sourceTitle: String

    public var id: UUID { highlight.id }
}

/// Всё, что нашёл общий поиск: страницы, книги и выделения из книг.
public struct LibrarySearchResults: Equatable, Sendable {
    public var pages: [SearchResult]
    public var sources: [Source]
    public var highlights: [HighlightMatch]

    public static let empty = LibrarySearchResults(pages: [], sources: [], highlights: [])

    public var isEmpty: Bool { pages.isEmpty && sources.isEmpty && highlights.isEmpty }
}

extension AppDatabase {
    /// Общий поиск по ⌘K: страницы по тексту (FTS5), книги по названию, автору и имени файла,
    /// выделения по цитате и комментарию. Каждое слово запроса должно найтись, регистр не важен.
    public func searchEverything(_ query: String, limit: Int = 30) async throws -> LibrarySearchResults {
        let words = Self.searchWords(query)
        guard !words.isEmpty else { return .empty }
        let pages = try await search(query, limit: limit)
        return try await reader.read { db in
            let sources = try Source
                .filter(Column("deletedAt") == nil)
                .order(Column("lastOpenedAt").desc, Column("createdAt").desc)
                .fetchAll(db)
            let titles = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.displayTitle) })
            let foundSources = sources.filter { source in
                Self.matches(words, in: [source.title, source.author ?? "", source.originalName])
            }
            let highlights = try Highlight
                .filter(Column("deletedAt") == nil)
                .order(Column("createdAt").desc)
                .fetchAll(db)
                .compactMap { highlight -> HighlightMatch? in
                    // Выделения из книг в корзине не показываем.
                    guard let title = titles[highlight.sourceId],
                          Self.matches(words, in: [highlight.text, highlight.note ?? ""]) else { return nil }
                    return HighlightMatch(highlight: highlight, sourceTitle: title)
                }
            return LibrarySearchResults(
                pages: pages,
                sources: Array(foundSources.prefix(limit)),
                highlights: Array(highlights.prefix(limit))
            )
        }
    }

    static func searchWords(_ query: String) -> [String] {
        query.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Каждое слово есть хотя бы в одном из полей. Сравнение без учёта регистра и «ё/е» не различает.
    static func matches(_ words: [String], in fields: [String]) -> Bool {
        words.allSatisfy { word in
            fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
