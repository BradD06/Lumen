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
    /// Страница, на которую ссылается блок «Страница».
    public var pageId: UUID?
    /// Имя файла во вложениях для блока «Картинка».
    public var attachment: String?
    /// Свёрнут ли сворачиваемый блок.
    public var isCollapsed: Bool
    public var textColor: BlockColor?
    public var backgroundColor: BlockColor?

    public init(
        runs: [TextRun] = [],
        isChecked: Bool = false,
        pageId: UUID? = nil,
        attachment: String? = nil,
        isCollapsed: Bool = false,
        textColor: BlockColor? = nil,
        backgroundColor: BlockColor? = nil
    ) {
        self.runs = runs
        self.isChecked = isChecked
        self.pageId = pageId
        self.attachment = attachment
        self.isCollapsed = isCollapsed
        self.textColor = textColor
        self.backgroundColor = backgroundColor
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
        case runs, isChecked, pageId, attachment, isCollapsed, textColor, backgroundColor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runs = try container.decodeIfPresent([TextRun].self, forKey: .runs) ?? []
        isChecked = try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
        pageId = try container.decodeIfPresent(UUID.self, forKey: .pageId)
        attachment = try container.decodeIfPresent(String.self, forKey: .attachment)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        // Неизвестный цвет (например, из более новой версии) не ломает чтение блока.
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor).flatMap(BlockColor.init(rawValue:))
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
            .flatMap(BlockColor.init(rawValue:))
    }
}

/// Цвета текста и фона блока, как в Notion. Конкретные оттенки задаёт тема.
public enum BlockColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gray: "Серый"
        case .brown: "Коричневый"
        case .orange: "Оранжевый"
        case .yellow: "Жёлтый"
        case .green: "Зелёный"
        case .blue: "Синий"
        case .purple: "Фиолетовый"
        case .pink: "Розовый"
        case .red: "Красный"
        }
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
