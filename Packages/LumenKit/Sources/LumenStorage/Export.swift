import Foundation
import GRDB
import LumenCore
import ZIPFoundation

/// Готовый к сохранению файл экспорта.
public struct ExportedFile: Sendable {
    public enum Kind: Sendable {
        case markdown
        /// Markdown с картинками: zip-архив с файлом страницы и папкой `images`.
        case markdownArchive
        case pdf
    }

    public var kind: Kind
    /// Имя без расширения.
    public var name: String
    public var data: Data

    public init(kind: Kind, name: String, data: Data) {
        self.kind = kind
        self.name = name
        self.data = data
    }

    public var fileExtension: String {
        switch kind {
        case .markdown: "md"
        case .markdownArchive: "zip"
        case .pdf: "pdf"
        }
    }
}

extension AppDatabase {
    /// Страница со всеми блоками и названиями, на которые они ссылаются.
    public func pageExport(_ pageId: UUID) async throws -> PageExport? {
        try await reader.read { db in
            guard let page = try Page.fetchOne(db, key: pageId) else { return nil }
            let blocks = try Block.filter(Column("pageId") == pageId).order(Column("sortKey")).fetchAll(db)
            let pageIds = Set(blocks.compactMap(\.content.pageId))
            let sourceIds = Set(blocks.compactMap { $0.content.excerpt?.sourceId })
            let pages = try Page.fetchAll(db, keys: pageIds)
            let sources = try Source.fetchAll(db, keys: sourceIds)
            return PageExport(
                page: page,
                blocks: blocks,
                pageTitles: Dictionary(pages.map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { first, _ in first }),
                sourceTitles: Dictionary(sources.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    /// Страница в Markdown. Без картинок это один файл `.md`, с картинками zip-архив:
    /// в нём файл страницы и папка `images`, на которую ссылается текст.
    public func exportMarkdown(_ pageId: UUID) async throws -> ExportedFile? {
        guard let export = try await pageExport(pageId) else { return nil }
        let markdown = export.markdown()
        let images = export.imageNames.filter { FileManager.default.fileExists(atPath: attachments.url(for: $0).path) }
        guard !images.isEmpty else {
            return ExportedFile(kind: .markdown, name: export.fileName, data: Data(markdown.utf8))
        }

        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("LumenMarkdown-\(UUID().uuidString)", isDirectory: true)
        let folder = staging.appendingPathComponent(export.fileName, isDirectory: true)
        let imagesFolder = folder.appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try Data(markdown.utf8).write(to: folder.appendingPathComponent("\(export.fileName).md"))
        for name in images {
            try fileManager.copyItem(at: attachments.url(for: name), to: imagesFolder.appendingPathComponent(name))
        }
        let archive = staging.appendingPathComponent("page.zip")
        try fileManager.zipItem(at: folder, to: archive, shouldKeepParent: true, compressionMethod: .deflate)
        return ExportedFile(kind: .markdownArchive, name: export.fileName, data: try Data(contentsOf: archive))
    }
}
