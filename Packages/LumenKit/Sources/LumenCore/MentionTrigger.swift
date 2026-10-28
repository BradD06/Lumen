/// Ссылка на страницу через `[[` или `@` в конце текста блока: пока пользователь пишет запрос,
/// редактор показывает список страниц.
public enum MentionTrigger {
    public struct Match: Equatable, Sendable {
        /// Текст блока до триггера.
        public var prefix: String
        /// Что написано после триггера: по этому ищется страница.
        public var query: String
    }

    private static let maxQueryLength = 60

    public static func match(_ text: String) -> Match? {
        if let range = text.range(of: "[[", options: .backwards) {
            let query = text[range.upperBound...]
            if !query.contains("]"), query.count <= maxQueryLength {
                return Match(prefix: String(text[..<range.lowerBound]), query: String(query))
            }
        }
        if let range = text.range(of: "@", options: .backwards) {
            let before = text[..<range.lowerBound]
            let query = text[range.upperBound...]
            // `@` в середине слова (почта и тому подобное) не считается.
            let startsWord = before.last?.isWhitespace ?? true
            if startsWord, query.first?.isWhitespace != true, query.count <= maxQueryLength {
                return Match(prefix: String(before), query: String(query))
            }
        }
        return nil
    }
}
