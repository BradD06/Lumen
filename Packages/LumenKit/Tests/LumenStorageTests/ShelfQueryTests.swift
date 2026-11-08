import Foundation
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
