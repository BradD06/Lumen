import Foundation

/// Синхронизация через обычную папку, которую человек выбрал сам, например в iCloud Drive.
/// Платный аккаунт разработчика для этого не нужен: файлы между устройствами возит сам iCloud
/// (или Dropbox, Google Drive и любое другое облако с папкой на диске).
///
/// Общую базу SQLite в облаке держать нельзя: два устройства, пишущие в один файл, её ломают.
/// Поэтому база у каждого устройства своя, а в папке лежат правки:
///
/// ```
/// Lumen Sync/
///   format.json                      версия формата
///   devices/<устройство>/device.json название устройства и когда оно было на связи
///   devices/<устройство>/changes/0000000001.json, …  правки по порядку
///   devices/<устройство>/snapshot-0000000300.json    сжатая копия вместо старых правок
///   files/<имя>                      книги, обложки и картинки
/// ```
///
/// Каждое устройство пишет только в свою папку, поэтому облаку не из-за чего делать копии-конфликты.
/// Чужие правки читаются по порядку номеров, из двух правок одной строки остаётся более поздняя.
public final class FolderSyncEngine: Sendable {
    public static let folderName = "Lumen Sync"
    static let format = 1
    /// Сколько строк в одном файле правок.
    static let batchLimit = 500

    public let database: AppDatabase
    /// Папка «Lumen Sync».
    public let root: URL
    public let deviceId: String
    public let deviceName: String
    /// После стольких файлов правок устройство заменяет их одной сжатой копией.
    let compactAfter: Int

    public init(database: AppDatabase, root: URL, deviceId: String, deviceName: String, compactAfter: Int = 300) {
        self.database = database
        self.root = root
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.compactAfter = compactAfter
    }

    /// Где лежат данные в выбранной папке: в ней самой, если выбрали уже «Lumen Sync», иначе внутри неё.
    /// Так на всех устройствах достаточно выбрать один и тот же iCloud Drive.
    public static func dataFolder(in picked: URL) -> URL {
        picked.lastPathComponent == folderName ? picked : picked.appendingPathComponent(folderName, isDirectory: true)
    }

    var devicesFolder: URL { root.appendingPathComponent("devices", isDirectory: true) }
    var filesFolder: URL { root.appendingPathComponent("files", isDirectory: true) }
    var ownFolder: URL { devicesFolder.appendingPathComponent(deviceId, isDirectory: true) }

    static func changesFolder(_ device: URL) -> URL { device.appendingPathComponent("changes", isDirectory: true) }
    static func changeName(_ seq: Int) -> String { String(format: "%010d.json", seq) }
    static func snapshotName(_ seq: Int) -> String { String(format: "snapshot-%010d.json", seq) }

    static func seq(fromChange name: String) -> Int? {
        guard name.hasSuffix(".json"), name.count == 15 else { return nil }
        return Int(name.dropLast(5))
    }

    static func seq(fromSnapshot name: String) -> Int? {
        guard name.hasPrefix("snapshot-"), name.hasSuffix(".json") else { return nil }
        return Int(name.dropFirst(9).dropLast(5))
    }

    // MARK: Круг синхронизации

    /// Один круг: принять чужие правки и файлы, отправить свои. Безопасно повторять сколько угодно.
    public func sync() async throws -> FolderSyncReport {
        try prepare()
        var report = FolderSyncReport()
        // Чужое читается раньше, чем своё пишется: правки, пришедшие новее своих, не уедут обратно.
        var firstError: (any Error)?
        do {
            report.received = try await pullChanges()
        } catch {
            firstError = error
        }
        report.filesReceived = try await pullFiles()
        // Файлы раньше строк: на другом устройстве книга появится уже с файлом.
        report.filesSent = try await pushFiles()
        report.sent = try await pushChanges()
        try await compactIfNeeded()
        report.otherDevices = otherDevices()
        if let firstError { throw firstError }
        return report
    }

    func prepare() throws {
        try FolderFiles.makeFolder(Self.changesFolder(ownFolder))
        try FolderFiles.makeFolder(filesFolder)

        let formatURL = root.appendingPathComponent("format.json")
        if FolderFiles.exists(formatURL) {
            let info = try JSONDecoder().decode(FormatInfo.self, from: FolderFiles.read(formatURL))
            if info.format > Self.format { throw FolderSyncError.newerFormat }
        } else {
            try FolderFiles.write(Self.encoder.encode(FormatInfo(format: Self.format)), to: formatURL)
        }

        // Название устройства обновляется раз в час: чаще незачем гонять файл через облако.
        let infoURL = ownFolder.appendingPathComponent("device.json")
        if (FolderFiles.modificationDate(infoURL) ?? .distantPast) < Date().addingTimeInterval(-3600) {
            let info = FolderSyncDevice(id: deviceId, name: deviceName, lastSeen: Date())
            try FolderFiles.write(Self.encoder.encode(info), to: infoURL)
        }
    }

    // MARK: Приём

    func pullChanges() async throws -> Int {
        var received = 0
        var firstError: (any Error)?
        for device in FolderFiles.list(devicesFolder) where device != deviceId {
            do {
                received += try await pull(device: device)
            } catch {
                // Файл ещё не доехал или испорчен: остальные устройства всё равно читаются.
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
        return received
    }

    private func pull(device: String) async throws -> Int {
        let folder = devicesFolder.appendingPathComponent(device, isDirectory: true)
        let cursorKey = "folder.cursor.\(device)"
        var cursor = try await database.folderSyncNumber(forKey: cursorKey) ?? 0
        let seqs = Set(FolderFiles.list(Self.changesFolder(folder)).compactMap(Self.seq(fromChange:)))
        var received = 0

        // Старые правки устройство заменило сжатой копией: она читается, если их уже нет.
        if let snapshot = FolderFiles.list(folder).compactMap(Self.seq(fromSnapshot:)).max(),
           snapshot > cursor, !(cursor + 1 ... snapshot).allSatisfy(seqs.contains) {
            let batch = try readBatch(folder.appendingPathComponent(Self.snapshotName(snapshot)))
            received += try await database.applyFolderEntries(batch.entries)
            cursor = snapshot
            try await database.setFolderSyncNumber(cursor, forKey: cursorKey)
        }

        for seq in seqs.sorted() where seq > cursor {
            // Пропуск в номерах: облако ещё не довезло файл. Дочитаем в следующий раз.
            guard seq == cursor + 1 else { break }
            let batch = try readBatch(Self.changesFolder(folder).appendingPathComponent(Self.changeName(seq)))
            received += try await database.applyFolderEntries(batch.entries)
            cursor = seq
            try await database.setFolderSyncNumber(cursor, forKey: cursorKey)
        }
        return received
    }

    private func readBatch(_ url: URL) throws -> FolderSyncBatch {
        let batch = try JSONDecoder().decode(FolderSyncBatch.self, from: FolderFiles.read(url))
        if batch.format > Self.format { throw FolderSyncError.newerFormat }
        return batch
    }

    /// Книги и картинки, которых здесь нет, но на которые ссылаются заметки.
    func pullFiles() async throws -> Int {
        let local = Set(FolderFiles.list(database.attachments.folder))
        let missing = Set(FolderFiles.list(filesFolder)).subtracting(local)
        let wanted = try await database.referencedAttachments(among: missing)
        guard !wanted.isEmpty else { return 0 }
        try FolderFiles.makeFolder(database.attachments.folder)
        var count = 0
        for name in wanted {
            do {
                try FolderFiles.copy(filesFolder.appendingPathComponent(name), to: database.attachments.url(for: name))
                count += 1
            } catch {
                // Большая книга может ещё качаться из облака, возьмём в следующий раз.
                continue
            }
        }
        return count
    }

    // MARK: Отправка

    func pushFiles() async throws -> Int {
        let remote = Set(FolderFiles.list(filesFolder))
        let missing = Set(FolderFiles.list(database.attachments.folder)).subtracting(remote)
        var count = 0
        for name in try await database.referencedAttachments(among: missing) {
            // Не скопировался один файл: строки всё равно уедут, файл попробуем в следующий раз.
            guard (try? FolderFiles.copy(database.attachments.url(for: name), to: filesFolder.appendingPathComponent(name))) != nil else {
                continue
            }
            count += 1
        }
        return count
    }

    func pushChanges() async throws -> Int {
        var seq = try await lastOwnSeq()
        var sent = 0
        while true {
            let (entries, changes) = try await database.folderSyncOutgoing(limit: Self.batchLimit)
            guard !changes.isEmpty else { break }
            if !entries.isEmpty {
                seq += 1
                let batch = FolderSyncBatch(format: Self.format, device: deviceId, seq: seq, entries: entries)
                try FolderFiles.write(
                    Self.encoder.encode(batch),
                    to: Self.changesFolder(ownFolder).appendingPathComponent(Self.changeName(seq))
                )
                try await database.setFolderSyncNumber(seq, forKey: "folder.ownSeq")
                sent += entries.count
            }
            try await database.markFolderSynced(changes)
        }
        return sent
    }

    /// Последний номер своих правок. Берётся и из папки: база могла вернуться из резервной копии.
    private func lastOwnSeq() async throws -> Int {
        let stored = try await database.folderSyncNumber(forKey: "folder.ownSeq") ?? 0
        let files = FolderFiles.list(Self.changesFolder(ownFolder)).compactMap(Self.seq(fromChange:)).max() ?? 0
        let snapshot = FolderFiles.list(ownFolder).compactMap(Self.seq(fromSnapshot:)).max() ?? 0
        return max(stored, files, snapshot)
    }

    /// Много файлов правок заменяются одной копией всей базы. Старые удаляются после того,
    /// как копия записана: устройство, которое их не дочитало, прочитает копию.
    func compactIfNeeded() async throws {
        let changes = Self.changesFolder(ownFolder)
        let seqs = FolderFiles.list(changes).compactMap(Self.seq(fromChange:))
        guard seqs.count > compactAfter, let last = seqs.max() else { return }
        let entries = try await database.folderSyncSnapshot()
        let batch = FolderSyncBatch(format: Self.format, device: deviceId, seq: last, entries: entries)
        try FolderFiles.write(Self.encoder.encode(batch), to: ownFolder.appendingPathComponent(Self.snapshotName(last)))
        for old in FolderFiles.list(ownFolder) {
            if let seq = Self.seq(fromSnapshot: old), seq < last {
                try? FolderFiles.remove(ownFolder.appendingPathComponent(old))
            }
        }
        for seq in seqs where seq <= last {
            try? FolderFiles.remove(changes.appendingPathComponent(Self.changeName(seq)))
        }
    }

    /// Другие устройства, которые пишут в эту папку.
    func otherDevices() -> [FolderSyncDevice] {
        FolderFiles.list(devicesFolder)
            .filter { $0 != deviceId }
            .compactMap { device in
                let url = devicesFolder.appendingPathComponent(device, isDirectory: true).appendingPathComponent("device.json")
                return (try? FolderFiles.read(url)).flatMap { try? Self.decoder.decode(FolderSyncDevice.self, from: $0) }
            }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Итог одного круга.
public struct FolderSyncReport: Sendable, Equatable {
    public var sent = 0
    public var received = 0
    public var filesSent = 0
    public var filesReceived = 0
    public var otherDevices: [FolderSyncDevice] = []

    public init() {}
}

/// Устройство, которое синхронизируется через ту же папку.
public struct FolderSyncDevice: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var lastSeen: Date

    public init(id: String, name: String, lastSeen: Date) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
    }
}

public enum FolderSyncError: LocalizedError {
    case newerFormat
    case noAccess

    public var errorDescription: String? {
        switch self {
        case .newerFormat: "В папке данные из более новой версии Lumen. Обновите приложение на этом устройстве."
        case .noAccess: "Нет доступа к папке синхронизации. Выберите её заново."
        }
    }
}

struct FolderSyncBatch: Codable {
    var format: Int
    var device: String
    var seq: Int
    var entries: [FolderSyncEntry]
}

private struct FormatInfo: Codable {
    var format: Int
    var app = "Lumen"
}

/// Чтение и запись через `NSFileCoordinator`: так облако не подменит файл посреди чтения,
/// а файл, которого ещё нет на устройстве (только в iCloud), сначала скачается.
enum FolderFiles {
    /// Имена в папке. Файлы iCloud, которые ещё не скачаны, на iPhone видны как `.имя.icloud`:
    /// они называются своими именами. Скрытые файлы пропускаются.
    static func list(_ folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                return String(name.dropFirst().dropLast(7))
            }
            return name.hasPrefix(".") ? nil : name
        }
    }

    static func exists(_ url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func makeFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func read(_ url: URL) throws -> Data {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func write(_ data: Data, to url: URL) throws {
        var result: Result<Void, any Error> = .success(())
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    /// Копирует файл через временный рядом с целью: недокачанный файл не займёт имя.
    static func copy(_ source: URL, to target: URL) throws {
        try? FileManager.default.startDownloadingUbiquitousItem(at: source)
        var result: Result<Void, any Error> = .success(())
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: source, options: [],
            writingItemAt: target, options: .forReplacing,
            error: &coordinationError
        ) { source, target in
            result = Result {
                let temporary = target.deletingLastPathComponent()
                    .appendingPathComponent(".\(UUID().uuidString)-\(target.lastPathComponent)")
                try FileManager.default.copyItem(at: source, to: temporary)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: temporary, to: target)
            }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    static func remove(_ url: URL) throws {
        var result: Result<Void, any Error> = .success(())
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            result = Result { try FileManager.default.removeItem(at: url) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}
