import Foundation
import GRDB
import Testing
import LumenCore
@testable import LumenStorage

struct BoardRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func snapshot() async throws -> BoardSnapshot {
        try await db.reader.read { try BoardSnapshot.fetch($0) }
    }

    private func book(_ title: String) async throws -> Source {
        try await db.addSource(title: title, format: .epub, file: "\(title).epub", originalName: "\(title).epub")
    }

    @Test func pinMoveAndUnpin() async throws {
        let page = try await db.createPage(title: "Эссе")
        try await db.pinToBoard([.page(page.id): LibraryPoint(x: 300, y: 200)])
        var board = try await snapshot()
        #expect(board.pins.map(\.item) == [.page(page.id)])

        try await db.moveBoardPin(.page(page.id), to: LibraryPoint(x: 500, y: 260))
        board = try await snapshot()
        #expect(board.pins.first?.point == LibraryPoint(x: 500, y: 260))
        #expect(board.pins.count == 1)

        try await db.unpinFromBoard([.page(page.id)])
        #expect(try await snapshot().pins.isEmpty)
        // Заметка осталась на месте.
        #expect(try await db.page(page.id) != nil)
    }

    @Test func relationsComeFromNotes() async throws {
        let master = try await book("Мастер и Маргарита")
        let idiot = try await book("Идиот")
        let essay = try await db.createPage(title: "Эссе о свободе")
        let questions = try await db.createPage(title: "Вопросы к семинару")

        // Блок «Страница», ссылка lumen:// на книгу в тексте и выписка.
        try await db.saveBlock(Block(pageId: questions.id, type: .page, content: BlockContent(pageId: essay.id), sortKey: "V"))
        let linkRun = TextRun("Идиот", link: LumenLink.source(idiot.id).url.absoluteString)
        try await db.saveBlock(Block(pageId: essay.id, content: BlockContent(runs: [TextRun("См. "), linkRun]), sortKey: "V"))
        let excerpt = ExcerptReference(sourceId: master.id, highlightId: UUID(), label: "стр. 289")
        try await db.saveBlock(Block(pageId: essay.id, type: .excerpt, content: BlockContent(runs: [TextRun("Рукописи не горят")], excerpt: excerpt), sortKey: "W"))
        let notes = try await db.notesPage(for: master.id)

        let board = try await snapshot()
        let relations = Set(board.relations.map { "\($0.from.boardKey)>\($0.to.boardKey):\($0.kind.rawValue)" })
        #expect(relations.contains("\(LibraryItemID.page(questions.id).boardKey)>\(LibraryItemID.page(essay.id).boardKey):link"))
        #expect(relations.contains("\(LibraryItemID.page(essay.id).boardKey)>\(LibraryItemID.source(idiot.id).boardKey):link"))
        #expect(relations.contains("\(LibraryItemID.page(essay.id).boardKey)>\(LibraryItemID.source(master.id).boardKey):excerpt"))
        #expect(relations.contains("\(LibraryItemID.page(notes.id).boardKey)>\(LibraryItemID.source(master.id).boardKey):notes"))
        #expect(board.unpinnedLinkedItems.isSuperset(of: [.page(essay.id), .page(questions.id), .source(master.id), .source(idiot.id)]))

        try await db.pinToBoard([
            .page(essay.id): LibraryPoint(x: 400, y: 300),
            .source(master.id): LibraryPoint(x: 150, y: 150),
            .source(idiot.id): LibraryPoint(x: 700, y: 150),
        ])
        let pinned = try await snapshot()
        #expect(pinned.threads.count == 2)
        #expect(pinned.threads.allSatisfy { $0.touches(.page(essay.id)) })
    }

    @Test func trashedItemsLeaveTheBoardAndComeBack() async throws {
        let page = try await db.createPage(title: "Черновик")
        try await db.pinToBoard([.page(page.id): LibraryPoint(x: 200, y: 200)])
        try await db.trashPage(page.id)
        #expect(try await snapshot().pins.isEmpty)
        try await db.restorePage(page.id)
        #expect(try await snapshot().pins.count == 1)

        try await db.trashPage(page.id)
        try await db.deleteForever(.page(page.id))
        let rows = try await db.reader.read { try BoardPin.fetchCount($0) }
        #expect(rows == 0)
    }

    @Test func pinningOneItemPlacesItBesideItsLinks() async throws {
        let master = try await book("Мастер и Маргарита")
        let notes = try await db.notesPage(for: master.id)
        try await db.pinToBoard([.source(master.id): LibraryPoint(x: 800, y: 600)])

        #expect(try await db.pinToBoard(.page(notes.id)))
        #expect(try await db.pinToBoard(.page(notes.id)) == false)
        let board = try await snapshot()
        let pin = try #require(board.pins.first(where: { $0.item == .page(notes.id) }))
        #expect(abs(pin.x - 800) <= BoardLayout.cellWidth + 1)
        #expect(abs(pin.y - 600) <= BoardLayout.cellHeight + 1)
    }

    @Test func folderStandsInForItsNotes() async throws {
        let folder = try await db.createFolder(name: "Конспекты")
        let master = try await book("Мастер и Маргарита")
        let summary = try await db.createPage(title: "Конспект", folderId: folder.id)
        let excerpt = ExcerptReference(sourceId: master.id, highlightId: UUID(), label: "стр. 12")
        try await db.saveBlock(Block(pageId: summary.id, type: .excerpt, content: BlockContent(runs: [TextRun("Цитата")], excerpt: excerpt), sortKey: "V"))

        try await db.pinToBoard([
            .folder(folder.id): LibraryPoint(x: 200, y: 200),
            .source(master.id): LibraryPoint(x: 600, y: 200),
        ])
        let board = try await snapshot()
        #expect(board.threads.count == 1)
        #expect(board.threads.first?.touches(.folder(folder.id)) == true)
        #expect(board.folderCounts[folder.id] == 1)
    }

    @Test func boardPinsAreSynced() async throws {
        let page = try await db.createPage(title: "Эссе")
        try await db.pinToBoard([.page(page.id): LibraryPoint(x: 300, y: 200)])
        let logged = try await db.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncChange WHERE tableName = 'boardPin' AND recordId = ?", arguments: [page.id])
        }
        #expect(logged == 1)
        let entries = try await db.folderSyncSnapshot()
        #expect(entries.contains { $0.id.table == .boardPin && $0.id.id == page.id })
    }
}
