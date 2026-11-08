import Foundation
import GRDB

/// Одна правка строки в файле общей папки: строка целиком или отметка, что её удалили.
/// `changedAt` это время правки в виде даты GRDB (`2026-11-08 08:31:02.123`, UTC):
/// такие строки сравниваются как время, и из двух правок остаётся более поздняя.
public struct FolderSyncEntry: Hashable, Sendable {
    public var id: SyncRecordID
    public var changedAt: String
    /// `nil`, если строку удалили.
    public var fields: [String: SyncValue]?

    public init(id: SyncRecordID, changedAt: String, fields: [String: SyncValue]?) {
        self.id = id
        self.changedAt = changedAt
        self.fields = fields
    }
}

/// Простой JSON, чтобы файлы мог прочитать кто угодно, например будущая версия для Windows:
/// `{"record": "page.<id>", "changedAt": "…", "fields": {"title": "Лекция", "parentId": {"data": "<base64>"}}}`.
extension FolderSyncEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case record, changedAt, fields, deleted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .record)
        guard let id = SyncRecordID(recordName: name) else {
            throw DecodingError.dataCorruptedError(forKey: .record, in: container, debugDescription: "Неизвестная запись \(name)")
        }
        self.id = id
        changedAt = try container.decode(String.self, forKey: .changedAt)
        fields = try container.decodeIfPresent([String: FolderValue].self, forKey: .fields)?.mapValues(\.value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.recordName, forKey: .record)
        try container.encode(changedAt, forKey: .changedAt)
        if let fields {
            try container.encode(fields.mapValues { FolderValue($0) }, forKey: .fields)
        } else {
            try container.encode(true, forKey: .deleted)
        }
    }
}

/// Значение поля в JSON: null, число, строка или `{"data": base64}` для двоичных данных.
/// Целое и дробное число различаются только видом, остальное делает тип колонки SQLite.
struct FolderValue: Codable {
    var value: SyncValue

    init(_ value: SyncValue) {
        self.value = value
    }

    private enum Keys: String, CodingKey {
        case data
    }

    init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            value = .null
        } else if let int = try? single.decode(Int64.self) {
            value = .integer(int)
        } else if let double = try? single.decode(Double.self) {
            value = .double(double)
        } else if let text = try? single.decode(String.self) {
            value = .text(text)
        } else {
            let keyed = try decoder.container(keyedBy: Keys.self)
            let base64 = try keyed.decode(String.self, forKey: .data)
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(forKey: .data, in: keyed, debugDescription: "Не base64")
            }
            value = .data(data)
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch value {
        case .null, .asset:
            var single = encoder.singleValueContainer()
            try single.encodeNil()
        case .integer(let int):
            var single = encoder.singleValueContainer()
            try single.encode(int)
        case .double(let double):
            var single = encoder.singleValueContainer()
            // В JSON нет бесконечности и NaN.
            if double.isFinite { try single.encode(double) } else { try single.encodeNil() }
        case .text(let text):
            var single = encoder.singleValueContainer()
            try single.encode(text)
        case .data(let data):
            var keyed = encoder.container(keyedBy: Keys.self)
            try keyed.encode(data.base64EncodedString(), forKey: .data)
        }
    }
}

/// Сторона базы для синхронизации через папку. Сами файлы читает и пишет `FolderSyncEngine`.
extension AppDatabase {
    /// Текущее время в виде даты GRDB.
    static func syncClockNow() -> String {
        String.fromDatabaseValue(Date().databaseValue) ?? ""
    }

    /// До `limit` правок из очереди: строки целиком в том виде, в каком они сейчас в базе.
    /// `changes` нужно потом отдать в `markFolderSynced`, когда файл с правками записан.
    public func folderSyncOutgoing(limit: Int) async throws -> (entries: [FolderSyncEntry], changes: [SyncChange]) {
        try await reader.read { db in
            let changes = try SyncChange.order(Column("version")).limit(limit).fetchAll(db)
            var entries: [FolderSyncEntry] = []
            for change in changes {
                guard let id = change.id else { continue }
                let clock = try String.fetchOne(
                    db,
                    sql: "SELECT changedAt FROM syncClock WHERE tableName = ? AND recordId = ?",
                    arguments: [id.table.rawValue, id.id]
                )
                if let record = try Self.syncRecord(db, id: id) {
                    entries.append(Self.folderEntry(record, clock: clock))
                } else {
                    entries.append(FolderSyncEntry(id: id, changedAt: clock ?? Self.syncClockNow(), fields: nil))
                }
            }
            return (entries, changes)
        }
    }

    /// Строка для файла. Без часов (строка старше журнала) временем правки считается `updatedAt`.
    static func folderEntry(_ record: SyncRecord, clock: String?) -> FolderSyncEntry {
        // Файлы книг едут отдельно, папкой `files`.
        let fields = record.fields.filter { _, value in
            if case .asset = value { false } else { true }
        }
        var changedAt = clock
        if changedAt == nil, case .text(let updatedAt)? = record.fields["updatedAt"] {
            changedAt = updatedAt
        }
        return FolderSyncEntry(id: record.id, changedAt: changedAt ?? "", fields: fields)
    }

    /// Правки записаны в папку: строки очереди снимаются, если их с тех пор не меняли ещё раз.
    public func markFolderSynced(_ changes: [SyncChange]) async throws {
        try await writer.write { db in
            for change in changes {
                try db.execute(
                    sql: "DELETE FROM syncChange WHERE tableName = ? AND recordId = ? AND version <= ?",
                    arguments: [change.tableName, change.recordId, change.version]
                )
            }
        }
    }

    /// Все строки и все удаления, которые помнит база: из этого собирается сжатая копия
    /// правок устройства, чтобы в папке не копились тысячи старых файлов.
    public func folderSyncSnapshot() async throws -> [FolderSyncEntry] {
        try await reader.read { db in
            var entries: [FolderSyncEntry] = []
            for table in SyncTable.allCases {
                var clocks: [UUID: String] = [:]
                for row in try Row.fetchAll(
                    db,
                    sql: "SELECT recordId, changedAt FROM syncClock WHERE tableName = ? AND isDeleted = 0",
                    arguments: [table.rawValue]
                ) {
                    let id: UUID = row["recordId"]
                    let changedAt: String = row["changedAt"]
                    clocks[id] = changedAt
                }
                for row in try Row.fetchAll(db, sql: "SELECT * FROM \(table.rawValue)") {
                    let uuid: UUID = row["id"]
                    let record = Self.syncRecord(row: row, id: SyncRecordID(table: table, id: uuid))
                    entries.append(Self.folderEntry(record, clock: clocks[uuid]))
                }
            }
            for row in try Row.fetchAll(db, sql: "SELECT tableName, recordId, changedAt FROM syncClock WHERE isDeleted = 1") {
                let tableName: String = row["tableName"]
                let id: UUID = row["recordId"]
                let changedAt: String = row["changedAt"]
                guard let table = SyncTable(rawValue: tableName) else { continue }
                entries.append(FolderSyncEntry(id: SyncRecordID(table: table, id: id), changedAt: changedAt, fields: nil))
            }
            return entries
        }
    }

    /// Принимает правки другого устройства. Ложится только то, что новее своего: своя правка
    /// или удаление, сделанные позже, остаются и уедут на другие устройства сами.
    /// Возвращает, сколько правок легло.
    @discardableResult
    public func applyFolderEntries(_ entries: [FolderSyncEntry]) async throws -> Int {
        var latest: [SyncRecordID: FolderSyncEntry] = [:]
        for entry in entries {
            if let known = latest[entry.id], known.changedAt >= entry.changedAt { continue }
            latest[entry.id] = entry
        }
        let incoming = Array(latest.values)
        let (applied, removedFiles) = try await writer.write { db -> (Int, [String]) in
            try db.execute(sql: "INSERT INTO syncApplying(id) VALUES (1)")
            defer { try? db.execute(sql: "DELETE FROM syncApplying") }

            var saved: [SyncRecord] = []
            var deleted: [SyncRecordID] = []
            for entry in incoming {
                guard try Self.isNewerThanLocal(db, entry) else { continue }
                // Своя правка старше пришедшей: отправлять её больше незачем.
                try db.execute(
                    sql: "DELETE FROM syncChange WHERE tableName = ? AND recordId = ?",
                    arguments: [entry.id.table.rawValue, entry.id.id]
                )
                try db.execute(
                    sql: "INSERT OR REPLACE INTO syncClock(tableName, recordId, changedAt, isDeleted) VALUES (?, ?, ?, ?)",
                    arguments: [entry.id.table.rawValue, entry.id.id, entry.changedAt, entry.fields == nil]
                )
                if let fields = entry.fields {
                    saved.append(SyncRecord(id: entry.id, fields: fields))
                } else {
                    deleted.append(entry.id)
                }
            }
            let removed = try Self.applyRemote(db, saved: saved, deleted: deleted)
            return (saved.count + deleted.count, removed)
        }
        for file in removedFiles {
            attachments.remove(file)
        }
        return applied
    }

    static func isNewerThanLocal(_ db: Database, _ entry: FolderSyncEntry) throws -> Bool {
        let table = entry.id.table
        if let clock = try String.fetchOne(
            db,
            sql: "SELECT changedAt FROM syncClock WHERE tableName = ? AND recordId = ?",
            arguments: [table.rawValue, entry.id.id]
        ) {
            return entry.changedAt > clock
        }
        // Строка старше журнала часов: её время это `updatedAt`, а у времени чтения его нет.
        if table == .readingSession {
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM readingSession WHERE id = ?)", arguments: [entry.id.id]) ?? false
            return !exists
        }
        guard let updatedAt = try String.fetchOne(db, sql: "SELECT updatedAt FROM \(table.rawValue) WHERE id = ?", arguments: [entry.id.id]) else {
            return true
        }
        return entry.changedAt > updatedAt
    }

    /// Какие из этих файлов-вложений нужны базе: книги, обложки, фоны и картинки в блоках.
    /// Файлы удалённых навсегда книг не тянутся обратно из папки.
    public func referencedAttachments(among names: Set<String>) async throws -> Set<String> {
        guard !names.isEmpty else { return [] }
        return try await reader.read { db in
            var found = Set<String>()
            for name in names {
                let pattern = "%\(name)%"
                let used = try Bool.fetchOne(db, sql: """
                    SELECT EXISTS (SELECT 1 FROM source WHERE file = :name OR cover = :name)
                        OR EXISTS (SELECT 1 FROM page WHERE cover LIKE :pattern OR background LIKE :pattern)
                        OR EXISTS (SELECT 1 FROM block WHERE content LIKE :pattern)
                    """, arguments: ["name": name, "pattern": pattern]) ?? false
                if used { found.insert(name) }
            }
            return found
        }
    }

    /// Состояние синхронизации через папку забывается: при выборе другой папки всё читается
    /// и отправляется заново. Данные на устройстве не трогаются.
    public func resetFolderSyncState() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM syncState WHERE key LIKE 'folder.%'")
        }
        try await enqueueAllForSync()
    }

    func folderSyncNumber(forKey key: String) async throws -> Int? {
        guard let data = try await syncStateValue(forKey: key) else { return nil }
        return Int(String(decoding: data, as: UTF8.self))
    }

    func setFolderSyncNumber(_ value: Int, forKey key: String) async throws {
        try await setSyncStateValue(Data(String(value).utf8), forKey: key)
    }
}
