import Foundation
import GRDB
import LumenCore

extension AppDatabase {
    // MARK: Папки

    @discardableResult
    public func createFolder(
        name: String = "",
        parentId: UUID? = nil,
        color: Int = 0,
        position: LibraryPoint? = nil
    ) async throws -> Folder {
        try await writer.write { db in
            let folder = Folder(parentId: parentId, name: name, color: Self.clampedColor(color), position: position)
            try folder.insert(db)
            return folder
        }
    }

    public func folder(_ id: UUID) async throws -> Folder? {
        try await reader.read { db in try Folder.fetchOne(db, key: id) }
    }

    public func renameFolder(_ id: UUID, name: String) async throws {
        try await writer.write { db in
            try Self.updateFolder(db, id) { $0.name = name }
        }
    }

    public func setFolderColor(_ id: UUID, color: Int) async throws {
        try await writer.write { db in
            try Self.updateFolder(db, id) { $0.color = Self.clampedColor(color) }
        }
    }

    /// Кладёт папку в другую папку (`nil` = корень библиотеки). На новом месте она встаёт в свободную ячейку.
    public func moveFolder(_ id: UUID, toParent parentId: UUID?) async throws {
        try await writer.write { db in
            if let parentId, try Self.folderSubtreeIds(db, root: id).contains(parentId) {
                throw StorageError.invalidMove
            }
            try Self.updateFolder(db, id) { folder in
                guard folder.parentId != parentId else { return }
                folder.parentId = parentId
                folder.position = nil
            }
        }
    }

    /// Кладёт страницу в папку (`nil` = корень библиотеки). Подстраница или заметка из «Входящих»
    /// становится страницей верхнего уровня.
    public func movePage(_ id: UUID, toFolder folderId: UUID?) async throws {
        try await writer.write { db in
            try Self.updatePage(db, id) { page in
                guard page.folderId != folderId || page.parentId != nil || page.inInbox else { return }
                page.parentId = nil
                page.inInbox = false
                page.folderId = folderId
                page.position = nil
            }
        }
    }

    /// Запоминает, где предмет лежит на холсте. `nil` возвращает его в автоматическую раскладку.
    public func setPosition(_ item: LibraryItemID, _ position: LibraryPoint?) async throws {
        try await setPositions([item: position])
    }

    /// Несколько мест за одну запись, например после выравнивания по сетке.
    public func setPositions(_ positions: [LibraryItemID: LibraryPoint?]) async throws {
        try await writer.write { db in
            // Перестановка на холсте не правка содержимого: время изменения не трогаем,
            // иначе страница всплывала бы в «Недавних».
            for (item, position) in positions {
                switch item {
                case .folder(let id):
                    guard var folder = try Folder.fetchOne(db, key: id) else { throw StorageError.folderNotFound }
                    folder.position = position
                    try folder.update(db)
                case .page(let id):
                    guard var page = try Page.fetchOne(db, key: id) else { throw StorageError.pageNotFound }
                    page.position = position
                    try page.update(db)
                case .source(let id):
                    guard var source = try Source.fetchOne(db, key: id) else { throw StorageError.sourceNotFound }
                    source.position = position
                    try source.update(db)
                }
            }
        }
    }

    // MARK: Корзина

    /// Переносит папку в корзину вместе с вложенными папками и всеми страницами в них.
    public func trashFolder(_ id: UUID) async throws {
        try await writer.write { db in
            let folderIds = try Self.folderSubtreeIds(db, root: id)
            let now = Date()
            try Folder.filter(keys: folderIds).filter(Column("deletedAt") == nil).updateAll(db, [
                Column("deletedAt").set(to: now),
                Column("updatedAt").set(to: now),
            ])
            let pageIds = try Self.pageIdsInFolders(db, folderIds)
                .filter { try Page.fetchOne(db, key: $0)?.isTrashed == false }
            try Page.filter(keys: pageIds).updateAll(db, [
                Column("deletedAt").set(to: now),
                Column("updatedAt").set(to: now),
            ])
            for pageId in pageIds {
                try Self.reindex(db, pageId: pageId)
            }
            let sourceIds = try Source.filter(folderIds.contains(Column("folderId"))).fetchAll(db).map(\.id)
            try Self.trashSources(db, sourceIds, at: now)
        }
    }

    /// Возвращает папку из корзины со всем, что удалили вместе с ней. Если родитель всё ещё
    /// в корзине, папка поднимается в корень библиотеки.
    public func restoreFolder(_ id: UUID) async throws {
        try await writer.write { db in
            guard let folder = try Folder.fetchOne(db, key: id) else { throw StorageError.folderNotFound }
            guard let trashedAt = folder.deletedAt else { return }
            if let parentId = folder.parentId,
               try Folder.fetchOne(db, key: parentId)?.isTrashed ?? true {
                try Self.updateFolder(db, id) { folder in
                    folder.parentId = nil
                    folder.position = nil
                }
            }
            // То, что удалили раньше папки отдельно, остаётся в корзине.
            let folderIds = try Self.folderSubtreeIds(db, root: id)
            let restoredFolders = Folder.filter(keys: folderIds).filter(Column("deletedAt") >= trashedAt)
            let restoredFolderIds = try restoredFolders.fetchAll(db).map(\.id)
            let pageIds = try Self.pageIdsInFolders(db, restoredFolderIds)
            let restoredPages = try Page.filter(keys: pageIds).filter(Column("deletedAt") >= trashedAt).fetchAll(db).map(\.id)
            let now = Date()
            try restoredFolders.updateAll(db, [
                Column("deletedAt").set(to: nil),
                Column("updatedAt").set(to: now),
            ])
            try Page.filter(keys: restoredPages).updateAll(db, [
                Column("deletedAt").set(to: nil),
                Column("updatedAt").set(to: now),
            ])
            for pageId in restoredPages {
                try Self.reindex(db, pageId: pageId)
            }
            let restoredSources = try Source
                .filter(restoredFolderIds.contains(Column("folderId")))
                .filter(Column("deletedAt") >= trashedAt)
                .fetchAll(db)
                .map(\.id)
            try Self.restoreSources(db, restoredSources)
        }
    }

    // MARK: Помощники

    static func clampedColor(_ color: Int) -> Int {
        min(max(color, 0), Folder.colorCount - 1)
    }

    static func updateFolder(_ db: Database, _ id: UUID, _ change: (inout Folder) -> Void) throws {
        guard var folder = try Folder.fetchOne(db, key: id) else { throw StorageError.folderNotFound }
        let original = folder
        change(&folder)
        guard folder != original else { return }
        folder.updatedAt = Date()
        try folder.update(db)
    }

    /// Идентификаторы папки и всех вложенных папок.
    static func folderSubtreeIds(_ db: Database, root: UUID) throws -> [UUID] {
        try UUID.fetchAll(db, sql: """
            WITH RECURSIVE subtree(id) AS (
                SELECT ?
                UNION ALL
                SELECT folder.id FROM folder JOIN subtree ON folder.parentId = subtree.id
            )
            SELECT id FROM subtree
            """, arguments: [root])
    }

    /// Страницы, которые лежат в этих папках, вместе со всеми их подстраницами.
    static func pageIdsInFolders(_ db: Database, _ folderIds: [UUID]) throws -> [UUID] {
        guard !folderIds.isEmpty else { return [] }
        let roots = try Page.filter(folderIds.contains(Column("folderId"))).fetchAll(db).map(\.id)
        var ids: [UUID] = []
        for root in roots {
            ids += try subtreeIds(db, root: root)
        }
        return ids
    }
}
