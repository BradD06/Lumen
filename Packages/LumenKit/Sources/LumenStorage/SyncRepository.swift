import Foundation
import GRDB
import LumenCore

/// Всё, что нужно движку синхронизации от базы. Сам CloudKit живёт в модуле LumenSync:
/// здесь только строки, очередь правок и приём записей, поэтому всё это проверяется тестами без iCloud.
extension AppDatabase {
    // MARK: Отправка

    /// Правки, которые ждут отправки, по порядку.
    public func pendingSyncChanges() async throws -> [SyncChange] {
        try await reader.read { db in
            try SyncChange.order(Column("version")).fetchAll(db)
        }
    }

    /// Текущая строка для отправки и версия правки, которую она несёт. `nil`, если строки уже нет.
    public func syncRecord(for id: SyncRecordID) async throws -> (record: SyncRecord, version: Int64?)? {
        try await reader.read { db in
            guard let record = try Self.syncRecord(db, id: id) else { return nil }
            let version = try Int64.fetchOne(
                db,
                sql: "SELECT version FROM syncChange WHERE tableName = ? AND recordId = ?",
                arguments: [id.table.rawValue, id.id]
            )
            return (record, version)
        }
    }

    static func syncRecord(_ db: Database, id: SyncRecordID) throws -> SyncRecord? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(id.table.rawValue) WHERE id = ?", arguments: [id.id]) else {
            return nil
        }
        var fields: [String: SyncValue] = [:]
        for column in row.columnNames where column != "id" {
            fields[column] = SyncValue(row[column] as DatabaseValue)
        }
        for (field, column) in id.table.assetFields {
            if let name = row[column] as String?, !name.isEmpty {
                fields[field] = .asset(name)
            }
        }
        return SyncRecord(id: id, fields: fields)
    }

    /// Сервер принял правку. Строка очереди снимается, если её с тех пор не меняли ещё раз.
    public func markSynced(_ id: SyncRecordID, version: Int64) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM syncChange WHERE tableName = ? AND recordId = ? AND version <= ?",
                arguments: [id.table.rawValue, id.id, version]
            )
        }
    }

    /// Ставит в очередь все строки: при первом включении синхронизации или когда облако сбросили.
    public func enqueueAllForSync() async throws {
        try await writer.write { db in
            for table in SyncTable.allCases {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO syncChange(tableName, recordId, isDeletion, version)
                    SELECT '\(table.rawValue)', id, 0,
                        (SELECT COALESCE(MAX(version), 0) FROM syncChange) + ROW_NUMBER() OVER ()
                    FROM \(table.rawValue)
                    """)
            }
        }
    }

    // MARK: Приём

    /// Принимает записи из iCloud. Записи, которым пока не на что ссылаться (страницы ещё нет),
    /// ждут в `syncIncoming` и ложатся в базу, как только придёт недостающее.
    /// Если строку здесь поменяли позже, чем пришедшую запись, остаётся своя правка: она уйдёт на сервер.
    public func applyRemoteChanges(saved: [SyncRecord], deleted: [SyncRecordID]) async throws {
        let removedFiles = try await writer.write { db -> [String] in
            try db.execute(sql: "INSERT INTO syncApplying(id) VALUES (1)")
            defer { try? db.execute(sql: "DELETE FROM syncApplying") }

            let encoder = JSONEncoder()
            for record in saved {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO syncIncoming(recordName, payload) VALUES (?, ?)",
                    arguments: [record.id.recordName, try encoder.encode(record)]
                )
            }

            var touchedPages = Set<UUID>()
            var removedFiles: [String] = []
            for id in deleted {
                try db.execute(sql: "DELETE FROM syncIncoming WHERE recordName = ?", arguments: [id.recordName])
                try db.execute(
                    sql: "DELETE FROM syncChange WHERE tableName = ? AND recordId = ?",
                    arguments: [id.table.rawValue, id.id]
                )
                switch id.table {
                case .page:
                    // Страницы больше нет: из поиска её убирает reindex.
                    touchedPages.insert(id.id)
                case .block:
                    if let pageId = try UUID.fetchOne(db, sql: "SELECT pageId FROM block WHERE id = ?", arguments: [id.id]) {
                        touchedPages.insert(pageId)
                    }
                case .source:
                    if let source = try Source.fetchOne(db, key: id.id) {
                        removedFiles += [source.file] + (source.cover.map { [$0] } ?? [])
                    }
                case .folder, .highlight:
                    break
                }
                try db.execute(sql: "DELETE FROM \(id.table.rawValue) WHERE id = ?", arguments: [id.id])
            }

            touchedPages.formUnion(try Self.applyIncoming(db))
            for pageId in touchedPages {
                try Self.reindex(db, pageId: pageId)
            }
            return removedFiles
        }
        for file in removedFiles {
            attachments.remove(file)
        }
    }

    /// Кладёт в базу всё, что ждёт в `syncIncoming`, пока это получается. Возвращает затронутые страницы.
    static func applyIncoming(_ db: Database) throws -> Set<UUID> {
        let decoder = JSONDecoder()
        var pending = try Row.fetchAll(db, sql: "SELECT recordName, payload FROM syncIncoming").compactMap { row in
            try? decoder.decode(SyncRecord.self, from: row["payload"] as Data)
        }
        pending.sort { lhs, rhs in
            let order = SyncTable.allCases
            return order.firstIndex(of: lhs.id.table)! < order.firstIndex(of: rhs.id.table)!
        }

        var touchedPages = Set<UUID>()
        var madeProgress = true
        // По кругу, пока хоть что-то ложится: дети могут прийти раньше родителей той же таблицы.
        while madeProgress, !pending.isEmpty {
            madeProgress = false
            var stillPending: [SyncRecord] = []
            for record in pending {
                do {
                    try db.inSavepoint {
                        try upsert(db, record: record)
                        return .commit
                    }
                } catch {
                    // Обычно это ссылка на строку, которой ещё нет. Запись подождёт.
                    stillPending.append(record)
                    continue
                }
                madeProgress = true
                try db.execute(sql: "DELETE FROM syncIncoming WHERE recordName = ?", arguments: [record.id.recordName])
                switch record.id.table {
                case .page:
                    touchedPages.insert(record.id.id)
                case .block:
                    if let block = try Block.fetchOne(db, key: record.id.id) {
                        try updateLinks(db, block: block)
                        touchedPages.insert(block.pageId)
                    }
                case .folder, .source, .highlight:
                    break
                }
            }
            pending = stillPending
        }
        return touchedPages
    }

    /// Вставляет или обновляет строку. Не через REPLACE: тот удалил бы строку вместе с детьми.
    static func upsert(_ db: Database, record: SyncRecord) throws {
        let table = record.id.table.rawValue
        let pending = try SyncChange
            .filter(Column("tableName") == table && Column("recordId") == record.id.id)
            .fetchOne(db)
        if let pending, !pending.isDeletion,
           let localDate = try Date.fetchOne(db, sql: "SELECT updatedAt FROM \(table) WHERE id = ?", arguments: [record.id.id]),
           let remoteDate = record.updatedAt, localDate > remoteDate {
            // Своя правка новее: её и оставляем.
            return
        }

        let columns = try db.columns(in: table).filter { $0.name != "id" }
        var names = ["id"]
        var values: [DatabaseValue] = [record.id.id.databaseValue]
        var updates: [String] = []
        for column in columns {
            if let value = record.fields[column.name] {
                names.append(column.name)
                values.append(value.databaseValue)
                updates.append("\(column.name) = excluded.\(column.name)")
            } else if !column.isNotNull {
                // Поле стёрли на другом устройстве: в записи CloudKit пустых полей нет.
                updates.append("\(column.name) = NULL")
            }
        }
        let placeholders = Array(repeating: "?", count: names.count).joined(separator: ", ")
        try db.execute(
            sql: """
                INSERT INTO \(table)(\(names.joined(separator: ", "))) VALUES (\(placeholders))
                ON CONFLICT(id) DO UPDATE SET \(updates.joined(separator: ", "))
                """,
            arguments: StatementArguments(values)
        )
        if let pending, !pending.isDeletion {
            // Строка теперь совпадает с сервером, отправлять нечего.
            try pending.delete(db)
        }
    }

    // MARK: Служебное

    /// Служебные поля записи CloudKit, сохранённые после прошлой отправки или приёма.
    public func syncSystemFields(for id: SyncRecordID) async throws -> Data? {
        try await reader.read { db in
            try Data.fetchOne(db, sql: "SELECT systemFields FROM syncRecordMetadata WHERE recordName = ?", arguments: [id.recordName])
        }
    }

    public func saveSyncSystemFields(_ fields: [SyncRecordID: Data], removing removed: [SyncRecordID] = []) async throws {
        try await writer.write { db in
            for (id, data) in fields {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO syncRecordMetadata(recordName, systemFields) VALUES (?, ?)",
                    arguments: [id.recordName, data]
                )
            }
            for id in removed {
                try db.execute(sql: "DELETE FROM syncRecordMetadata WHERE recordName = ?", arguments: [id.recordName])
            }
        }
    }

    public func syncStateValue(forKey key: String) async throws -> Data? {
        try await reader.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM syncState WHERE key = ?", arguments: [key])
        }
    }

    public func setSyncStateValue(_ value: Data?, forKey key: String) async throws {
        try await writer.write { db in
            if let value {
                try db.execute(sql: "INSERT OR REPLACE INTO syncState(key, value) VALUES (?, ?)", arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM syncState WHERE key = ?", arguments: [key])
            }
        }
    }

    /// Другой аккаунт iCloud или облако очистили: связь с сервером забывается, данные на устройстве
    /// остаются и при следующей синхронизации уходят на сервер целиком.
    public func resetSyncMetadata() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM syncRecordMetadata")
            try db.execute(sql: "DELETE FROM syncState")
            try db.execute(sql: "DELETE FROM syncIncoming")
        }
        try await enqueueAllForSync()
    }
}
