import LumenStorage
import LumenSync
import LumenUI
import SwiftUI
import Synchronization

@main
struct LumenApp: App {
    /// `nil`, если база не открылась: тогда вместо приложения экран восстановления.
    @State private var database = AppEnvironment.currentDatabase
    @State private var syncStatus = SyncStatus()

    var body: some Scene {
        WindowGroup {
            if let database {
                RootView(database: database)
                    .environment(syncStatus)
                    .task { await AppEnvironment.startSync(database: database, status: syncStatus) }
            } else {
                DatabaseRecoveryView(error: AppEnvironment.openingError ?? CocoaError(.fileReadUnknown)) { recovered in
                    AppEnvironment.useRecovered(recovered)
                    database = recovered
                }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
        .commands {
            EditorCommands()
            SoundCommands()
        }
    }
}

/// Одна база на весь процесс: её же использует быстрая заметка из Shortcuts,
/// поэтому открытые экраны сразу видят новую заметку.
enum AppEnvironment {
    private static let opening: Result<AppDatabase, any Error> = {
        do {
            // UI-тесты запускают приложение с чистой базой в памяти.
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                return .success(try AppDatabase.inMemory())
            }
            return .success(try AppDatabase.makeDefault())
        } catch {
            // Без базы приложение покажет экран восстановления, см. `DatabaseRecoveryView`.
            return .failure(error)
        }
    }()

    /// База, собранная на экране восстановления, если основная не открылась.
    private static let recovered = Mutex<AppDatabase?>(nil)

    static var currentDatabase: AppDatabase? {
        try? database()
    }

    static var openingError: (any Error)? {
        if case .failure(let error) = opening { error } else { nil }
    }

    static func database() throws -> AppDatabase {
        if let database = recovered.withLock({ $0 }) {
            return database
        }
        return try opening.get()
    }

    static func useRecovered(_ database: AppDatabase) {
        recovered.withLock { $0 = database }
    }
}

extension AppEnvironment {
    /// Синхронизация с iCloud, если сборка с ней: в Info.plist указан контейнер и есть права iCloud
    /// (нужен платный аккаунт разработчика, см. README). Иначе всё остаётся только на устройстве.
    @MainActor
    private static var sync: CloudSync?

    @MainActor
    static func startSync(database: AppDatabase, status: SyncStatus) async {
        guard sync == nil,
              !ProcessInfo.processInfo.arguments.contains("-uiTesting"),
              let container = CloudSync.configuredContainer else { return }
        let sync = CloudSync(database: database, containerIdentifier: container, status: status)
        self.sync = sync
        await sync.start()
    }
}
