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

@MainActor
struct PageEditorHistoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func typingIsUndoneAsOneStep() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)

        for prefix in ["П", "Пр", "При", "Привет"] {
            model.updateText(blockId, to: prefix)
        }
        #expect(model.canUndo)

        model.undo()
        #expect(model.blocks.map(\.text) == [""])
        #expect(model.canRedo)

        model.redo()
        #expect(model.blocks.map(\.text) == ["Привет"])
        await model.flush()
        #expect(try await db.blocks(of: page.id).map(\.text) == ["Привет"])
    }

    @Test func undoDeleteRestoresBlockInDatabase() async throws {
        let page = try await db.createQuickNote("Заметка\nпервый\nвторой")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let second = model.blocks[1].id

        model.deleteBlock(second)
        await model.flush()
        #expect(try await db.blocks(of: page.id).map(\.text) == ["первый"])

        model.undo()
        await model.flush()
        #expect(try await db.blocks(of: page.id).map(\.text) == ["первый", "второй"])

        model.redo()
        await model.flush()
        #expect(try await db.blocks(of: page.id).map(\.text) == ["первый"])
    }

    @Test func undoReturnSplit() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)

        model.updateText(blockId, to: "раз")
        model.submit(blockId)
        #expect(model.blocks.count == 2)

        model.undo()
        #expect(model.blocks.map(\.text) == ["раз"])
    }

    @Test func moveBlocks() async throws {
        let page = try await db.createQuickNote("Список\nа\nб\nв")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let ids = model.blocks.map(\.id)

        // Вниз: «а» на место «в» встаёт после него.
        model.moveBlock(ids[0], onto: ids[2])
        #expect(model.blocks.map(\.text) == ["б", "в", "а"])
        // Вверх: «а» на место «б» встаёт перед ним.
        model.moveBlock(ids[0], onto: ids[1])
        #expect(model.blocks.map(\.text) == ["а", "б", "в"])
        model.moveBlock(ids[2], by: -1)
        #expect(model.blocks.map(\.text) == ["а", "в", "б"])
        model.moveBlock(ids[0], by: -1)
        #expect(model.blocks.map(\.text) == ["а", "в", "б"], "Первый блок выше не поднимается")

        await model.flush()
        #expect(try await db.blocks(of: page.id).map(\.text) == ["а", "в", "б"])

        model.undo()
        #expect(model.blocks.map(\.text) == ["а", "б", "в"])
    }

    @Test func linkPageFromMention() async throws {
        let target = try await db.createPage(title: "Матанализ")
        let page = try await db.createPage(title: "План")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)

        model.updateText(blockId, to: "повторить [[Мат")
        model.linkPage(from: blockId, to: target.id)

        #expect(model.blocks.map(\.type) == [.paragraph, .page, .paragraph])
        #expect(model.blocks[0].text == "повторить")
        #expect(model.blocks[1].content.pageId == target.id)

        await model.flush()
        let backlinks = try await db.reader.read { try PageLinksSnapshot.fetch($0, pageId: target.id) }.backlinks
        #expect(backlinks.map(\.id) == [page.id])
    }

    @Test func linkReplacesEmptyMentionBlock() async throws {
        let target = try await db.createPage(title: "Цель")
        let page = try await db.createPage(title: "План")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)

        model.updateText(blockId, to: "@Це")
        model.linkPage(from: blockId, to: target.id)

        #expect(model.blocks.map(\.type) == [.page, .paragraph])
        #expect(model.blocks[0].id == blockId)
    }
}
