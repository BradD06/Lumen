import LumenStorage
import LumenSync
import LumenUI
import SwiftUI

@main
struct LumenApp: App {
    private let database = AppEnvironment.database
    #if os(macOS)
    @NSApplicationDelegateAdaptor(LumenAppDelegate.self) private var appDelegate
    #endif
    @State private var syncStatus = SyncStatus()

    var body: some Scene {
        WindowGroup {
            RootView(database: database)
                .environment(syncStatus)
                .task { await AppEnvironment.startSync(status: syncStatus) }
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
    static let database: AppDatabase = {
        do {
            // UI-тесты запускают приложение с чистой базой в памяти.
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                return try AppDatabase.inMemory()
            }
            return try AppDatabase.makeDefault()
        } catch {
            // Без базы приложение работать не может. Позже здесь будет экран восстановления.
            fatalError("Не удалось открыть базу данных: \(error)")
        }
    }()
}

extension AppEnvironment {
    /// Синхронизация с iCloud, если сборка с ней: в Info.plist указан контейнер и есть права iCloud
    /// (нужен платный аккаунт разработчика, см. README). Иначе всё остаётся только на устройстве.
    @MainActor
    private static var sync: CloudSync?

    @MainActor
    static func startSync(status: SyncStatus) async {
        guard sync == nil,
              !ProcessInfo.processInfo.arguments.contains("-uiTesting"),
              let container = CloudSync.configuredContainer else { return }
        let sync = CloudSync(database: database, containerIdentifier: container, status: status)
        self.sync = sync
        await sync.start()
    }
}
