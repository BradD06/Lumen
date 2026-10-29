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
        let isStillQuoted = try Block
            .filter(Column("type") == BlockType.excerpt.rawValue)
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
