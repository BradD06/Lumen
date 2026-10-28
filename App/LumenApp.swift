import LumenStorage
import LumenUI
import SwiftUI

@main
struct LumenApp: App {
    private let database = AppEnvironment.database

    var body: some Scene {
        WindowGroup {
            RootView(database: database)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
        .commands {
            EditorCommands()
        }
    }
}

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
