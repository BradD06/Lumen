import Foundation

/// Блок страницы: абзац, заголовок, пункт списка и так далее.
public struct Block: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var pageId: UUID
    /// Родительский блок для вложенности (toggle, вложенные списки). Пока не используется редактором.
    public var parentBlockId: UUID?
    public var type: BlockType
    public var content: BlockContent
    public var sortKey: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        pageId: UUID,
        parentBlockId: UUID? = nil,
        type: BlockType = .paragraph,
        content: BlockContent = BlockContent(),
        sortKey: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.pageId = pageId
        self.parentBlockId = parentBlockId
        self.type = type
        self.content = content
        self.sortKey = sortKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var text: String {
        get { content.text }
        set { content.text = newValue }
    }
}

/// Содержимое блока. Хранится в базе как JSON.
public struct BlockContent: Hashable, Codable, Sendable {
    /// Текст как массив фрагментов с атрибутами, а не HTML.
    public var runs: [TextRun]
    /// Отметка для блока-задачи.
    public var isChecked: Bool

    public init(runs: [TextRun] = [], isChecked: Bool = false) {
        self.runs = runs
        self.isChecked = isChecked
    }

    public init(text: String, isChecked: Bool = false) {
        self.init(runs: text.isEmpty ? [] : [TextRun(text)], isChecked: isChecked)
    }

    /// Простой текст блока. Запись заменяет все фрагменты одним без атрибутов:
    /// редактор форматирования появится позже, пока он работает только с простым текстом.
    public var text: String {
        get { runs.map(\.text).joined() }
        set { runs = newValue.isEmpty ? [] : [TextRun(newValue)] }
    }

    private enum CodingKeys: String, CodingKey {
        case runs, isChecked
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runs = try container.decodeIfPresent([TextRun].self, forKey: .runs) ?? []
        isChecked = try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
    }
}

public struct TextRun: Hashable, Codable, Sendable {
    public var text: String
    public var marks: Set<TextMark>
    public var link: String?

    public init(_ text: String, marks: Set<TextMark> = [], link: String? = nil) {
        self.text = text
        self.marks = marks
        self.link = link
    }
}

public enum TextMark: String, Hashable, Codable, Sendable, CaseIterable {
    case bold, italic, underline, strikethrough, code
}
