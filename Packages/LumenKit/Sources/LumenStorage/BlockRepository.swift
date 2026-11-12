import Foundation
import GRDB
import LumenCore

extension AppDatabase {
    /// Блоки верхнего уровня страницы по порядку.
    public func blocks(of pageId: UUID) async throws -> [Block] {
        try await reader.read { db in
            try Block
                .filter(Column("pageId") == pageId)
                .order(Column("sortKey"))
                .fetchAll(db)
        }
    }

    /// Вставляет или обновляет блок. Ключ порядка редактор считает сам через `SortKey`.
    public func saveBlock(_ block: Block) async throws {
        try await writer.write { db in
            var block = block
            let now = Date()
            block.updatedAt = now
            try block.save(db)
            try Self.updateLinks(db, block: block)
            try Self.reviveHighlight(db, for: block)
            try db.execute(sql: "UPDATE page SET updatedAt = ? WHERE id = ?", arguments: [now, block.pageId])
            try Self.reindex(db, pageId: block.pageId)
        }
    }

    /// Правки открытой страницы одной записью: новое название, изменённые и удалённые блоки.
    /// Одна транзакция вместо записи на каждый блок: поиск пересчитывается один раз, и экраны,
    /// которые следят за базой, узнают о правке один раз. Удаления идут после сохранений,
    /// чтобы каскад не забрал блоки, которые только что перенесли к другому родителю.
    public func savePageEdits(pageId: UUID, title: String?, saving blocks: [Block], deleting ids: [UUID]) async throws {
        try await writer.write { db in
            let now = Date()
            var touched: Set<UUID> = [pageId]
            if let title {
                try Self.updatePage(db, pageId) { $0.title = title }
            }
            for var block in blocks {
                block.updatedAt = now
                try block.save(db)
                try Self.updateLinks(db, block: block)
                try Self.reviveHighlight(db, for: block)
                touched.insert(block.pageId)
            }
            for id in ids {
                guard let block = try Block.fetchOne(db, key: id) else { continue }
                try block.delete(db)
                try Self.releaseHighlight(db, for: block)
                touched.insert(block.pageId)
            }
            for id in touched {
                if !blocks.isEmpty || !ids.isEmpty {
                    try db.execute(sql: "UPDATE page SET updatedAt = ? WHERE id = ?", arguments: [now, id])
                }
                try Self.reindex(db, pageId: id)
            }
        }
    }

    public func deleteBlock(_ id: UUID) async throws {
        try await writer.write { db in
            guard let block = try Block.fetchOne(db, key: id) else { return }
            try block.delete(db)
            try Self.releaseHighlight(db, for: block)
            try db.execute(sql: "UPDATE page SET updatedAt = ? WHERE id = ?", arguments: [Date(), block.pageId])
            try Self.reindex(db, pageId: block.pageId)
        }
    }

    /// Выписку вернули, например отменой удаления: её выделение снова видно в книге.
    static func reviveHighlight(_ db: Database, for block: Block) throws {
        guard block.type == .excerpt, let id = block.content.excerpt?.highlightId else { return }
        try db.execute(
            sql: "UPDATE highlight SET deletedAt = NULL WHERE id = ? AND deletedAt IS NOT NULL",
            arguments: [id]
        )
    }

    /// Удалили последнюю выписку из выделения: выделение пропадает из книги и из списка выделений.
    static func releaseHighlight(_ db: Database, for block: Block) throws {
        guard block.type == .excerpt, let id = block.content.excerpt?.highlightId else { return }
        // Сначала дешёвый отбор по тексту: разбирать JSON всех выписок базы долго.
        let isStillQuoted = try Block
            .filter(Column("type") == BlockType.excerpt.rawValue)
            .filter(Column("content").like("%\(id.uuidString)%"))
            .fetchAll(db)
            .contains { $0.content.excerpt?.highlightId == id }
        guard !isStillQuoted else { return }
        try db.execute(sql: "UPDATE highlight SET deletedAt = ? WHERE id = ?", arguments: [Date(), id])
    }

    /// Пересобирает ссылки блока на другие страницы. Строки ссылок блока удаляются вместе с ним каскадом.
    static func updateLinks(_ db: Database, block: Block) throws {
        try db.execute(sql: "DELETE FROM link WHERE sourceBlockId = ?", arguments: [block.id])
        guard block.type == .page, let target = block.content.pageId, target != block.pageId,
              try Page.exists(db, key: target) else { return }
        try db.execute(
            sql: "INSERT OR IGNORE INTO link(sourceBlockId, sourcePageId, targetPageId) VALUES (?, ?, ?)",
            arguments: [block.id, block.pageId, target]
        )
    }
}
