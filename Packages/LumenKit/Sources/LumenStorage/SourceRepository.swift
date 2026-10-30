import Foundation
import GRDB
import LumenCore

extension AppDatabase {
    // MARK: Источники

    /// Добавляет источник, файл которого уже лежит во вложениях (`AttachmentStore.importFile`).
    @discardableResult
    public func addSource(
        title: String,
        author: String? = nil,
        format: SourceFormat,
        file: String,
        originalName: String,
        cover: String? = nil,
        folderId: UUID? = nil,
        position: LibraryPoint? = nil
    ) async throws -> Source {
        try await writer.write { db in
            let source = Source(
                title: title,
                author: author,
                format: format,
                file: file,
                originalName: originalName,
                cover: cover,
                folderId: folderId,
                position: position
            )
            try source.insert(db)
            return source
        }
    }

    public func source(_ id: UUID) async throws -> Source? {
        try await reader.read { db in try Source.fetchOne(db, key: id) }
    }

    public func renameSource(_ id: UUID, title: String) async throws {
        try await writer.write { db in
            try Self.updateSource(db, id) { $0.title = title }
        }
    }

    /// Кладёт источник в папку (`nil` = корень библиотеки), на новом месте он встаёт в свободную ячейку.
    public func moveSource(_ id: UUID, toFolder folderId: UUID?) async throws {
        try await writer.write { db in
            try Self.updateSource(db, id) { source in
                guard source.folderId != folderId else { return }
                source.folderId = folderId
                source.position = nil
            }
        }
    }

    /// Запоминает, где остановились, и сколько прочитано. Время изменения не трогает:
    /// чтение не правка, а время последнего открытия обновляет само.
    public func saveReadingPosition(_ id: UUID, locator: SourceLocator, progress: Double) async throws {
        try await writer.write { db in
            guard var source = try Source.fetchOne(db, key: id) else { throw StorageError.sourceNotFound }
            source.locator = locator
            source.progress = min(max(progress, 0), 1)
            source.lastOpenedAt = Date()
            try source.update(db)
        }
    }

    /// Ставит место чтения, не трогая, сколько прочитано: книга откроется на этом месте,
    /// например по ссылке на место из заметки.
    public func setReadingLocator(_ id: UUID, locator: SourceLocator) async throws {
        try await writer.write { db in
            guard var source = try Source.fetchOne(db, key: id) else { throw StorageError.sourceNotFound }
            source.locator = locator
            try source.update(db)
        }
    }

    /// Страница заметок к источнику. Если её ещё нет, создаётся: в библиотеке её не видно,
    /// она открывается рядом с книгой.
    public func notesPage(for sourceId: UUID) async throws -> Page {
        try await writer.write { db in
            if let page = try Page
                .filter(Column("sourceId") == sourceId && Column("parentId") == nil && Column("deletedAt") == nil)
                .order(Column("createdAt"))
                .fetchOne(db) {
                return page
            }
            guard let source = try Source.fetchOne(db, key: sourceId) else { throw StorageError.sourceNotFound }
            var page = try Self.insertPage(db, title: source.displayTitle, parentId: nil, inInbox: false, bodyLines: [])
            page.sourceId = sourceId
            page.icon = "📖"
            try page.update(db)
            return page
        }
    }

    // MARK: Выделения

    @discardableResult
    public func addHighlight(_ highlight: Highlight) async throws -> Highlight {
        try await writer.write { db in
            try highlight.insert(db)
            return highlight
        }
    }

    public func highlight(_ id: UUID) async throws -> Highlight? {
        try await reader.read { db in try Highlight.fetchOne(db, key: id) }
    }

    public func setHighlightColor(_ id: UUID, color: HighlightColor) async throws {
        try await writer.write { db in
            try Self.updateHighlight(db, id) { $0.color = color }
        }
    }

    public func setHighlightNote(_ id: UUID, note: String?) async throws {
        try await writer.write { db in
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.updateHighlight(db, id) { $0.note = trimmed?.isEmpty == false ? trimmed : nil }
        }
    }

    /// Удаляет выделение. Выписки из него остаются на страницах, но уже не открывают книгу.
    public func deleteHighlight(_ id: UUID) async throws {
        _ = try await writer.write { db in
            try Highlight.deleteOne(db, key: id)
        }
    }

    // MARK: Корзина

    /// Переносит источник в корзину вместе с его заметками.
    public func trashSource(_ id: UUID) async throws {
        try await writer.write { db in
            try Self.trashSources(db, [id], at: Date())
        }
    }

    /// Возвращает источник из корзины вместе с заметками, удалёнными вместе с ним.
    /// Если папка всё ещё в корзине, источник поднимается в корень библиотеки.
    public func restoreSource(_ id: UUID) async throws {
        try await writer.write { db in
            guard let source = try Source.fetchOne(db, key: id) else { throw StorageError.sourceNotFound }
            guard source.isTrashed else { return }
            if let folderId = source.folderId,
               try Folder.fetchOne(db, key: folderId)?.isTrashed ?? true {
                try Self.updateSource(db, id) { source in
                    source.folderId = nil
                    source.position = nil
                }
            }
            try Self.restoreSources(db, [id])
        }
    }

    // MARK: Помощники

    static func updateSource(_ db: Database, _ id: UUID, _ change: (inout Source) -> Void) throws {
        guard var source = try Source.fetchOne(db, key: id) else { throw StorageError.sourceNotFound }
        let original = source
        change(&source)
        guard source != original else { return }
        source.updatedAt = Date()
        try source.update(db)
    }

    static func updateHighlight(_ db: Database, _ id: UUID, _ change: (inout Highlight) -> Void) throws {
        guard var highlight = try Highlight.fetchOne(db, key: id) else { throw StorageError.highlightNotFound }
        change(&highlight)
        highlight.updatedAt = Date()
        try highlight.update(db)
    }

    /// Страницы заметок источников вместе с подстраницами.
    static func notePageIds(_ db: Database, sources: [UUID]) throws -> [UUID] {
        guard !sources.isEmpty else { return [] }
        let roots = try Page
            .filter(sources.contains(Column("sourceId")) && Column("parentId") == nil)
            .fetchAll(db)
            .map(\.id)
        return try roots.flatMap { try subtreeIds(db, root: $0) }
    }

    static func trashSources(_ db: Database, _ ids: [UUID], at now: Date) throws {
        let alive = try Source.filter(keys: ids).filter(Column("deletedAt") == nil).fetchAll(db).map(\.id)
        guard !alive.isEmpty else { return }
        try Source.filter(keys: alive).updateAll(db, [
            Column("deletedAt").set(to: now),
            Column("updatedAt").set(to: now),
        ])
        let pageIds = try Page.filter(keys: try notePageIds(db, sources: alive))
            .filter(Column("deletedAt") == nil)
            .fetchAll(db)
            .map(\.id)
        try Page.filter(keys: pageIds).updateAll(db, [
            Column("deletedAt").set(to: now),
            Column("updatedAt").set(to: now),
        ])
        for pageId in pageIds {
            try reindex(db, pageId: pageId)
        }
    }

    /// Возвращает источники и заметки, которые удалили не раньше самих источников.
    static func restoreSources(_ db: Database, _ ids: [UUID]) throws {
        let now = Date()
        for source in try Source.filter(keys: ids).fetchAll(db) {
            guard let trashedAt = source.deletedAt else { continue }
            try Source.filter(key: source.id).updateAll(db, [
                Column("deletedAt").set(to: nil),
                Column("updatedAt").set(to: now),
            ])
            let pageIds = try Page.filter(keys: try notePageIds(db, sources: [source.id]))
                .filter(Column("deletedAt") >= trashedAt)
                .fetchAll(db)
                .map(\.id)
            try Page.filter(keys: pageIds).updateAll(db, [
                Column("deletedAt").set(to: nil),
                Column("updatedAt").set(to: now),
            ])
            for pageId in pageIds {
                try reindex(db, pageId: pageId)
            }
        }
    }
}
