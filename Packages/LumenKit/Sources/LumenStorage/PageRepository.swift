import Foundation
import GRDB
import LumenCore

public enum StorageError: Error, Equatable {
    case pageNotFound
    case folderNotFound
    case sourceNotFound
    case highlightNotFound
    case dataTableNotFound
    /// Попытка переместить страницу или папку внутрь самой себя.
    case invalidMove
}

extension AppDatabase {
    // MARK: Создание

    /// Новая пустая страница с одним пустым абзацем.
    /// `folderId` и `position` кладут страницу в папку библиотеки на нужное место холста.
    @discardableResult
    public func createPage(
        title: String = "",
        parentId: UUID? = nil,
        inInbox: Bool = false,
        folderId: UUID? = nil,
        position: LibraryPoint? = nil
    ) async throws -> Page {
        try await writer.write { db in
            try Self.insertPage(
                db, title: title, parentId: parentId, inInbox: inInbox,
                folderId: folderId, position: position, bodyLines: []
            )
        }
    }

    /// Новая рукописная заметка: один лист бумаги, на котором пишут от руки.
    /// Все листы и штрихи лежат в единственном блоке «Рисунок» этой страницы.
    @discardableResult
    public func createNotebook(
        title: String = "",
        parentId: UUID? = nil,
        inInbox: Bool = false,
        folderId: UUID? = nil,
        position: LibraryPoint? = nil,
        paper: PaperPattern = .lined,
        tone: PaperTone = .white
    ) async throws -> Page {
        try await writer.write { db in
            var page = try Self.insertPage(
                db, title: title, parentId: parentId, inInbox: inInbox,
                folderId: folderId, position: position, bodyLines: []
            )
            page.pageKind = .notebook
            page.icon = "✍️"
            try page.update(db)
            // Пустой абзац, который вставляет `insertPage`, заменяется листами.
            try Block.filter(Column("pageId") == page.id).deleteAll(db)
            try Block(
                pageId: page.id,
                type: .drawing,
                content: BlockContent(sheetCount: 1, paper: paper, paperTone: tone),
                sortKey: SortKey.between(nil, nil),
                createdAt: page.createdAt
            ).insert(db)
            try Self.reindex(db, pageId: page.id)
            return page
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
        folderId: UUID? = nil,
        position: LibraryPoint? = nil,
        bodyLines: [String]
    ) throws -> Page {
        // В папке лежат только страницы верхнего уровня, не из «Входящих».
        let inFolder = parentId == nil && !inInbox
        let lastKey = try String.fetchOne(
            db,
            sql: "SELECT MAX(sortKey) FROM page WHERE parentId IS ? AND inInbox = ?",
            arguments: [parentId, inInbox]
        )
        let now = Date()
        let page = Page(
            parentId: parentId,
            title: title,
            folderId: inFolder ? folderId : nil,
            position: inFolder ? position : nil,
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

    public func setCover(_ id: UUID, cover: PageCover?) async throws {
        try await writer.write { db in
            try Self.updatePage(db, id) { $0.pageCover = cover }
        }
    }

    public func setBackground(_ id: UUID, background: PageBackground?) async throws {
        try await writer.write { db in
            try Self.updatePage(db, id) { $0.pageBackground = background }
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
                // Строка, вынесенная из своей базы, становится обычной страницей.
                if page.parentId != parentId {
                    page.databaseId = nil
                    page.properties = nil
                }
                page.parentId = parentId
                page.inInbox = false
                page.sortKey = SortKey.between(lastKey, nil)
                // Подстраница живёт внутри родителя, а не в папке библиотеки.
                if parentId != nil {
                    page.folderId = nil
                    page.position = nil
                }
            }
        }
    }

    /// Копия страницы со всеми блоками рядом с оригиналом: в той же папке, под тем же родителем
    /// или во «Входящих». Подстраницы не копируются. Копия заметок к книге становится обычной
    /// страницей в библиотеке, чтобы у книги не появилось вторых заметок.
    @discardableResult
    public func duplicatePage(_ id: UUID) async throws -> Page {
        try await writer.write { db in
            guard let original = try Page.fetchOne(db, key: id), !original.isTrashed else {
                throw StorageError.pageNotFound
            }
            let nextKey = try String.fetchOne(
                db,
                sql: "SELECT MIN(sortKey) FROM page WHERE parentId IS ? AND inInbox = ? AND sortKey > ?",
                arguments: [original.parentId, original.inInbox, original.sortKey]
            )
            let now = Date()
            var copy = original
            copy.id = UUID()
            copy.title = original.title.isEmpty ? "" : "\(original.title) (копия)"
            copy.sourceId = nil
            copy.isFavorite = false
            copy.position = nil
            copy.sortKey = SortKey.between(original.sortKey, nextKey)
            copy.createdAt = now
            copy.updatedAt = now
            copy.deletedAt = nil
            try copy.insert(db)

            // Родительский блок вставляется раньше вложенных: на него ссылается внешний ключ.
            let blocks = try Block.filter(Column("pageId") == id).order(Column("sortKey")).fetchAll(db)
            var newIds: [UUID: UUID] = [:]
            for block in blocks { newIds[block.id] = UUID() }
            var inserted: Set<UUID> = []
            var pending = blocks
            while !pending.isEmpty {
                let ready = pending.filter { block in
                    block.parentBlockId.map { inserted.contains($0) || newIds[$0] == nil } ?? true
                }
                // Петля в дереве блоков: остальные кладём на верхний уровень, чтобы ничего не потерять.
                let batch = ready.isEmpty ? pending : ready
                for block in batch {
                    var newBlock = block
                    newBlock.id = newIds[block.id] ?? UUID()
                    newBlock.pageId = copy.id
                    newBlock.parentBlockId = ready.isEmpty ? nil : block.parentBlockId.flatMap { newIds[$0] }
                    newBlock.createdAt = now
                    newBlock.updatedAt = now
                    try newBlock.insert(db)
                    try Self.updateLinks(db, block: newBlock)
                    inserted.insert(block.id)
                }
                pending.removeAll { inserted.contains($0.id) }
            }
            try Self.reindex(db, pageId: copy.id)
            return copy
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
                // Строка без своей базы становится обычной страницей.
                try Self.updatePage(db, id) { page in
                    page.parentId = nil
                    page.databaseId = nil
                    page.properties = nil
                }
            }
            // Папка тоже могла остаться в корзине: тогда страница возвращается в корень библиотеки.
            if let folderId = page.folderId,
               try Folder.fetchOne(db, key: folderId)?.isTrashed ?? true {
                try Self.updatePage(db, id) { page in
                    page.folderId = nil
                    page.position = nil
                }
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

    /// Удаляет из корзины всё навсегда: страницы, папки, книги и их файлы.
    /// Блоки, выделения и вложенные папки удаляются каскадом.
    public func emptyTrash() async throws {
        let files = try await writer.write { db in
            let sources = try Source.filter(Column("deletedAt") != nil).fetchAll(db)
            try Source.filter(keys: sources.map(\.id)).deleteAll(db)
            try Page.filter(Column("deletedAt") != nil).deleteAll(db)
            try Folder.filter(Column("deletedAt") != nil).deleteAll(db)
            try Highlight.filter(Column("deletedAt") != nil).deleteAll(db)
            return sources.flatMap { [$0.file] + ($0.cover.map { [$0] } ?? []) }
        }
        for file in files {
            attachments.remove(file)
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
        // Только содержимое блоков: штрихи рисунков для поиска не нужны, а весят много.
        let body = try Data
            .fetchAll(db, sql: "SELECT content FROM block WHERE pageId = ? ORDER BY sortKey", arguments: [pageId])
            .compactMap { try? JSONDecoder().decode(BlockContent.self, from: $0).text }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        try db.execute(
            sql: "INSERT INTO pageSearch(pageId, title, body) VALUES (?, ?, ?)",
            arguments: [pageId.uuidString, page.title, body]
        )
    }
}
