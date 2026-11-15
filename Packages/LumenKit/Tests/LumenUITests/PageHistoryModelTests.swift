import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct PageHistoryModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func openingAPageRemembersItAndRestoreIsUndoable() async throws {
        let page = try await db.createQuickNote("История\nбыло")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let versions = try await db.pageVersions(of: page.id)
        #expect(versions.count == 1, "Страница при открытии уходит в историю")

        let id = model.blocks[0].id
        model.updateText(id, to: "стало")
        model.addBlock(below: id)
        await model.flush()

        let version = try #require(try await db.pageVersion(versions[0].id))
        await model.restoreVersion(title: version.title, blocks: try version.decodedBlocks())
        #expect(model.blocks.map(\.text) == ["было"])
        await model.flush()
        #expect(try await db.blocks(of: page.id).map(\.text) == ["было"])
        // Вид до отката тоже в истории.
        #expect(try await db.pageVersions(of: page.id).count == 2)

        model.undo()
        #expect(model.blocks.map(\.text) == ["стало", ""])
    }
}
