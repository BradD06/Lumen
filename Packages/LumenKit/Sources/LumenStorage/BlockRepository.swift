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
            try db.execute(sql: "UPDATE page SET updatedAt = ? WHERE id = ?", arguments: [now, block.pageId])
            try Self.reindex(db, pageId: block.pageId)
        }
    }

    public func deleteBlock(_ id: UUID) async throws {
        try await writer.write { db in
            guard let block = try Block.fetchOne(db, key: id) else { return }
            try block.delete(db)
            try db.execute(sql: "UPDATE page SET updatedAt = ? WHERE id = ?", arguments: [Date(), block.pageId])
            try Self.reindex(db, pageId: block.pageId)
        }
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
