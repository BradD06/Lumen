import Foundation
import GRDB
import LumenStorage
import Observation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

private let folderSyncLog = Logger(subsystem: "io.github.bradd06.lumen", category: "folder-sync")

/// Синхронизация через папку, которую выбрали в настройках (обычно iCloud Drive).
/// Помнит папку между запусками (закладка с доступом к ней), запускает круг синхронизации
/// при запуске, через несколько секунд после правки и раз в полминуты, пока приложение открыто.
@MainActor
@Observable
public final class FolderSyncController {
    static let bookmarkKey = "sync.folderBookmark"
    static let deviceKey = "sync.deviceId"
    /// Сколько ждать после правки: правки подряд уезжают одним файлом.
    static let debounce: Duration = .seconds(3)
    static let interval: Duration = .seconds(30)

    /// Как называется выбранная папка, например «iCloud Drive/Lumen Sync». `nil`, если синхронизация выключена.
    public private(set) var folderName: String?
    /// Другие устройства в той же папке.
    public private(set) var otherDevices: [FolderSyncDevice] = []

    public var isOn: Bool { engine != nil }

    private let database: AppDatabase
    private let status: SyncStatus
    private var engine: FolderSyncEngine?
    /// Выбранная папка, к которой открыт доступ. Закрывается при выключении.
    private var pickedFolder: URL?
    private var loop: Task<Void, Never>?
    private var observation: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var isRunning = false
    private var runAgain = false

    public init(database: AppDatabase, status: SyncStatus) {
        self.database = database
        self.status = status
    }

    /// При запуске приложения: если папку уже выбирали, синхронизация включается сама.
    public func start() {
        guard engine == nil, let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try Self.resolve(bookmark, isStale: &isStale)
            _ = url.startAccessingSecurityScopedResource()
            if isStale, let fresh = try? Self.bookmark(for: url) {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
            turnOn(url)
        } catch {
            folderSyncLog.error("Folder bookmark failed: \(String(describing: error), privacy: .public)")
            status.state = .failed(FolderSyncError.noAccess.localizedDescription)
        }
    }

    /// Папку выбрали в системном окне. Всё, что есть на устройстве, уедет в неё, а из неё придёт чужое.
    public func choose(_ url: URL) async {
        let isAccessing = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try Self.bookmark(for: url)
            stop()
            try await database.resetFolderSyncState()
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            turnOn(url)
        } catch {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
            status.state = .failed(error.localizedDescription)
        }
    }

    /// Синхронизация выключается, файлы в папке остаются: включить снова можно в любой момент.
    public func turnOff() {
        stop()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        status.state = .notConfigured
    }

    /// Круг синхронизации сейчас: по кнопке, при открытии приложения и при уходе в фон.
    public func syncNow() {
        guard let engine else { return }
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        if case .upToDate = status.state {} else { status.state = .syncing }
        Task {
            do {
                let report = try await engine.sync()
                // Книга, добавленная на двух устройствах, после синхронизации стояла бы дважды.
                let merged = (try? await database.mergeDuplicateBooks()) ?? 0
                if merged > 0 {
                    folderSyncLog.info("Folder sync: merged \(merged) duplicate books")
                }
                otherDevices = report.otherDevices
                status.state = .upToDate(Date())
                if report.sent + report.received + report.filesSent + report.filesReceived > 0 {
                    folderSyncLog.info("Folder sync: sent \(report.sent), received \(report.received), files \(report.filesSent)/\(report.filesReceived)")
                }
            } catch {
                folderSyncLog.error("Folder sync failed: \(String(describing: error), privacy: .public)")
                status.state = .failed(error.localizedDescription)
            }
            isRunning = false
            if runAgain, self.engine != nil {
                runAgain = false
                syncNow()
            }
        }
    }

    // MARK: Внутреннее

    private func turnOn(_ picked: URL) {
        pickedFolder = picked
        let root = FolderSyncEngine.dataFolder(in: picked)
        engine = FolderSyncEngine(database: database, root: root, deviceId: Self.deviceId, deviceName: Self.deviceName)
        folderName = Self.displayName(for: root)
        status.state = .syncing
        observeLocalChanges()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.syncNow()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func stop() {
        loop?.cancel()
        observation?.cancel()
        debounceTask?.cancel()
        loop = nil
        observation = nil
        debounceTask = nil
        engine = nil
        folderName = nil
        otherDevices = []
        pickedFolder?.stopAccessingSecurityScopedResource()
        pickedFolder = nil
    }

    /// Правка на этом устройстве: круг через пару секунд, чтобы правки подряд уехали вместе.
    private func observeLocalChanges() {
        let observation = ValueObservation.tracking { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(version), 0) FROM syncChange") ?? 0
        }
        let reader = database.reader
        self.observation = Task { [weak self] in
            do {
                for try await _ in observation.values(in: reader).dropFirst() {
                    self?.scheduleSoon()
                }
            } catch {
                folderSyncLog.error("Folder sync observation failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func scheduleSoon() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// Своё имя папки на каждой установке приложения: в неё пишет только это устройство.
    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.model
        #endif
    }

    static func bookmark(for url: URL) throws -> Data {
        #if os(macOS)
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        #endif
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ bookmark: Data, isStale: inout Bool) throws -> URL {
        #if os(macOS)
        if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return url
        }
        #endif
        return try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// «iCloud Drive/Lumen Sync» вместо длинного системного пути.
    static func displayName(for url: URL) -> String {
        let parts = url.standardizedFileURL.pathComponents
        if let index = parts.lastIndex(of: "com~apple~CloudDocs") {
            return (["iCloud Drive"] + parts[(index + 1)...]).joined(separator: "/")
        }
        return parts.suffix(2).joined(separator: "/")
    }
}
