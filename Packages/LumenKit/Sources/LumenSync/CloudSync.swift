import CloudKit
import Foundation
import GRDB
import LumenStorage
import Observation
import OSLog

private let syncLog = Logger(subsystem: "io.github.bradd06.lumen", category: "sync")

/// Что показывать человеку о синхронизации.
@MainActor
@Observable
public final class SyncStatus {
    public enum State: Equatable, Sendable {
        /// Синхронизация не настроена в сборке: нет контейнера iCloud (нужен платный аккаунт разработчика).
        case notConfigured
        /// На устройстве не выполнен вход в iCloud.
        case noAccount
        case syncing
        case upToDate(Date)
        case failed(String)
    }

    public var state: State

    public init(state: State = .notConfigured) {
        self.state = state
    }
}

/// Синхронизация через iCloud: личная база CloudKit пользователя и `CKSyncEngine`.
/// Движок сам решает, когда отправлять и получать, следит за входом в iCloud и повторяет запросы.
/// Здесь только перевод строк базы в записи CloudKit и обратно.
///
/// Работает, только если в сборке указан контейнер iCloud (`LumenCloudKitContainer` в Info.plist)
/// и приложение подписано с правами iCloud. Без них `CloudSync` не создаётся: обращение к CloudKit
/// без прав завершает приложение.
public actor CloudSync {
    public static let zoneName = "Lumen"
    private static let stateKey = "ckSyncEngineState"

    private let database: AppDatabase
    private let container: CKContainer
    private let status: SyncStatus
    private var engine: CKSyncEngine?
    private var observation: Task<Void, Never>?
    /// Какую версию правки несла отправленная запись: после ответа сервера снимается именно она.
    private var sentVersions: [String: Int64] = [:]

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public init(database: AppDatabase, containerIdentifier: String, status: SyncStatus) {
        self.database = database
        self.container = CKContainer(identifier: containerIdentifier)
        self.status = status
    }

    /// Контейнер из Info.plist. Пусто, если сборка без iCloud.
    public static var configuredContainer: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LumenCloudKitContainer") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func start() async {
        guard engine == nil else { return }
        if (try? await container.accountStatus()) != .available {
            await setStatus(.noAccount)
        }

        let saved = try? await database.syncStateValue(forKey: Self.stateKey)
        let state = saved.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: state,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        if state == nil {
            // Первый запуск: создать зону и отправить всё, что уже есть на устройстве.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            try? await database.enqueueAllForSync()
        }
        observeLocalChanges()
    }

    /// Получить и отправить изменения сейчас, например по кнопке или при открытии приложения.
    public func syncNow() async {
        guard let engine else { return }
        await setStatus(.syncing)
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            await setStatus(.upToDate(Date()))
        } catch {
            await setStatus(.failed(error.localizedDescription))
        }
    }

    // MARK: Локальные правки

    /// Каждая запись в очереди базы становится отложенной правкой движка.
    private func observeLocalChanges() {
        observation?.cancel()
        let observation = ValueObservation.tracking { db in
            try SyncChange.order(Column("version")).fetchAll(db)
        }
        let reader = database.reader
        self.observation = Task { [weak self] in
            do {
                for try await changes in observation.values(in: reader) {
                    await self?.schedule(changes)
                }
            } catch {
                syncLog.error("Sync observation failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func schedule(_ changes: [SyncChange]) {
        guard let engine else { return }
        var saves = Set<String>()
        var deletes = Set<String>()
        for change in engine.state.pendingRecordZoneChanges {
            switch change {
            case .saveRecord(let recordID): saves.insert(recordID.recordName)
            case .deleteRecord(let recordID): deletes.insert(recordID.recordName)
            @unknown default: break
            }
        }
        var add: [CKSyncEngine.PendingRecordZoneChange] = []
        var remove: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in changes {
            guard let id = change.id else { continue }
            let name = id.recordName
            let recordID = CKRecord.ID(recordName: name, zoneID: zoneID)
            if change.isDeletion {
                if saves.contains(name) { remove.append(.saveRecord(recordID)) }
                if !deletes.contains(name) { add.append(.deleteRecord(recordID)) }
            } else {
                if deletes.contains(name) { remove.append(.deleteRecord(recordID)) }
                if !saves.contains(name) { add.append(.saveRecord(recordID)) }
            }
        }
        if !remove.isEmpty { engine.state.remove(pendingRecordZoneChanges: remove) }
        if !add.isEmpty { engine.state.add(pendingRecordZoneChanges: add) }
    }

    // MARK: Записи

    private func record(for recordID: CKRecord.ID) async -> CKRecord? {
        guard let id = SyncRecordID(recordName: recordID.recordName),
              let found = try? await database.syncRecord(for: id) else { return nil }
        if let version = found.version {
            sentVersions[recordID.recordName] = version
        }

        let record: CKRecord
        if let data = try? await database.syncSystemFields(for: id), let restored = Self.decodeSystemFields(data) {
            record = restored
        } else {
            record = CKRecord(recordType: id.table.recordType, recordID: recordID)
        }
        for (key, value) in found.record.fields {
            switch value {
            case .null: record.setObject(nil, forKey: key)
            case .integer(let int): record.setObject(NSNumber(value: int), forKey: key)
            case .double(let double): record.setObject(NSNumber(value: double), forKey: key)
            case .text(let text): record.setObject(text as NSString, forKey: key)
            case .data(let data): record.setObject(data as NSData, forKey: key)
            case .asset(let name):
                let url = database.attachments.url(for: name)
                if FileManager.default.fileExists(atPath: url.path) {
                    record.setObject(CKAsset(fileURL: url), forKey: key)
                }
            }
        }
        return record
    }

    /// Запись CloudKit в строку базы. Файлы из вложений копируются в папку вложений под своими именами.
    private func syncRecord(from record: CKRecord) -> SyncRecord? {
        guard let id = SyncRecordID(recordName: record.recordID.recordName) else { return nil }
        var fields: [String: SyncValue] = [:]
        for key in record.allKeys() {
            guard let value = record.object(forKey: key) else { continue }
            switch value {
            case let asset as CKAsset:
                fields[key] = .asset(asset.fileURL?.lastPathComponent ?? "")
            case let text as String:
                fields[key] = .text(text)
            case let data as Data:
                fields[key] = .data(data)
            case let number as NSNumber:
                fields[key] = CFNumberIsFloatType(number as CFNumber) ? .double(number.doubleValue) : .integer(number.int64Value)
            default:
                break
            }
        }
        for (field, column) in id.table.assetFields {
            guard let asset = record.object(forKey: field) as? CKAsset, let url = asset.fileURL,
                  case .text(let name)? = fields[column], !name.isEmpty else { continue }
            let target = database.attachments.url(for: name)
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.createDirectory(at: database.attachments.folder, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: url, to: target)
            }
        }
        for (field, _) in id.table.assetFields {
            fields[field] = nil
        }
        return SyncRecord(id: id, fields: fields)
    }

    private static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private func setStatus(_ state: SyncStatus.State) async {
        let status = status
        await MainActor.run { status.state = state }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSync: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            let data = try? JSONEncoder().encode(update.stateSerialization)
            try? await database.setSyncStateValue(data, forKey: Self.stateKey)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                try? await database.enqueueAllForSync()
                await setStatus(.syncing)
            case .signOut, .switchAccounts:
                // Данные остаются на устройстве, связь со старым аккаунтом забывается.
                try? await database.resetSyncMetadata()
                await setStatus(.noAccount)
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                // Облако очистили в настройках iCloud: всё с устройства уходит туда заново.
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                try? await database.resetSyncMetadata()
            }

        case .fetchedRecordZoneChanges(let changes):
            var systemFields: [SyncRecordID: Data] = [:]
            var saved: [SyncRecord] = []
            for modification in changes.modifications {
                guard let record = syncRecord(from: modification.record) else { continue }
                systemFields[record.id] = Self.encodeSystemFields(modification.record)
                saved.append(record)
            }
            let deleted = changes.deletions.compactMap { SyncRecordID(recordName: $0.recordID.recordName) }
            try? await database.saveSyncSystemFields(systemFields, removing: deleted)
            do {
                try await database.applyRemoteChanges(saved: saved, deleted: deleted)
            } catch {
                await setStatus(.failed(error.localizedDescription))
            }

        case .sentRecordZoneChanges(let sent):
            await handleSent(sent, syncEngine: syncEngine)

        case .willFetchChanges, .willSendChanges:
            await setStatus(.syncing)

        case .didFetchChanges, .didSendChanges:
            await setStatus(.upToDate(Date()))

        default:
            break
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) async {
        var systemFields: [SyncRecordID: Data] = [:]
        for record in sent.savedRecords {
            guard let id = SyncRecordID(recordName: record.recordID.recordName) else { continue }
            systemFields[id] = Self.encodeSystemFields(record)
            if let version = sentVersions.removeValue(forKey: record.recordID.recordName) {
                try? await database.markSynced(id, version: version)
            }
        }
        var removed: [SyncRecordID] = []
        for recordID in sent.deletedRecordIDs {
            guard let id = SyncRecordID(recordName: recordID.recordName) else { continue }
            removed.append(id)
            if let version = sentVersions.removeValue(forKey: recordID.recordName) {
                try? await database.markSynced(id, version: version)
            } else if let change = try? await database.pendingSyncChanges().first(where: { $0.id == id && $0.isDeletion }) {
                try? await database.markSynced(id, version: change.version)
            }
        }
        try? await database.saveSyncSystemFields(systemFields, removing: removed)

        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            guard let id = SyncRecordID(recordName: recordID.recordName) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                // На сервере правка новее нашей метки. Берём серверную запись: если наша строка
                // новее, база её не перезапишет, и правка уйдёт ещё раз уже с новой меткой.
                guard let server = failure.error.serverRecord else { break }
                try? await database.saveSyncSystemFields([id: Self.encodeSystemFields(server)])
                if let record = syncRecord(from: server) {
                    try? await database.applyRemoteChanges(saved: [record], deleted: [])
                }
                if (try? await database.pendingSyncChanges().contains(where: { $0.id == id })) == true {
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                }
            case .zoneNotFound:
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                try? await database.saveSyncSystemFields([:], removing: [id])
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .unknownItem:
                // Записи на сервере нет, хотя метка есть: отправляем как новую.
                try? await database.saveSyncSystemFields([:], removing: [id])
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .quotaExceeded:
                await setStatus(.failed("В iCloud закончилось место"))
            default:
                // Сеть, занятый сервер и прочее временное движок повторит сам.
                break
            }
        }
        // Правки, сделанные пока запись летела на сервер, остались в очереди базы: их движку напоминаем.
        if let pending = try? await database.pendingSyncChanges() {
            schedule(pending)
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(for: recordID)
        }
    }
}
