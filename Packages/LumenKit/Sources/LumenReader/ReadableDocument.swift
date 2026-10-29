import Foundation
import LumenCore

/// Книга или документ, переведённые в HTML для экрана чтения: главы по порядку и метаданные.
public struct ReadableDocument: Codable, Hashable, Sendable {
    public var title: String?
    public var author: String?
    /// Главы (для EPUB и FB2), слайды или один раздел для документа.
    public var sections: [ReadableSection]
    /// Картинка обложки относительно папки документа.
    public var coverPath: String?
    /// Оглавление. Пустое, если в файле его нет: тогда читалка соберёт заголовки открытой главы сама.
    public var toc: [TocEntry]

    public init(
        title: String? = nil,
        author: String? = nil,
        sections: [ReadableSection],
        coverPath: String? = nil,
        toc: [TocEntry] = []
    ) {
        self.title = title
        self.author = author
        self.sections = sections
        self.coverPath = coverPath
        self.toc = toc
    }
}

/// Пункт оглавления: куда ведёт и насколько вложен.
public struct TocEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(section)#\(anchor ?? "")#\(title)" }
    public var title: String
    /// Глава (или страница PDF), с нуля.
    public var section: Int
    /// id элемента внутри главы. `nil` это начало главы.
    public var anchor: String?
    /// 0 для верхнего уровня.
    public var level: Int

    public init(title: String, section: Int, anchor: String? = nil, level: Int = 0) {
        self.title = title
        self.section = section
        self.anchor = anchor
        self.level = level
    }
}

public struct ReadableSection: Codable, Hashable, Sendable {
    public var title: String
    /// HTML-файл главы относительно папки документа.
    public var path: String

    public init(title: String, path: String) {
        self.title = title
        self.path = path
    }
}

/// Документ, готовый к чтению: где лежит папка с HTML и что в ней.
public struct PreparedDocument: Hashable, Sendable {
    public var root: URL
    public var document: ReadableDocument

    public func url(for section: Int) -> URL? {
        guard document.sections.indices.contains(section) else { return nil }
        return root.appendingPathComponent(document.sections[section].path)
    }

    public var coverURL: URL? {
        document.coverPath.map { root.appendingPathComponent($0) }
    }
}

public enum ReaderError: Error, Equatable {
    /// Формат не переводится в HTML: его показывает системный просмотр.
    case unsupportedFormat
    /// Файл повреждён или это не тот формат, что указан в расширении.
    case unreadable
}

/// Переводит файл источника в HTML и складывает результат в кэш, чтобы второе открытие было мгновенным.
public enum DocumentConverter {
    /// Номер версии конвертеров: если поменять вывод, старый кэш перестанет подходить.
    static let version = 2

    /// Форматы, которые читалка показывает как HTML: с ними работают выделения и выписки.
    public static func canConvert(_ format: SourceFormat) -> Bool {
        switch format {
        case .epub, .fb2, .docx, .pptx, .rtf, .txt, .markdown, .html, .cbz: true
        #if os(macOS)
        case .doc, .odt: true
        #endif
        default: false
        }
    }

    /// Готовит документ к чтению. `cacheKey` должен быть уникален для файла, например его имя во вложениях.
    public static func prepare(file: URL, format: SourceFormat, cacheKey: String) async throws -> PreparedDocument {
        try await Task.detached(priority: .userInitiated) {
            try prepareSync(file: file, format: format, cacheKey: cacheKey)
        }.value
    }

    /// Удаляет кэш документа, например когда источник удалили навсегда.
    public static func removeCache(for cacheKey: String) {
        try? FileManager.default.removeItem(at: cacheFolder(for: cacheKey))
    }

    static func prepareSync(file: URL, format: SourceFormat, cacheKey: String) throws -> PreparedDocument {
        guard canConvert(format) else { throw ReaderError.unsupportedFormat }
        let fileManager = FileManager.default
        let root = cacheFolder(for: cacheKey)
        let manifest = root.appendingPathComponent("lumen-manifest.json")
        if let data = try? Data(contentsOf: manifest),
           let document = try? JSONDecoder().decode(ReadableDocument.self, from: data) {
            return PreparedDocument(root: root, document: document)
        }

        // Сначала во временную папку: прерванный перевод не оставит в кэше половину книги.
        let work = root.deletingLastPathComponent()
            .appendingPathComponent(".\(root.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let document = try convert(file: file, format: format, into: work)
            try JSONEncoder().encode(document).write(to: work.appendingPathComponent("lumen-manifest.json"))
            try? fileManager.removeItem(at: root)
            try fileManager.moveItem(at: work, to: root)
            return PreparedDocument(root: root, document: document)
        } catch {
            try? fileManager.removeItem(at: work)
            throw error
        }
    }

    static func convert(file: URL, format: SourceFormat, into folder: URL) throws -> ReadableDocument {
        switch format {
        case .epub: try EPUBConverter.convert(file: file, into: folder)
        case .fb2: try FB2Converter.convert(file: file, into: folder)
        case .docx: try DOCXConverter.convert(file: file, into: folder)
        case .pptx: try PPTXConverter.convert(file: file, into: folder)
        case .cbz: try CBZConverter.convert(file: file, into: folder)
        case .txt, .markdown, .html, .rtf, .doc, .odt: try TextConverter.convert(file: file, format: format, into: folder)
        case .pdf, .image, .other: throw ReaderError.unsupportedFormat
        }
    }

    static func cacheFolder(for cacheKey: String) -> URL {
        let caches = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let safeKey = (cacheKey as NSString).lastPathComponent
        return caches
            .appendingPathComponent("LumenReader", isDirectory: true)
            .appendingPathComponent("\(safeKey)-v\(version)", isDirectory: true)
    }
}
