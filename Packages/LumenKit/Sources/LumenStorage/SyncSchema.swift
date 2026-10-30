import Foundation
import GRDB

/// Таблицы, которые уезжают в iCloud. Порядок важен: при приёме записей сначала создаются
/// папки и книги, потом страницы, блоки и выделения, которые на них ссылаются.
/// Поиск и индекс ссылок не синхронизируются: они собираются заново из страниц и блоков.
public enum SyncTable: String, CaseIterable, Codable, Sendable {
    case folder
    case source
    case page
    case block
    case highlight

    /// Тип записи в CloudKit.
    public var recordType: String {
        switch self {
        case .folder: "Folder"
        case .source: "Source"
        case .page: "Page"
        case .block: "Block"
        case .highlight: "Highlight"
        }
    }

    public init?(recordType: String) {
        guard let table = Self.allCases.first(where: { $0.recordType == recordType }) else { return nil }
        self = table
    }

    /// Поля записи с файлами-вложениями: имя поля в записи и колонка с именем файла.
    /// Файлы книг едут в iCloud вместе с книгой, их не скачать заново из другого места.
    public var assetFields: [(field: String, column: String)] {
        switch self {
        case .source: [("fileAsset", "file"), ("coverAsset", "cover")]
        default: []
        }
    }
}

/// Имя записи в CloudKit: таблица и идентификатор строки, например `page.5F1C…`.
/// Имя одно на всю зону, поэтому таблица входит в него.
public struct SyncRecordID: Hashable, Codable, Sendable {
    public var table: SyncTable
    public var id: UUID

    public init(table: SyncTable, id: UUID) {
        self.table = table
        self.id = id
    }

    public var recordName: String { "\(table.rawValue).\(id.uuidString)" }

    public init?(recordName: String) {
        let parts = recordName.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let table = SyncTable(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else {
            return nil
        }
        self.init(table: table, id: id)
    }
}

/// Значение поля записи. Хранится так же, как в SQLite, чтобы строка вернулась в базу без потерь.
public enum SyncValue: Hashable, Codable, Sendable {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
    case data(Data)
    /// Файл из папки вложений по имени.
    case asset(String)

    init(_ value: DatabaseValue) {
        switch value.storage {
        case .null: self = .null
        case .int64(let int): self = .integer(int)
        case .double(let double): self = .double(double)
        case .string(let string): self = .text(string)
        case .blob(let data): self = .data(data)
        }
    }

    var databaseValue: DatabaseValue {
        switch self {
        case .null, .asset: .null
        case .integer(let int): int.databaseValue
        case .double(let double): double.databaseValue
        case .text(let string): string.databaseValue
        case .data(let data): data.databaseValue
        }
    }
}

/// Строка таблицы в виде, который не зависит от CloudKit: так её легко проверить в тестах.
public struct SyncRecord: Hashable, Codable, Sendable {
    public var id: SyncRecordID
    public var fields: [String: SyncValue]

    public init(id: SyncRecordID, fields: [String: SyncValue]) {
        self.id = id
        self.fields = fields
    }

    /// Когда запись меняли: по этому времени решается, чья правка новее.
    public var updatedAt: Date? {
        guard case .text(let text) = fields["updatedAt"] else { return nil }
        return Date.fromDatabaseValue(text.databaseValue)
    }
}

/// Локальная правка, которую ещё не отправили в iCloud. Записывается триггерами SQLite
/// при любой вставке, изменении или удалении строки, поэтому ни один репозиторий о ней не думает.
public struct SyncChange: Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "syncChange"

    public var tableName: String
    public var recordId: UUID
    public var isDeletion: Bool
    /// Растёт с каждой правкой. Отправленная правка снимается, только если после неё ничего не меняли.
    public var version: Int64

    public var id: SyncRecordID? {
        SyncTable(rawValue: tableName).map { SyncRecordID(table: $0, id: recordId) }
    }

    public init(row: Row) throws {
        tableName = row["tableName"]
        recordId = row["recordId"]
        isDeletion = row["isDeletion"]
        version = row["version"]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["tableName"] = tableName
        container["recordId"] = recordId
        container["isDeletion"] = isDeletion
        container["version"] = version
    }
}

extension AppDatabase {
    /// Таблицы и триггеры журнала синхронизации.
    static func createSyncSchema(_ db: Database) throws {
        // Очередь правок для отправки.
        try db.create(table: "syncChange") { t in
            t.column("tableName", .text).notNull()
            t.column("recordId", .blob).notNull()
            t.column("isDeletion", .boolean).notNull()
            t.column("version", .integer).notNull()
            t.primaryKey(["tableName", "recordId"])
        }
        // Служебные поля записей CloudKit (метка изменения), без них сервер не примет правку.
        try db.create(table: "syncRecordMetadata") { t in
            t.primaryKey("recordName", .text)
            t.column("systemFields", .blob).notNull()
        }
        // Состояние движка синхронизации и прочие настройки.
        try db.create(table: "syncState") { t in
            t.primaryKey("key", .text)
            t.column("value", .blob).notNull()
        }
        // Записи из iCloud, которые пока не легли в базу: например блок пришёл раньше своей страницы.
        try db.create(table: "syncIncoming") { t in
            t.primaryKey("recordName", .text)
            t.column("payload", .blob).notNull()
        }
        // Пока в этой таблице есть строка, база принимает записи из iCloud и триггеры молчат,
        // иначе принятая запись тут же ушла бы обратно на сервер.
        try db.create(table: "syncApplying") { t in
            t.primaryKey("id", .integer)
        }

        for table in SyncTable.allCases {
            try createSyncTriggers(db, table: table.rawValue)
        }
    }

    static func createSyncTriggers(_ db: Database, table: String) throws {
        for (event, row, isDeletion) in [("INSERT", "NEW", 0), ("UPDATE", "NEW", 0), ("DELETE", "OLD", 1)] {
            try db.execute(sql: """
                CREATE TRIGGER sync_\(table)_\(event.lowercased())
                AFTER \(event) ON \(table)
                WHEN NOT EXISTS (SELECT 1 FROM syncApplying)
                BEGIN
                    INSERT OR REPLACE INTO syncChange(tableName, recordId, isDeletion, version)
                    VALUES ('\(table)', \(row).id, \(isDeletion), (SELECT COALESCE(MAX(version), 0) + 1 FROM syncChange));
                END
                """)
        }
    }
}
