import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct DatabaseBlockModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func openDatabaseBlock() async throws -> (PageEditorModel, UUID) {
        let page = try await db.createQuickNote("Страница\nа")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let id = model.blocks[0].id
        model.setType(id, .database)
        return (model, id)
    }

    @Test func slashMenuMakesEmptyDatabaseBlock() async throws {
        let (model, id) = try await openDatabaseBlock()
        #expect(model.findBlock(id)?.type == .database)
        #expect(model.findBlock(id)?.content.pageId == nil, "Сначала выбор базы")
        #expect(model.children(of: nil).last?.type == .paragraph, "Под базой абзац, чтобы писать дальше")
    }

    @Test func newInlineDatabaseLivesUnderThePage() async throws {
        let (model, id) = try await openDatabaseBlock()
        await model.createInlineDatabase(in: id)
        let databasePageId = try #require(model.findBlock(id)?.content.pageId)
        let databasePage = try await db.page(databasePageId)
        #expect(databasePage?.parentId == model.pageId)
        let snapshot = try await db.reader.read { try DataTableSnapshot.fetch($0, pageId: databasePageId) }
        #expect(snapshot.table != nil)

        await model.flush()
        let saved = try await db.blocks(of: model.pageId).first { $0.id == id }
        #expect(saved?.content.pageId == databasePageId)
        model.undo()
        #expect(model.findBlock(id)?.content.pageId == nil)
    }

    @Test func blockCanShowTasksOrAnExistingDatabase() async throws {
        let (model, id) = try await openDatabaseBlock()
        await model.attachTasksDatabase(id)
        let tasks = try await db.tasksDataTable()
        #expect(model.findBlock(id)?.content.pageId == tasks.pageId)

        let books = try await db.createDataTable(title: "Книги")
        model.attachDatabase(id, databasePageId: books.pageId)
        #expect(model.findBlock(id)?.content.pageId == books.pageId)
    }
}
