import Foundation
import GRDB
import Testing
import LumenCore
@testable import LumenStorage

struct NotebookRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func notebookHasOneSheetBlock() async throws {
        let page = try await db.createNotebook(title: "Конспект")
        #expect(page.pageKind == .notebook)
        #expect(page.isNotebook)

        let stored = try #require(try await db.page(page.id))
        #expect(stored.pageKind == .notebook)
        #expect(stored.icon == "✍️")

        let blocks = try await db.blocks(of: page.id)
        #expect(blocks.count == 1)
        #expect(blocks.first?.type == .drawing)
        #expect(blocks.first?.content.sheetCount == 1)
        #expect(blocks.first?.content.paper == .lined)
        #expect(blocks.first?.content.paperTone == .white)
    }

    @Test func notebookGoesToTheLibraryFolder() async throws {
        let folder = try await db.createFolder(name: "Учёба")
        let page = try await db.createNotebook(folderId: folder.id, position: LibraryPoint(x: 10, y: 20))
        let library = try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: folder.id) }
        #expect(library.pages.map(\.page.id) == [page.id])
    }

    @Test func drawingDataIsStoredAndCopied() async throws {
        let page = try await db.createPage(title: "Схема")
        var block = try #require(try await db.blocks(of: page.id).first)
        let strokes = Data((0..<4096).map { UInt8($0 % 251) })
        block.type = .drawing
        block.drawing = strokes
        block.content.drawingHeight = 380
        try await db.saveBlock(block)

        let saved = try #require(try await db.blocks(of: page.id).first)
        #expect(saved.drawing == strokes)
        #expect(saved.content.drawingHeight == 380)

        let copy = try await db.duplicatePage(page.id)
        let copied = try #require(try await db.blocks(of: copy.id).first)
        #expect(copied.drawing == strokes)
        #expect(copied.id != saved.id)
    }

    @Test func searchStillFindsTextNextToADrawing() async throws {
        let page = try await db.createQuickNote("Лекция\n\nтеорема Пифагора")
        var block = try #require(try await db.blocks(of: page.id).first)
        let drawingBlock = Block(pageId: page.id, type: .drawing, drawing: Data([7, 7, 7]), sortKey: "zz")
        block.text = "теорема Пифагора и чертёж"
        try await db.saveBlock(block)
        try await db.saveBlock(drawingBlock)

        let body = try await db.reader.read { db in
            try String.fetchOne(db, sql: "SELECT body FROM pageSearch WHERE pageId = ?", arguments: [page.id.uuidString])
        }
        #expect(body == "теорема Пифагора и чертёж")
    }
}
