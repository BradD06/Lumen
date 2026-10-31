import Foundation
import GRDB
import LumenCore

extension AppDatabase {
    /// Сколько дней вещь лежит в корзине, прежде чем удалиться сама.
    public static let trashRetentionDays = 30

    /// Удаляет навсегда одну вещь из корзины: папку со всем, что удалили вместе с ней,
    /// страницу с подстраницами или книгу с заметками и файлами. Живые вещи не трогает.
    public func deleteForever(_ item: LibraryItemID) async throws {
        let files = try await writer.write { db in
            try Self.deleteForever(db, item)
        }
        for file in files {
            attachments.remove(file)
        }
    }

    /// Удаляет навсегда то, что лежит в корзине дольше `trashRetentionDays` дней.
    /// Возвращает, сколько вещей удалено (верхних, как их видно в корзине).
    @discardableResult
    public func purgeTrash(now: Date = Date(), calendar: Calendar = .current) async throws -> Int {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.trashRetentionDays, to: now) else { return 0 }
        let (count, files) = try await writer.write { db in
            let trash = try TrashSnapshot.fetch(db)
            let items: [LibraryItemID] =
                trash.folders.filter { ($0.deletedAt ?? now) < cutoff }.map { .folder($0.id) }
                + trash.sources.filter { ($0.deletedAt ?? now) < cutoff }.map { .source($0.id) }
                + trash.pages.filter { ($0.deletedAt ?? now) < cutoff }.map { .page($0.id) }
            var files: [String] = []
            for item in items {
                files += try Self.deleteForever(db, item)
            }
            return (items.count, files)
        }
        for file in files {
            attachments.remove(file)
        }
        return count
    }

    /// Удаляет вещь из корзины и возвращает имена файлов во вложениях, которые больше не нужны.
    static func deleteForever(_ db: Database, _ item: LibraryItemID) throws -> [String] {
        switch item {
        case .page(let id):
            guard let page = try Page.fetchOne(db, key: id), page.isTrashed else { return [] }
            // Подстраницы удаляются каскадом.
            try Page.deleteOne(db, key: id)
            return []

        case .source(let id):
            guard let source = try Source.fetchOne(db, key: id), source.isTrashed else { return [] }
            return try deleteTrashedSources(db, [source])

        case .folder(let id):
            guard let folder = try Folder.fetchOne(db, key: id), folder.isTrashed else { return [] }
            let folderIds = try folderSubtreeIds(db, root: id)
            // Страницы и книги в этих папках удалены вместе с ними (или раньше): уходят навсегда.
            // Если что-то внутри почему-то живо, оно не теряется, а остаётся в корне библиотеки.
            let pageIds = try pageIdsInFolders(db, folderIds)
            try Page.filter(keys: pageIds).filter(Column("deletedAt") != nil).deleteAll(db)
            let sources = try Source
                .filter(folderIds.contains(Column("folderId")))
                .filter(Column("deletedAt") != nil)
                .fetchAll(db)
            let files = try deleteTrashedSources(db, sources)
            // Вложенные папки удаляются каскадом.
            try Folder.deleteOne(db, key: id)
            return files
        }
    }

    /// Книги из корзины вместе с их заметками, которые тоже в корзине. Выделения и отрезки чтения
    /// удаляются каскадом.
    private static func deleteTrashedSources(_ db: Database, _ sources: [Source]) throws -> [String] {
        guard !sources.isEmpty else { return [] }
        let ids = sources.map(\.id)
        let notes = try notePageIds(db, sources: ids)
        try Page.filter(keys: notes).filter(Column("deletedAt") != nil).deleteAll(db)
        try Source.filter(keys: ids).deleteAll(db)
        return sources.flatMap { [$0.file] + ($0.cover.map { [$0] } ?? []) }
    }
}
