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
