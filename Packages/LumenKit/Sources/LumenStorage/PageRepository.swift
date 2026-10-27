import Foundation
import GRDB
import LumenCore

public enum StorageError: Error, Equatable {
    case pageNotFound
    /// Попытка переместить страницу внутрь самой себя.
    case invalidMove
}

extension AppDatabase {
    // MARK: Создание

    /// Новая пустая страница с одним пустым абзацем.
    @discardableResult
    public func createPage(title: String = "", parentId: UUID? = nil, inInbox: Bool = false) async throws -> Page {
        try await writer.write { db in
            try Self.insertPage(db, title: title, parentId: parentId, inInbox: inInbox, bodyLines: [])
        }
    }

    /// Быстрая заметка во «Входящие»: первая строка становится названием, остальные строки абзацами.
    @discardableResult
    public func createQuickNote(_ text: String) async throws -> Page {
        var lines = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
        let title = lines.isEmpty ? "" : lines.removeFirst()
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeFirst()
        }
        return try await writer.write { [lines] db in
            try Self.insertPage(db, title: title, parentId: nil, inInbox: true, bodyLines: lines)
        }
    }

    static func insertPage(
        _ db: Database,
        title: String,
        parentId: UUID?,
        inInbox: Bool,
        bodyLines: [String]
    ) throws -> Page {
        let lastKey = try String.fetchOne(
            db,
            sql: "SELECT MAX(sortKey) FROM page WHERE parentId IS ? AND inInbox = ?",
            arguments: [parentId, inInbox]
        )
        let now = Date()
        let page = Page(
            parentId: parentId,
            title: title,
            inInbox: inInbox && parentId == nil,
            sortKey: SortKey.between(lastKey, nil),
            createdAt: now
        )
        try page.insert(db)

        let lines = bodyLines.isEmpty ? [""] : bodyLines
        for (line, key) in zip(lines, SortKey.sequence(count: lines.count)) {
            try Block(pageId: page.id, content: BlockContent(text: line), sortKey: key, createdAt: now).insert(db)
        }
        try reindex(db, pageId: page.id)
        return page
    }

    // MARK: Чтение

    public func page(_ id: UUID) async throws -> Page? {
        try await reader.read { db in try Page.fetchOne(db, key: id) }
    }

    // MARK: Изменение

    public func renamePage(_ id: UUID, title: String) async throws {
        try await writer.write { db in
            try Self.updatePage(db, id) { $0.title = title }
            try Self.reindex(db, pageId: id)
        }
    }

    public func setIcon(_ id: UUID, icon: String?) async throws {
        try await writer.write { db in
            try Self.updatePage(db, id) { $0.icon = icon }
        }
    }

    public func setFavorite(_ id: UUID, _ isFavorite: Bool) async throws {
        try await writer.write { db in
            try Self.updatePage(db, id) { $0.isFavorite = isFavorite }
        }
    }

    /// Перемещает страницу под другого родителя (`nil` = верхний уровень) и убирает её из «Входящих».
    public func movePage(_ id: UUID, toParent parentId: UUID?) async throws {
        try await writer.write { db in
            if let parentId {
                let subtree = try Self.subtreeIds(db, root: id)
                if subtree.contains(parentId) { throw StorageError.invalidMove }
            }
            let lastKey = try String.fetchOne(
                db,
                sql: "SELECT MAX(sortKey) FROM page WHERE parentId IS ? AND inInbox = 0 AND id != ?",
                arguments: [parentId, id]
            )
            try Self.updatePage(db, id) { page in
                page.parentId = parentId
                page.inInbox = false
                page.sortKey = SortKey.between(lastKey, nil)
            }
        }
    }

    // MARK: Корзина

    /// Переносит страницу и все вложенные страницы в корзину.
    public func trashPage(_ id: UUID) async throws {
        try await writer.write { db in
            let ids = try Self.subtreeIds(db, root: id)
            let now = Date()
            try Page.filter(keys: ids).updateAll(db, [
                Column("deletedAt").set(to: now),
                Column("updatedAt").set(to: now),
            ])
            for pageId in ids {
                try Self.reindex(db, pageId: pageId)
            }
        }
    }

    /// Возвращает страницу из корзины вместе с вложенными. Если родитель всё ещё в корзине,
    /// страница поднимается на верхний уровень.
    public func restorePage(_ id: UUID) async throws {
        try await writer.write { db in
            guard let page = try Page.fetchOne(db, key: id) else { throw StorageError.pageNotFound }
            if let parentId = page.parentId,
               try Page.fetchOne(db, key: parentId)?.isTrashed ?? true {
                try Self.updatePage(db, id) { $0.parentId = nil }
            }
            let ids = try Self.subtreeIds(db, root: id)
            try Page.filter(keys: ids).updateAll(db, [
                Column("deletedAt").set(to: nil),
                Column("updatedAt").set(to: Date()),
            ])
            for pageId in ids {
                try Self.reindex(db, pageId: pageId)
            }
        }
    }

    /// Удаляет из корзины всё навсегда. Блоки удаляются каскадом.
    public func emptyTrash() async throws {
        _ = try await writer.write { db in
            try Page.filter(Column("deletedAt") != nil).deleteAll(db)
        }
    }

    // MARK: Помощники

    static func updatePage(_ db: Database, _ id: UUID, _ change: (inout Page) -> Void) throws {
        guard var page = try Page.fetchOne(db, key: id) else { throw StorageError.pageNotFound }
        change(&page)
        page.updatedAt = Date()
        try page.update(db)
    }

    /// Идентификаторы страницы и всех её потомков.
    static func subtreeIds(_ db: Database, root: UUID) throws -> [UUID] {
        try UUID.fetchAll(db, sql: """
            WITH RECURSIVE subtree(id) AS (
                SELECT ?
                UNION ALL
                SELECT page.id FROM page JOIN subtree ON page.parentId = subtree.id
            )
            SELECT id FROM subtree
            """, arguments: [root])
    }

    /// Обновляет строку страницы в полнотекстовом индексе. Страницы в корзине из индекса убираются.
    static func reindex(_ db: Database, pageId: UUID) throws {
        try db.execute(sql: "DELETE FROM pageSearch WHERE pageId = ?", arguments: [pageId.uuidString])
        guard let page = try Page.fetchOne(db, key: pageId), !page.isTrashed else { return }
        let body = try Block
            .filter(Column("pageId") == pageId)
            .order(Column("sortKey"))
            .fetchAll(db)
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        try db.execute(
            sql: "INSERT INTO pageSearch(pageId, title, body) VALUES (?, ?, ?)",
            arguments: [pageId.uuidString, page.title, body]
        )
    }
}
