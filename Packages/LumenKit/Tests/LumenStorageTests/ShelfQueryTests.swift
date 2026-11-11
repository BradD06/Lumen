import Foundation
import GRDB
import LumenCore
@testable import LumenStorage
import Testing

struct ShelfQueryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func readBooksStandFirstThenNewOnesAndTrashIsGone() async throws {
        let old = try await db.addSource(title: "Старая", format: .epub, file: "a.epub", originalName: "a.epub")
        let reading = try await db.addSource(title: "Читаю", format: .epub, file: "b.epub", originalName: "b.epub")
        let fresh = try await db.addSource(title: "Новая", format: .pdf, file: "c.pdf", originalName: "c.pdf")
        let trashed = try await db.addSource(title: "Удалена", format: .epub, file: "d.epub", originalName: "d.epub")
        try await db.saveReadingPosition(reading.id, locator: SourceLocator(section: 3), progress: 0.4)
        try await db.trashSource(trashed.id)

        let shelf = try await db.reader.read { try ShelfQuery.fetch($0) }
        #expect(shelf.map(\.id) == [reading.id, fresh.id, old.id])
        #expect(shelf.first?.progress == 0.4)
    }

    @Test func shelfKeepsToTheLimit() async throws {
        for index in 0..<5 {
            _ = try await db.addSource(title: "Книга \(index)", format: .epub, file: "\(index).epub", originalName: "\(index).epub")
        }
        let shelf = try await db.reader.read { try ShelfQuery.fetch($0, limit: 3) }
        #expect(shelf.count == 3)
    }
}

struct ShelfArrangeTests {
    @Test func arrangedOrderIsKeptAndOnlyMovedBookChanges() async throws {
        let db = try AppDatabase.inMemory()
        var ids: [UUID] = []
        for index in 0..<4 {
            ids.append(try await db.addSource(title: "Книга \(index)", format: .epub, file: "\(index).epub", originalName: "\(index).epub").id)
        }
        try await db.arrangeShelf(ids)
        let before = try await db.reader.read { try ShelfQuery.fetch($0) }
        #expect(ShelfSort.custom.sorted(before).map(\.id) == ids)

        // Последнюю книгу поставили первой.
        let moved = [ids[3], ids[0], ids[1], ids[2]]
        try await db.arrangeShelf(moved)
        let after = try await db.reader.read { try ShelfQuery.fetch($0) }
        #expect(ShelfSort.custom.sorted(after).map(\.id) == moved)
        let keyBefore = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.shelfOrder) })
        let changed = after.filter { keyBefore[$0.id] != $0.shelfOrder }.map(\.id)
        #expect(changed == [ids[3]])
    }
}

struct ShelvesTests {
    @Test func booksStandOnTheShelfOfTheirFolderAndTheRestOnTheCommonOne() async throws {
        let db = try AppDatabase.inMemory()
        let philosophy = try await db.createShelf(name: "Философия")
        let plain = try await db.createFolder(name: "Просто папка")
        let onShelf = try await db.addSource(title: "Сократ", format: .epub, file: "a.epub", originalName: "a.epub")
        let inFolder = try await db.addSource(title: "Отчёт", format: .pdf, file: "b.pdf", originalName: "b.pdf")
        let loose = try await db.addSource(title: "Роман", format: .epub, file: "c.epub", originalName: "c.epub")
        try await db.moveSource(onShelf.id, toFolder: philosophy.id)
        try await db.moveSource(inFolder.id, toFolder: plain.id)

        let groups = try await db.reader.read { try ShelfQuery.snapshot($0) }.groups
        #expect(groups.map(\.shelf?.name) == [nil, "Философия"])
        #expect(Set(groups[0].books.map(\.id)) == [inFolder.id, loose.id])
        #expect(groups[1].books.map(\.id) == [onShelf.id])
    }

    @Test func removingAShelfKeepsTheFolderAndItsBooks() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = try await db.createShelf(name: "Стихи")
        let book = try await db.addSource(title: "Блок", format: .epub, file: "a.epub", originalName: "a.epub")
        try await db.moveSource(book.id, toFolder: shelf.id)

        try await db.setFolderShelf(shelf.id, isShelf: false)

        let snapshot = try await db.reader.read { try ShelfQuery.snapshot($0) }
        #expect(snapshot.shelves.isEmpty)
        #expect(snapshot.groups.map(\.books.count) == [1])
        let folder = try await db.folder(shelf.id)
        #expect(folder?.isShelf == false)
        #expect(folder?.deletedAt == nil)
        #expect(snapshot.books.first?.folderId == shelf.id)
    }

    @Test func trashedShelvesAreHidden() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = try await db.createShelf(name: "Старое")
        try await db.trashFolder(shelf.id)
        let snapshot = try await db.reader.read { try ShelfQuery.snapshot($0) }
        #expect(snapshot.shelves.isEmpty)
    }
}

struct BookDuplicateMergeTests {
    @Test func duplicateGivesItsHighlightsNotesAndPlaceToTheOriginal() async throws {
        let db = try AppDatabase.inMemory()
        let original = try await db.addSource(title: "Война и мир", format: .epub, file: "a.epub", originalName: "war.epub")
        try await Task.sleep(for: .milliseconds(5))
        let copy = try await db.addSource(title: "Война и мир", format: .epub, file: "b.epub", originalName: "war.epub")
        let quote = try await db.addHighlight(Highlight(
            sourceId: copy.id, locator: SourceLocator(section: 2), text: "Всё смешалось", label: "Глава 1"
        ))
        let notes = try await db.notesPage(for: copy.id)
        try await db.saveReadingPosition(copy.id, locator: SourceLocator(section: 7), progress: 0.6)

        let merged = try await db.mergeDuplicateBooks()

        #expect(merged == 1)
        let books = try await db.reader.read { try ShelfQuery.fetch($0) }
        #expect(books.map(\.id) == [original.id])
        #expect(books.first?.progress == 0.6)
        let moved = try await db.reader.read { try Highlight.fetchOne($0, key: quote.id) }
        #expect(moved?.sourceId == original.id)
        let page = try await db.reader.read { try Page.fetchOne($0, key: notes.id) }
        #expect(page?.sourceId == original.id)
        #expect(page?.deletedAt == nil)
        #expect(try await db.mergeDuplicateBooks() == 0)
    }

    @Test func bookDroppedOnAnotherShelfMovesAndStandsInPlaceInOneStep() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = try await db.createShelf(name: "Поэзия")
        let a = try await db.addSource(title: "А", format: .epub, file: "a.epub", originalName: "a.epub")
        let b = try await db.addSource(title: "Б", format: .epub, file: "b.epub", originalName: "b.epub")
        try await db.moveSource(a.id, toFolder: shelf.id)

        try await db.placeOnShelf([b.id, a.id], shelf: shelf.id, arrivals: [b.id])

        let groups = try await db.reader.read { try ShelfQuery.snapshot($0) }.groups
        #expect(groups[1].shelf?.id == shelf.id)
        #expect(ShelfSort.custom.sorted(groups[1].books).map(\.id) == [b.id, a.id])
        #expect(groups[0].books.isEmpty)
    }
}

struct ShelfNotesTests {
    @Test func sortedNotesStandOnTheShelfWithTheirSheets() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = try await db.createShelf(name: "Учёба")
        let single = try await db.createPage(title: "Список литературы")
        let binder = try await db.createPage(title: "Конспекты", folderId: shelf.id)
        let inbox = try await db.createPage(title: "Мысль", inInbox: true)
        let child = try await db.createPage(title: "Подстраница", parentId: binder.id)
        let trashed = try await db.createPage(title: "Удалена")
        try await db.trashPage(trashed.id)

        // Две границы листов: у заметки три листа. Граница внутри блока не считается.
        let keys = SortKey.sequence(count: 3, after: "z")
        for key in keys.prefix(2) {
            try await db.saveBlock(Block(pageId: binder.id, type: .sheetBreak, sortKey: key))
        }

        let notes = try await db.reader.read { try ShelfQuery.notes($0) }
        let ids = Set(notes.map(\.id))
        #expect(ids.contains(single.id))
        #expect(ids.contains(binder.id))
        #expect(!ids.contains(inbox.id))
        #expect(!ids.contains(child.id))
        #expect(!ids.contains(trashed.id))
        #expect(notes.first { $0.id == binder.id }?.sheetCount == 3)
        #expect(notes.first { $0.id == single.id }?.sheetCount == 1)

        let groups = try await db.reader.read { try ShelfQuery.snapshot($0) }.groups
        #expect(groups.first { $0.shelf?.id == shelf.id }?.folders.map(\.id) == [binder.id])
        #expect(groups.first { $0.shelf == nil }?.singleSheets.map(\.id) == [single.id])
    }

    @Test func sheetPinnedToTheShelfIsRemembered() async throws {
        let db = try AppDatabase.inMemory()
        let page = try await db.createPage(title: "Позвонить научруку")
        try await db.setShelfPin(page.id, sheet: 0)
        #expect(try await db.page(page.id)?.shelfPin == 0)
        var notes = try await db.reader.read { try ShelfQuery.notes($0) }
        #expect(notes.first?.shelfPin == 0)

        try await db.setShelfPin(page.id, sheet: nil)
        notes = try await db.reader.read { try ShelfQuery.notes($0) }
        #expect(notes.first?.shelfPin == nil)
    }

    @Test func notebookStandsWithItsSheets() async throws {
        let db = try AppDatabase.inMemory()
        let notebook = try await db.createNotebook(title: "От руки")
        let notes = try await db.reader.read { try ShelfQuery.notes($0) }
        let entry = try #require(notes.first { $0.id == notebook.id })
        #expect(entry.isNotebook)
        #expect(entry.sheetCount >= 1)
    }
}
