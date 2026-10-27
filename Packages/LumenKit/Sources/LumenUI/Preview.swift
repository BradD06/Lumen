import Foundation
import LumenStorage

extension AppDatabase {
    /// База в памяти с несколькими страницами для превью SwiftUI.
    static func preview() -> AppDatabase {
        // swiftlint:disable:next force_try
        let database = try! AppDatabase.inMemory()
        Task {
            _ = try? await database.createQuickNote("Идея для курсовой\nСобрать литературу и составить план")
            _ = try? await database.createQuickNote("Купить тетради")
            let study = try? await database.createPage(title: "Учёба")
            _ = try? await database.createPage(title: "Матанализ", parentId: study?.id)
            _ = try? await database.createPage(title: "История", parentId: study?.id)
            _ = try? await database.createPage(title: "Чтение")
        }
        return database
    }
}
