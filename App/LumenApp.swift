import LumenStorage
import LumenUI
import SwiftUI

@main
struct LumenApp: App {
    private let database: AppDatabase

    init() {
        do {
            database = try AppDatabase.makeDefault()
        } catch {
            // Без базы приложение работать не может. Позже здесь будет экран восстановления.
            fatalError("Не удалось открыть базу данных: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(database: database)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
    }
}
