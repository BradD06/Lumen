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

    /// Книги из библиотеки (не из корзины), добавленные из файла с таким именем, новые первыми.
    /// По ним видно, что ту же книгу открывают ещё раз, например снова из Telegram.
    public func sources(originalName: String) async throws -> [Source] {
        try await reader.read { db in
            try Source
                .filter(Column("originalName") == originalName && Column("deletedAt") == nil)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
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

    /// Страница заметок к источнику, если её уже завели. Сама ничего не создаёт:
    /// книгу можно открыть и читать, не оставляя в библиотеке пустых заметок.
    public func bookNotesPage(for sourceId: UUID) async throws -> Page? {
        try await reader.read { db in try Self.bookNotesPage(db, sourceId: sourceId) }
    }

    /// Страница заметок к источнику. Если её ещё нет, создаётся там же, где лежит книга:
    /// в её папке (или в корне библиотеки), на холсте рядом с книгой.
    public func notesPage(for sourceId: UUID) async throws -> Page {
        try await writer.write { db in
            if let page = try Self.bookNotesPage(db, sourceId: sourceId) { return page }
            guard let source = try Source.fetchOne(db, key: sourceId) else { throw StorageError.sourceNotFound }
            var page = try Self.insertPage(
                db, title: source.displayTitle, parentId: nil, inInbox: false,
                folderId: source.folderId, position: try Self.spotBeside(db, source: source), bodyLines: []
            )
            page.sourceId = sourceId
            page.icon = "📖"
            try page.update(db)
            return page
        }
    }

    /// Новая пустая заметка, открытая из книги: в папке книги, на холсте рядом с ней.
    @discardableResult
    public func createPage(besideSource sourceId: UUID) async throws -> Page {
        try await writer.write { db in
            guard let source = try Source.fetchOne(db, key: sourceId) else { throw StorageError.sourceNotFound }
            return try Self.insertPage(
                db, title: "", parentId: nil, inInbox: false,
                folderId: source.folderId, position: try Self.spotBeside(db, source: source), bodyLines: []
            )
        }
    }

    static func bookNotesPage(_ db: Database, sourceId: UUID) throws -> Page? {
        try Page
            .filter(Column("sourceId") == sourceId && Column("parentId") == nil && Column("deletedAt") == nil)
            .order(Column("createdAt"))
            .fetchOne(db)
    }

    static func spotBeside(_ db: Database, source: Source) throws -> LibraryPoint? {
        try spotBeside(db, sourceId: source.id, folderId: source.folderId, anchor: source.position)
    }

    /// Свободное место на холсте рядом с книгой. Если у книги своего места нет (её раскладывает
    /// библиотека), `nil`: заметка тоже встанет в свободную ячейку той же папки.
    /// Читает координаты простым SQL: этим пользуется и миграция, которой записи GRDB не подходят.
    static func spotBeside(_ db: Database, sourceId: UUID, folderId: UUID?, anchor: LibraryPoint?) throws -> LibraryPoint? {
        guard let anchor else { return nil }
        let rows = try Row.fetchAll(db, sql: """
            SELECT canvasX, canvasY FROM folder WHERE parentId IS ? AND deletedAt IS NULL
            UNION ALL
            SELECT canvasX, canvasY FROM page
                WHERE folderId IS ? AND parentId IS NULL AND inInbox = 0 AND deletedAt IS NULL
            UNION ALL
            SELECT canvasX, canvasY FROM source WHERE folderId IS ? AND deletedAt IS NULL AND id != ?
            """, arguments: [folderId, folderId, folderId, sourceId])
        let placed = rows.compactMap { row in
            LibraryPoint(x: row["canvasX"] as Double?, y: row["canvasY"] as Double?)
        }
        return LibraryLayout.spot(beside: anchor, avoiding: placed)
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
                // Заметки к книге лежали в той же папке: поднимаются в корень вместе с книгой.
                try Page
                    .filter(Column("sourceId") == id && Column("parentId") == nil && Column("folderId") == folderId)
                    .updateAll(db, [Column("folderId").set(to: nil), Column("canvasX").set(to: nil), Column("canvasY").set(to: nil)])
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
