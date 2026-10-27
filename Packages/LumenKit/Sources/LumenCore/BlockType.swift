import Foundation

/// Типы блоков. Хранятся в базе строкой, так что новые типы добавляются без миграции.
public enum BlockType: String, Codable, Sendable, CaseIterable, Identifiable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulletedList
    case numberedList
    case todo
    case quote
    case callout
    case code
    case divider

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .paragraph: "Текст"
        case .heading1: "Заголовок 1"
        case .heading2: "Заголовок 2"
        case .heading3: "Заголовок 3"
        case .bulletedList: "Маркированный список"
        case .numberedList: "Нумерованный список"
        case .todo: "Задача"
        case .quote: "Цитата"
        case .callout: "Выноска"
        case .code: "Код"
        case .divider: "Разделитель"
        }
    }

    public var symbolName: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .bulletedList: "list.bullet"
        case .numberedList: "list.number"
        case .todo: "checkmark.square"
        case .quote: "text.quote"
        case .callout: "lightbulb"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        }
    }

    /// Дополнительные слова для поиска в slash-меню.
    public var keywords: [String] {
        switch self {
        case .paragraph: ["text", "текст", "абзац"]
        case .heading1: ["h1", "heading", "заголовок"]
        case .heading2: ["h2", "heading", "заголовок"]
        case .heading3: ["h3", "heading", "заголовок"]
        case .bulletedList: ["list", "bullet", "список"]
        case .numberedList: ["list", "number", "список", "номер"]
        case .todo: ["todo", "task", "check", "задача", "чекбокс"]
        case .quote: ["quote", "цитата"]
        case .callout: ["callout", "note", "выноска", "заметка"]
        case .code: ["code", "код"]
        case .divider: ["divider", "line", "разделитель", "линия"]
        }
    }

    /// Есть ли у блока редактируемый текст.
    public var hasText: Bool { self != .divider }

    /// Тип нового блока, который появляется по Return в конце этого блока:
    /// списки и задачи продолжаются, всё остальное превращается в обычный текст.
    public var continuation: BlockType {
        switch self {
        case .bulletedList, .numberedList, .todo: self
        default: .paragraph
        }
    }

    /// Подходит ли тип под запрос из slash-меню.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query) || keywords.contains { $0.hasPrefix(query) }
    }
}
