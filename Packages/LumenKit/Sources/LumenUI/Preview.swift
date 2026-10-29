import Foundation
import LumenCore
import LumenStorage

extension AppDatabase {
    /// База в памяти с несколькими страницами для превью SwiftUI.
    static func preview() -> AppDatabase {
        // swiftlint:disable:next force_try
        let database = try! AppDatabase.inMemory()
        Task {
            _ = try? await database.createQuickNote("Идея для курсовой\nСобрать литературу и составить план")
            _ = try? await database.createQuickNote("Купить тетради")
            let study = try? await database.createFolder(name: "Учёба", color: 0)
            _ = try? await database.createFolder(name: "Матанализ", parentId: study?.id, color: 4)
            _ = try? await database.createFolder(name: "Чтение", color: 2, position: LibraryPoint(x: 260, y: 60))
            _ = try? await database.createPage(title: "Лекция 1. Пределы", folderId: study?.id)
            _ = try? await database.createPage(title: "План на неделю", position: LibraryPoint(x: 90, y: 260))
        }
        return database
    }
}
