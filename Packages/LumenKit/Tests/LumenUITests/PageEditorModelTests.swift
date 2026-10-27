import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct PageEditorModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    /// Ожидание дольше задержки автосохранения.
    private func waitForAutosave() async throws {
        try await Task.sleep(for: .milliseconds(900))
    }

    @Test func titleAndTextAreAutosaved() async throws {
        let page = try await db.createPage(inInbox: true)
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)

        model.setTitle("Лекция 1")
        model.updateText(blockId, to: "Производная это скорость изменения")
        try await waitForAutosave()

        #expect(try await db.page(page.id)?.title == "Лекция 1")
        #expect(try await db.blocks(of: page.id).map(\.text) == ["Производная это скорость изменения"])
    }

    @Test func fastTypingKeepsTheLastValue() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()

        for prefix in ["К", "Ко", "Кон", "Конс", "Конспект"] {
            model.setTitle(prefix)
            try await Task.sleep(for: .milliseconds(120))
        }
        try await waitForAutosave()

        #expect(try await db.page(page.id)?.title == "Конспект")
    }

    @Test func editsDuringASaveAreNotLost() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)

        model.updateText(blockId, to: "Первая")
        // Правка примерно в момент, когда срабатывает таймер первой записи.
        try await Task.sleep(for: .milliseconds(360))
        model.updateText(blockId, to: "Первая и вторая")
        try await waitForAutosave()

        #expect(try await db.blocks(of: page.id).map(\.text) == ["Первая и вторая"])
    }

    @Test func returnCreatesSavedBlocks() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)

        model.updateText(blockId, to: "- молоко")
        model.updateText(blockId, to: "молоко\nхлеб")
        await model.flush()

        let saved = try await db.blocks(of: page.id)
        #expect(saved.map(\.text) == ["молоко", "хлеб"])
        #expect(saved.map(\.type) == [.bulletedList, .bulletedList])
    }

    @Test func deletedBlockStaysDeleted() async throws {
        let page = try await db.createQuickNote("Заметка\nпервый\nвторой")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let second = model.blocks[1].id

        model.updateText(second, to: "второй!")
        model.deleteBlock(second)
        await model.flush()
        try await waitForAutosave()

        #expect(try await db.blocks(of: page.id).map(\.text) == ["первый"])
    }

    @Test func flushSavesImmediately() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()

        model.setTitle("Сразу")
        await model.flush()

        #expect(try await db.page(page.id)?.title == "Сразу")
    }
}
