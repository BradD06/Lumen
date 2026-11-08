import LumenStorage
import LumenSync
import LumenUI
import SwiftUI
import Synchronization

@main
struct LumenApp: App {
    /// `nil`, если база не открылась: тогда вместо приложения экран восстановления.
    @State private var database = AppEnvironment.currentDatabase
    #if os(macOS)
    @NSApplicationDelegateAdaptor(LumenAppDelegate.self) private var appDelegate
    #endif
    @State private var syncStatus = SyncStatus()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let database {
                RootView(database: database)
                    .lumenThemed()
                    .environment(syncStatus)
                    .environment(AppEnvironment.folderSync(database: database, status: syncStatus))
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
        // Открыли приложение или ушли из него: правки сразу уезжают в папку и приходят из неё.
        .onChange(of: scenePhase) { _, phase in
            if phase != .inactive { AppEnvironment.folderSyncController?.syncNow() }
        }
        .commands {
            EditorCommands()
            SoundCommands()
        }
    }
}

#if os(macOS)
/// Книги, которые открыли в Lumen из Finder («Открыть с помощью», перетаскивание на иконку в Dock),
/// и ссылки lumen:// приходят сюда, даже если окна ещё нет. Окно разберёт их, когда появится.
@MainActor
final class LumenAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        IncomingOpenQueue.shared.receive(urls)
    }
}
#endif

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
    /// Синхронизация с iCloud через CloudKit, если сборка с ней: в Info.plist указан контейнер и есть права
    /// iCloud (нужен платный аккаунт разработчика, см. README). Иначе синхронизация через папку,
    /// которую выбирают в «Данные и копии», или всё остаётся только на устройстве.
    @MainActor
    private static var sync: CloudSync?

    /// Синхронизация через выбранную папку (iCloud Drive). Нет в сборке с CloudKit и в UI-тестах.
    @MainActor
    private(set) static var folderSyncController: FolderSyncController?

    @MainActor
    static func folderSync(database: AppDatabase, status: SyncStatus) -> FolderSyncController? {
        guard CloudSync.configuredContainer == nil,
              !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return nil }
        if let folderSyncController { return folderSyncController }
        let controller = FolderSyncController(database: database, status: status)
        folderSyncController = controller
        return controller
    }

    @MainActor
    static func startSync(database: AppDatabase, status: SyncStatus) async {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        guard let container = CloudSync.configuredContainer else {
            folderSync(database: database, status: status)?.start()
            return
        }
        guard sync == nil else { return }
        let sync = CloudSync(database: database, containerIdentifier: container, status: status)
        self.sync = sync
        await sync.start()
    }
}
