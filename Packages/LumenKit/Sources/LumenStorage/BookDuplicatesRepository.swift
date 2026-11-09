import Foundation
import GRDB
import LumenCore

extension AppDatabase {
    /// Сливает повторы одной книги (`BookDuplicates`): выделения, заметки, время чтения и ссылки
    /// в заметках переезжают к оригиналу, место чтения берётся у той записи, которую читали позже,
    /// а повтор уходит в корзину. Возвращает, сколько повторов убрано.
    @discardableResult
    public func mergeDuplicateBooks(now: Date = Date()) async throws -> Int {
        let attachments = attachments
        return try await writer.write { db in
            let books = try Source.filter(Column("deletedAt") == nil).fetchAll(db)
            let pairs = BookDuplicates.pairs(books) { attachments.fileSize($0.file) }
            for pair in pairs {
                try Self.mergeBook(db, pair.duplicate, into: pair.keeper, now: now)
            }
            return pairs.count
        }
    }

    static func mergeBook(_ db: Database, _ duplicateId: UUID, into keeperId: UUID, now: Date) throws {
        guard var keeper = try Source.fetchOne(db, key: keeperId),
              var duplicate = try Source.fetchOne(db, key: duplicateId) else { return }

        try db.execute(
            sql: "UPDATE highlight SET sourceId = ?, updatedAt = ? WHERE sourceId = ?",
            arguments: [keeperId, now, duplicateId]
        )
        try db.execute(
            sql: "UPDATE readingSession SET sourceId = ? WHERE sourceId = ?",
            arguments: [keeperId, duplicateId]
        )
        try db.execute(
            sql: "UPDATE page SET sourceId = ?, updatedAt = ? WHERE sourceId = ?",
            arguments: [keeperId, now, duplicateId]
        )

        // Ссылки lumen://source/<id> и выписки в заметках ведут теперь к оригиналу.
        let upper = duplicateId.uuidString
        let lower = upper.lowercased()
        let blocks = try Block
            .filter(sql: "instr(CAST(content AS TEXT), ?) > 0 OR instr(CAST(content AS TEXT), ?) > 0", arguments: [upper, lower])
            .fetchAll(db)
        for var block in blocks {
            guard let text = String(data: try JSONEncoder().encode(block.content), encoding: .utf8) else { continue }
            let replaced = text
                .replacingOccurrences(of: upper, with: keeperId.uuidString)
                .replacingOccurrences(of: lower, with: keeperId.uuidString.lowercased())
            guard replaced != text else { continue }
            block.content = try JSONDecoder().decode(BlockContent.self, from: Data(replaced.utf8))
            block.updatedAt = now
            try block.update(db)
        }

        var keeperChanged = false
        if (duplicate.lastOpenedAt ?? .distantPast) > (keeper.lastOpenedAt ?? .distantPast) {
            keeper.locator = duplicate.locator
            keeper.progress = duplicate.progress
            keeper.lastOpenedAt = duplicate.lastOpenedAt
            keeperChanged = true
        }
        if keeper.author?.isEmpty != false, let author = duplicate.author, !author.isEmpty {
            keeper.author = author
            keeperChanged = true
        }
        if keeper.cover == nil, let cover = duplicate.cover {
            // Обложка переходит оригиналу: при очистке корзины её файл не удалится вместе с повтором.
            keeper.cover = cover
            duplicate.cover = nil
            duplicate.updatedAt = now
            try duplicate.update(db)
            keeperChanged = true
        }
        if keeperChanged {
            keeper.updatedAt = now
            try keeper.update(db)
        }
        try trashSources(db, [duplicateId], at: now)
    }
}
