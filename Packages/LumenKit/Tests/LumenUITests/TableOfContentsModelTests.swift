import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct TableOfContentsModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func slashMenuMakesTableOfContentsAndParagraphBelow() async throws {
        let page = try await db.createQuickNote("Страница\n/огл")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let id = model.blocks[0].id
        model.setType(id, .tableOfContents)
        let block = try #require(model.findBlock(id))
        #expect(block.type == .tableOfContents)
        #expect(block.text.isEmpty)
        #expect(model.children(of: nil).last?.type == .paragraph, "Под оглавлением абзац, чтобы писать дальше")
        await model.flush()
        let saved = try await db.blocks(of: model.pageId).first { $0.id == id }
        #expect(saved?.type == .tableOfContents)
    }

    @Test func outlineFollowsHeadingsLive() async throws {
        let page = try await db.createQuickNote("Страница\nа")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let id = model.blocks[0].id
        model.setType(id, .tableOfContents)
        #expect(model.outline.isEmpty)
        let heading = model.insertBlock(after: id, type: .heading1, content: BlockContent(text: "Глава"))
        #expect(model.outline.map(\.title) == ["Глава"])
        #expect(model.outline.first?.anchorId == heading.id)
    }
}
