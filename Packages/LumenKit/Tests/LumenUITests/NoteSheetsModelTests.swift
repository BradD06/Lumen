import Foundation
import LumenCore
import LumenStorage
@testable import LumenUI
import Testing

@MainActor
struct NoteSheetsModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func openPage() async throws -> PageEditorModel {
        let page = try await db.createPage(title: "Конспект")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        return model
    }

    @Test func addSheetPutsAnEmptySheetAfterTheLast() async throws {
        let model = try await openPage()
        #expect(model.sheetCount == 1)
        let first = try #require(model.blocks.first?.id)
        model.updateText(first, to: "Первый лист")

        model.addSheet()
        #expect(model.sheetCount == 2)
        let sheets = model.sheets
        #expect(sheets[0].blocks.map(\.text) == ["Первый лист"])
        #expect(sheets[1].blocks.count == 1)
        #expect(model.focusRequest == sheets[1].blocks.first?.id)

        await model.flush()
        let saved = try await db.blocks(of: model.pageId)
        #expect(saved.filter { $0.type == .sheetBreak }.count == 1)

        model.undo()
        #expect(model.sheetCount == 1)
    }

    @Test func backspaceInAnEmptySheetRemovesIt() async throws {
        let model = try await openPage()
        let first = try #require(model.blocks.first?.id)
        model.updateText(first, to: "Текст")
        model.addSheet()
        let empty = try #require(model.sheets[1].blocks.first?.id)

        #expect(model.backspaceInEmptyBlock(empty))
        #expect(model.sheetCount == 1)
        #expect(model.focusRequest == first)
    }

    @Test func sheetsSwapPlacesAndMerge() async throws {
        let model = try await openPage()
        let first = try #require(model.blocks.first?.id)
        model.updateText(first, to: "А")
        model.addSheet()
        let second = try #require(model.sheets[1].blocks.first?.id)
        model.updateText(second, to: "Б")

        model.moveSheet(1, by: -1)
        #expect(model.sheets.map { $0.blocks.map(\.text) } == [["Б"], ["А"]])

        model.mergeSheetWithPrevious(1)
        #expect(model.sheetCount == 1)
        #expect(model.sheets[0].blocks.map(\.text) == ["Б", "А"])
    }

    @Test func deletingASheetTakesItsTextAlong() async throws {
        let model = try await openPage()
        let first = try #require(model.blocks.first?.id)
        model.updateText(first, to: "Оставить")
        model.addSheet()
        let second = try #require(model.sheets[1].blocks.first?.id)
        model.updateText(second, to: "Удалить")

        model.deleteSheet(1)
        #expect(model.sheetCount == 1)
        #expect(model.blocks.map(\.text) == ["Оставить"])

        // Удалили первый лист: второй становится первым, граница пропадает.
        model.addSheet()
        let next = try #require(model.sheets[1].blocks.first?.id)
        model.updateText(next, to: "Второй")
        model.deleteSheet(0)
        #expect(model.sheetCount == 1)
        #expect(model.blocks.map(\.text) == ["Второй"])
    }

    @Test func longNoteIsLaidOutOnSheets() async throws {
        let model = try await openPage()
        let first = try #require(model.blocks.first?.id)
        let paragraph = String(repeating: "Длинный старый конспект без листов. ", count: 10)
        var last = first
        model.updateText(first, to: paragraph)
        for _ in 0..<30 {
            model.addBlock(below: last)
            let id = try #require(model.focusRequest)
            model.updateText(id, to: paragraph)
            last = id
        }
        #expect(model.sheetCount == 1)
        #expect(model.hasOverfullSheets)

        model.paginateAll()
        #expect(model.sheetCount > 1)
        #expect(!model.hasOverfullSheets)
        #expect(model.blocks.filter { $0.type != .sheetBreak }.count == 31)
    }

    @Test func pinnedSheetIsSaved() async throws {
        let model = try await openPage()
        model.addSheet()
        model.pinSheet(1)
        #expect(model.pinnedSheet == 1)
        try await Task.sleep(for: .milliseconds(600))
        #expect(try await db.page(model.pageId)?.shelfPin == 1)
    }
}
