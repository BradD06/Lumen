import Foundation
import GRDB
import LumenCore

/// Локальная база приложения. Всё хранится на устройстве (local-first), синхронизация появится позже.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    /// Файлы, которые блоки и обложки показывают по имени: картинки, книги и документы.
    public let attachments: AttachmentStore

    public var reader: any DatabaseReader { writer }

    public init(_ writer: any DatabaseWriter, attachments: AttachmentStore = .temporary()) throws {
        self.writer = writer
        self.attachments = attachments
        try Self.migrator.migrate(writer)
    }

    /// База в `Application Support/Lumen/lumen.sqlite`, вложения рядом в `Attachments`.
    public static func makeDefault() throws -> AppDatabase {
        let fileManager = FileManager.default
        let folder = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Lumen", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return try onDisk(
            at: folder.appendingPathComponent("lumen.sqlite"),
            attachments: AttachmentStore(folder: folder.appendingPathComponent("Attachments", isDirectory: true))
        )
    }

    public static func onDisk(at url: URL, attachments: AttachmentStore = .temporary()) throws -> AppDatabase {
        try AppDatabase(DatabasePool(path: url.path, configuration: configuration), attachments: attachments)
    }

    /// База в памяти для тестов и превью.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return configuration
    }
}

// MARK: - Схема

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1: pages, blocks, search") { db in
            try db.create(table: "page") { t in
                t.primaryKey("id", .blob)
                t.column("parentId", .blob).references("page", onDelete: .cascade).indexed()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("icon", .text)
                t.column("sourceId", .blob)
                t.column("inInbox", .boolean).notNull().defaults(to: false)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("sortKey", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }

            try db.create(table: "block") { t in
                t.primaryKey("id", .blob)
                t.column("pageId", .blob).notNull().references("page", onDelete: .cascade).indexed()
                t.column("parentBlockId", .blob).references("block", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("content", .text).notNull()
                t.column("sortKey", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Полнотекстовый индекс по названию и тексту страниц.
            // pageId хранится строкой, индекс обновляется вручную в репозиториях.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE pageSearch USING fts5(
                    pageId UNINDEXED,
                    title,
                    body,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """)
        }

        migrator.registerMigration("v2: covers, links") { db in
            try db.alter(table: "page") { t in
                t.add(column: "cover", .text)
            }

            // Индекс ссылок между страницами для обратных ссылок. Заполняется в `saveBlock`.
            try db.create(table: "link") { t in
                t.column("sourceBlockId", .blob).notNull().references("block", onDelete: .cascade)
                t.column("sourcePageId", .blob).notNull().references("page", onDelete: .cascade).indexed()
                t.column("targetPageId", .blob).notNull().references("page", onDelete: .cascade).indexed()
                t.primaryKey(["sourceBlockId", "targetPageId"])
            }
        }

        migrator.registerMigration("v3: page background") { db in
            try db.alter(table: "page") { t in
                t.add(column: "background", .text)
            }
        }

        migrator.registerMigration("v4: folders, library canvas") { db in
            try db.create(table: "folder") { t in
                t.primaryKey("id", .blob)
                t.column("parentId", .blob).references("folder", onDelete: .cascade).indexed()
                t.column("name", .text).notNull().defaults(to: "")
                t.column("color", .integer).notNull().defaults(to: 0)
                t.column("canvasX", .double)
                t.column("canvasY", .double)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }

            // Страница остаётся без папки, если папку удалили навсегда: она просто появится в корне библиотеки.
            try db.alter(table: "page") { t in
                t.add(column: "folderId", .blob).references("folder", onDelete: .setNull)
                t.add(column: "canvasX", .double)
                t.add(column: "canvasY", .double)
            }
            try db.create(index: "page_on_folderId", on: "page", columns: ["folderId"])
        }

        migrator.registerMigration("v5: sources, highlights") { db in
            try db.create(table: "source") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("author", .text)
                t.column("format", .text).notNull()
                t.column("file", .text).notNull()
                t.column("originalName", .text).notNull()
                t.column("cover", .text)
                t.column("folderId", .blob).references("folder", onDelete: .setNull).indexed()
                t.column("canvasX", .double)
                t.column("canvasY", .double)
                t.column("locator", .text)
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("lastOpenedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }

            try db.create(table: "highlight") { t in
                t.primaryKey("id", .blob)
                t.column("sourceId", .blob).notNull().references("source", onDelete: .cascade).indexed()
                t.column("locator", .text).notNull()
                t.column("text", .text).notNull()
                t.column("note", .text)
                t.column("color", .text).notNull()
                t.column("label", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Страница заметок источника. Колонка sourceId была с первой схемы, индекса не было.
            try db.create(index: "page_on_sourceId", on: "page", columns: ["sourceId"])
        }

        return migrator
    }
}

// MARK: - Записи GRDB

extension Page: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "page"
}

extension Folder: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "folder"
}

extension Block: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "block"
}

extension Source: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "source"
}

extension Highlight: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "highlight"
}
