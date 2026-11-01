import Foundation
import GRDB
import LumenCore

/// Локальная база приложения. Всё хранится на устройстве (local-first), а в iCloud уезжает копия, см. LumenSync.
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

    /// Папка с данными приложения: `Application Support/Lumen`.
    public static func defaultFolder() throws -> URL {
        let fileManager = FileManager.default
        let folder = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Lumen", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// База в `Application Support/Lumen/lumen.sqlite`, вложения рядом в `Attachments`.
    public static func makeDefault() throws -> AppDatabase {
        let folder = try defaultFolder()
        return try onDisk(
            at: folder.appendingPathComponent(databaseFileName),
            attachments: AttachmentStore(folder: folder.appendingPathComponent("Attachments", isDirectory: true))
        )
    }

    static let databaseFileName = "lumen.sqlite"

    /// База в файле. Если новая версия приложения меняет схему, перед этим старая база
    /// копируется в папку `Backups` рядом: при ошибке в миграции данные не пропадут.
    public static func onDisk(at url: URL, attachments: AttachmentStore = .temporary()) throws -> AppDatabase {
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        try copyBeforeMigrating(pool, into: url.deletingLastPathComponent().appendingPathComponent("Backups"))
        return try AppDatabase(pool, attachments: attachments)
    }

    /// База в памяти для тестов и превью.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    static var configuration: Configuration {
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

        migrator.registerMigration("v6: highlight deletedAt") { db in
            try db.alter(table: "highlight") { t in
                t.add(column: "deletedAt", .datetime)
            }
            // До этой версии удалённые выписки оставляли выделение в книге. Выделения, которых
            // нет ни в одной выписке, прячутся так же, как теперь при удалении выписки.
            let quoted = Set(try Data
                .fetchAll(db, sql: "SELECT content FROM block WHERE type = 'excerpt'")
                .compactMap { try? JSONDecoder().decode(BlockContent.self, from: $0).excerpt?.highlightId })
            let orphans = try UUID.fetchAll(db, sql: "SELECT id FROM highlight").filter { !quoted.contains($0) }
            try Highlight.filter(keys: orphans).updateAll(db, Column("deletedAt").set(to: Date()))
        }

        migrator.registerMigration("v7: reading sessions") { db in
            try db.create(table: "readingSession") { t in
                t.primaryKey("id", .blob)
                t.column("sourceId", .blob).notNull().references("source", onDelete: .cascade).indexed()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime).notNull()
                t.column("seconds", .double).notNull()
            }
        }

        // Журнал правок для iCloud. Пишется всегда, даже когда синхронизация выключена:
        // включив её, не придётся гадать, что менялось. Старые строки ставит в очередь первый запуск синхронизации.
        migrator.registerMigration("sync: change log") { db in
            try Self.createSyncSchema(db)
        }

        migrator.registerMigration("v8: databases") { db in
            // База данных живёт на странице. Свойства и представления хранятся JSON:
            // их мало, а меняются они всегда вместе с базой.
            try db.create(table: "dataTable") { t in
                t.primaryKey("id", .blob)
                t.column("pageId", .blob).notNull().references("page", onDelete: .cascade).unique()
                t.column("properties", .text).notNull()
                t.column("views", .text).notNull()
                t.column("template", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            // Строка базы это страница, вложенная в страницу базы, со значениями свойств в JSON.
            // Внешнего ключа на dataTable нет: строки удаляются вместе со страницей базы, а при
            // синхронизации строка может прийти раньше базы.
            try db.alter(table: "page") { t in
                t.add(column: "databaseId", .blob)
                t.add(column: "properties", .text)
            }
            try db.create(index: "page_on_databaseId", on: "page", columns: ["databaseId"])
            try Self.createSyncTriggers(db, table: "dataTable")
        }

        // Заметки к книгам раньше прятались от библиотеки. Теперь они лежат там же, где книга.
        migrator.registerMigration("book notes beside books") { db in
            try Self.moveBookNotesBesideBooks(db)
        }

        migrator.registerMigration("v9: drawings, notebooks") { db in
            // Штрихи блока «Рисунок» (PencilKit) двоичными данными рядом с JSON содержимого.
            try db.alter(table: "block") { t in
                t.add(column: "drawing", .blob)
            }
            // Вид страницы: пусто у обычной, `notebook` у рукописной заметки.
            try db.alter(table: "page") { t in
                t.add(column: "kind", .text)
            }
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

extension DataTable: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dataTable"
}

extension ReadingSession: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "readingSession"
}

// MARK: - Заметки к книгам рядом с книгами

extension AppDatabase {
    /// Кладёт заметки к книгам в папку книги, рядом с ней на холсте. Пустые заметки, которые
    /// раньше заводились сами при открытии книги, удаляются: теперь заметка появляется,
    /// только когда её открывают.
    /// Только простой SQL: записи GRDB описывают схему последней версии, а миграция видит старую.
    static func moveBookNotesBesideBooks(_ db: Database) throws {
        let rows = try Row.fetchAll(db, sql: """
            SELECT page.id AS pageId, source.id AS sourceId, source.folderId AS folderId,
                source.canvasX AS x, source.canvasY AS y
            FROM page
            JOIN source ON source.id = page.sourceId
            WHERE page.parentId IS NULL
            ORDER BY page.createdAt
            """)
        for row in rows {
            let pageId: UUID = row["pageId"]
            let sourceId: UUID = row["sourceId"]
            let folderId: UUID? = row["folderId"]
            if try isUntouchedBookNotes(db, pageId: pageId) {
                // Внешние ключи в миграции выключены (GRDB проверяет их в конце), каскада нет:
                // всё, что ссылается на страницу, удаляется руками.
                try db.execute(sql: "DELETE FROM pageSearch WHERE pageId = ?", arguments: [pageId.uuidString])
                try db.execute(sql: "DELETE FROM link WHERE sourcePageId = ?", arguments: [pageId])
                try db.execute(sql: "DELETE FROM block WHERE pageId = ?", arguments: [pageId])
                try db.execute(sql: "DELETE FROM dataTable WHERE pageId = ?", arguments: [pageId])
                try db.execute(sql: "DELETE FROM page WHERE id = ?", arguments: [pageId])
                continue
            }
            let spot = try spotBeside(
                db, sourceId: sourceId, folderId: folderId,
                anchor: LibraryPoint(x: row["x"] as Double?, y: row["y"] as Double?)
            )
            try db.execute(
                sql: "UPDATE page SET folderId = ?, canvasX = ?, canvasY = ? WHERE id = ?",
                arguments: [folderId, spot?.x, spot?.y, pageId]
            )
        }
    }

    /// Заметка, в которую так ничего и не написали: один пустой абзац, без подстраниц,
    /// без ссылок на неё, не в избранном и без обложки.
    private static func isUntouchedBookNotes(_ db: Database, pageId: UUID) throws -> Bool {
        let flags = try Row.fetchOne(db, sql: "SELECT isFavorite, cover FROM page WHERE id = ?", arguments: [pageId])
        guard let flags, flags["isFavorite"] as Bool? != true, flags["cover"] as String? == nil else { return false }
        let hasChildren = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM page WHERE parentId = ?)", arguments: [pageId]) ?? true
        let hasBacklinks = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM link WHERE targetPageId = ?)", arguments: [pageId]) ?? true
        guard !hasChildren, !hasBacklinks else { return false }
        let blocks = try Row.fetchAll(db, sql: "SELECT type, content FROM block WHERE pageId = ?", arguments: [pageId])
        guard blocks.count <= 1 else { return false }
        guard let block = blocks.first else { return true }
        guard block["type"] as String? == BlockType.paragraph.rawValue,
              let json = block["content"] as Data?,
              let content = try? JSONDecoder().decode(BlockContent.self, from: json)
        else { return false }
        return content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.attachment == nil && content.pageId == nil && content.excerpt == nil
    }
}
