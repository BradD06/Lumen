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
    /// Ссылка на другую страницу или подстраницу (`content.pageId`).
    case page
    /// Картинка из вложений (`content.attachment`).
    case image
    /// Сворачиваемый блок: дочерние блоки видны, пока он раскрыт.
    case toggle
    /// Ряд колонок. Его дети это колонки (`column`), у колонок свои дочерние блоки.
    case columnList
    case column

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
        case .page: "Страница"
        case .image: "Картинка"
        case .toggle: "Сворачиваемый блок"
        case .columnList: "Колонки"
        case .column: "Колонка"
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
        case .page: "doc.text"
        case .image: "photo"
        case .toggle: "chevron.right.circle"
        case .columnList, .column: "rectangle.split.3x1"
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
        case .page: ["page", "subpage", "страница", "подстраница"]
        case .image: ["image", "photo", "picture", "картинка", "фото", "изображение"]
        case .toggle: ["toggle", "collapse", "свернуть", "раскрывающийся", "тоггл"]
        case .columnList, .column: ["columns", "колонки"]
        }
    }

    /// Есть ли у блока редактируемый текст.
    public var hasText: Bool {
        switch self {
        case .divider, .page, .image, .columnList, .column: false
        default: true
        }
    }

    /// Служебные блоки-контейнеры колонок: их не выбирают в меню, они появляются при перетаскивании.
    public var isLayout: Bool { self == .columnList || self == .column }

    /// Можно ли выбрать тип в slash-меню.
    public var isInsertable: Bool { !isLayout }

    /// Можно ли превратить в этот тип уже написанный блок (меню «Превратить в»).
    /// Страница и картинка создаются только заново, из slash-меню.
    public var isConvertible: Bool { hasText || self == .divider }

    /// Можно ли вложить в блок другие блоки клавишей Tab.
    public var canNest: Bool {
        switch self {
        case .paragraph, .bulletedList, .numberedList, .todo, .toggle, .quote, .callout: true
        default: false
        }
    }

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
