import Foundation

/// Как показаны книги в комнате «Полка»: корешками на полках, обложками или списком.
public enum ShelfDisplay: String, CaseIterable, Identifiable, Sendable {
    case spines
    case covers
    case list

    public var id: Self { self }

    public var title: String {
        switch self {
        case .spines: "Корешки"
        case .covers: "Обложки"
        case .list: "Список"
        }
    }

    public var symbolName: String {
        switch self {
        case .spines: "books.vertical"
        case .covers: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

/// Поиск по полке: книга подходит, если каждое слово запроса есть в названии или у автора.
/// Регистр, «ё» и знаки над буквами не важны.
public enum ShelfSearch {
    /// Слова запроса, уже приведённые к виду для сравнения. Пустой запрос: пустой список.
    public static func terms(_ query: String) -> [String] {
        normalized(query)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
    }

    public static func matches(_ book: Source, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let text = normalized([book.displayTitle, book.author ?? ""].joined(separator: " "))
        return terms.allSatisfy { text.contains($0) }
    }

    /// Книги, которые подходят под запрос, в том же порядке. Пустой запрос оставляет все.
    public static func filter(_ books: [Source], query: String) -> [Source] {
        let terms = terms(query)
        guard !terms.isEmpty else { return books }
        return books.filter { matches($0, terms: terms) }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
