import Foundation

/// Источник: книга или любой файл, который читают в приложении и к которому пишут заметки.
/// Сам файл лежит во вложениях, источник хранит только его имя.
public struct Source: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var author: String?
    public var format: SourceFormat
    /// Имя файла во вложениях.
    public var file: String
    /// Имя файла, с которым источник добавили: по нему видно расширение и исходное название.
    public var originalName: String
    /// Картинка обложки во вложениях, если её удалось достать из файла.
    public var cover: String?
    /// Папка библиотеки и место на её холсте, как у страниц.
    public var folderId: UUID?
    public var canvasX: Double?
    public var canvasY: Double?
    /// Где остановились в прошлый раз.
    public var locator: SourceLocator?
    /// Сколько прочитано, от 0 до 1.
    public var progress: Double
    public var lastOpenedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    /// Мягкое удаление: источник лежит в корзине.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        format: SourceFormat,
        file: String,
        originalName: String,
        cover: String? = nil,
        folderId: UUID? = nil,
        position: LibraryPoint? = nil,
        locator: SourceLocator? = nil,
        progress: Double = 0,
        lastOpenedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.format = format
        self.file = file
        self.originalName = originalName
        self.cover = cover
        self.folderId = folderId
        self.canvasX = position?.x
        self.canvasY = position?.y
        self.locator = locator
        self.progress = progress
        self.lastOpenedAt = lastOpenedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? originalName : trimmed
    }

    public var isTrashed: Bool { deletedAt != nil }

    public var position: LibraryPoint? {
        get { LibraryPoint(x: canvasX, y: canvasY) }
        set {
            canvasX = newValue?.x
            canvasY = newValue?.y
        }
    }
}

/// Формат файла источника. Хранится строкой, так что новые форматы добавляются без миграции.
public enum SourceFormat: String, Codable, Sendable, CaseIterable {
    case epub, pdf, fb2, docx, pptx, rtf, doc, odt, txt, markdown, html, cbz, image
    /// Таблицы Excel и Numbers, Keynote, Pages и прочее: показываются системным просмотром.
    case other

    public init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        case "fb2": self = .fb2
        case "docx", "docm", "dotx": self = .docx
        case "pptx", "pptm", "ppsx": self = .pptx
        case "rtf": self = .rtf
        case "doc": self = .doc
        case "odt": self = .odt
        case "txt", "text", "log": self = .txt
        case "md", "markdown": self = .markdown
        case "html", "htm", "xhtml": self = .html
        case "cbz": self = .cbz
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp": self = .image
        default: self = .other
        }
    }

    /// Короткая подпись на обложке: «EPUB», «Word», «Слайды».
    public var label: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .fb2: "FB2"
        case .docx, .doc, .odt, .rtf: "Документ"
        case .pptx: "Слайды"
        case .txt: "Текст"
        case .markdown: "Markdown"
        case .html: "HTML"
        case .cbz: "Комикс"
        case .image: "Картинка"
        case .other: "Файл"
        }
    }

    public var symbolName: String {
        switch self {
        case .epub, .fb2: "book.closed"
        case .pdf: "doc.richtext"
        case .docx, .doc, .odt, .rtf: "doc.text"
        case .pptx: "rectangle.on.rectangle"
        case .txt, .markdown: "text.alignleft"
        case .html: "globe"
        case .cbz: "photo.stack"
        case .image: "photo"
        case .other: "doc"
        }
    }

    /// Книга, а не документ: такие источники рисуются в библиотеке книжной обложкой.
    public var isBook: Bool {
        switch self {
        case .epub, .fb2, .pdf, .cbz: true
        default: false
        }
    }
}

/// Место в источнике: страница PDF или глава книги и точка внутри неё.
/// Для выделения ещё и сам текст: по нему выделение находится заново, даже если вёрстка поменялась.
public struct SourceLocator: Hashable, Codable, Sendable {
    /// Номер страницы PDF, главы книги или слайда, с нуля.
    public var section: Int
    /// Насколько прокручена глава, от 0 до 1. У PDF не нужна.
    public var progression: Double
    /// Выделенный текст.
    public var text: String?
    /// Сколько символов текста главы стоит до начала выделения: из нескольких одинаковых
    /// фрагментов выбирается ближайший к этому месту.
    public var textOffset: Int?
    /// Прямоугольники выделения на странице PDF, в координатах страницы.
    public var rects: [LocatorRect]?

    public init(
        section: Int,
        progression: Double = 0,
        text: String? = nil,
        textOffset: Int? = nil,
        rects: [LocatorRect]? = nil
    ) {
        self.section = max(section, 0)
        self.progression = min(max(progression, 0), 1)
        self.text = text
        self.textOffset = textOffset
        self.rects = rects
    }
}

public struct LocatorRect: Hashable, Codable, Sendable {
    /// Страница PDF, если выделение перешло на следующую. `nil` это страница `SourceLocator.section`.
    public var page: Int?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(page: Int? = nil, x: Double, y: Double, width: Double, height: Double) {
        self.page = page
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Выделение в источнике цветом, с необязательной заметкой. Из него делаются выписки.
public struct Highlight: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sourceId: UUID
    public var locator: SourceLocator
    public var text: String
    public var note: String?
    public var color: HighlightColor
    /// Подпись места для выписки: «стр. 12», «Глава 3».
    public var label: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        sourceId: UUID,
        locator: SourceLocator,
        text: String,
        note: String? = nil,
        color: HighlightColor = .yellow,
        label: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.locator = locator
        self.text = text
        self.note = note
        self.color = color
        self.label = label
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Цвета выделений. Конкретные оттенки задаёт читалка.
public enum HighlightColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case yellow, orange, pink, green, blue

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .yellow: "Жёлтый"
        case .orange: "Оранжевый"
        case .pink: "Розовый"
        case .green: "Зелёный"
        case .blue: "Синий"
        }
    }

    /// Цвет в шестнадцатеричном виде для PDF и HTML.
    public var hex: UInt32 {
        switch self {
        case .yellow: 0xFFD45C
        case .orange: 0xFF9A5C
        case .pink: 0xFF7EB0
        case .green: 0x8FDB7A
        case .blue: 0x7EC3FF
        }
    }
}

/// Ссылка выписки на выделение в источнике. Лежит в содержимом блока «Выписка».
public struct ExcerptReference: Hashable, Codable, Sendable {
    public var sourceId: UUID
    public var highlightId: UUID
    /// Подпись места, см. `Highlight.label`.
    public var label: String

    public init(sourceId: UUID, highlightId: UUID, label: String) {
        self.sourceId = sourceId
        self.highlightId = highlightId
        self.label = label
    }

    /// Ссылка вида `lumen://source/<id>/highlight/<id>`.
    public var url: URL {
        URL(string: "lumen://source/\(sourceId.uuidString)/highlight/\(highlightId.uuidString)")!
    }

    public init?(url: URL) {
        guard url.scheme == "lumen", url.host == "source" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3, parts[1] == "highlight",
              let sourceId = UUID(uuidString: parts[0]),
              let highlightId = UUID(uuidString: parts[2]) else { return nil }
        self.init(sourceId: sourceId, highlightId: highlightId, label: "")
    }
}
