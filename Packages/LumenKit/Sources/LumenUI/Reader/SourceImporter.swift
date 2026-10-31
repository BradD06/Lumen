import Foundation
import LumenCore
import LumenReader
import LumenStorage
import UniformTypeIdentifiers

/// Добавляет книги и файлы в библиотеку: копирует файл во вложения, достаёт название,
/// автора и обложку, а книги заранее переводит в HTML для читалки.
enum SourceImporter {
    /// Что можно выбрать в окне добавления: всё, что откроет читалка или системный просмотр.
    static let contentTypes: [UTType] = [.item]

    /// Добавляет файлы по одному. Файлы из «Файлов» и Finder доступны только внутри
    /// `startAccessingSecurityScopedResource`, поэтому копия делается сразу.
    static func importFiles(
        _ urls: [URL],
        into database: AppDatabase,
        folderId: UUID?,
        positions: [LibraryPoint]
    ) async -> [Source] {
        var sources: [Source] = []
        for (index, url) in urls.enumerated() {
            let position = positions.indices.contains(index) ? positions[index] : nil
            do {
                sources.append(try await importFile(url, into: database, folderId: folderId, position: position))
            } catch {
                await NoticeCenter.shared.report("Не удалось добавить «\(url.lastPathComponent)»", error)
            }
        }
        return sources
    }

    static func importFile(_ url: URL, into database: AppDatabase, folderId: UUID?, position: LibraryPoint?) async throws -> Source {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let attachments = database.attachments
        let file = try await Task.detached { try attachments.importFile(at: url) }.value
        let format = SourceFormat(fileExtension: url.pathExtension)
        let metadata = await SourceMetadata.read(file: attachments.url(for: file), format: format, cacheKey: file)
        let cover = metadata.cover.flatMap { try? attachments.save($0, fileExtension: "jpg") }
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        return try await database.addSource(
            title: metadata.title ?? fallbackTitle,
            author: metadata.author,
            format: format,
            file: file,
            originalName: url.lastPathComponent,
            cover: cover,
            folderId: folderId,
            position: position
        )
    }
}
