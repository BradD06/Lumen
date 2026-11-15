import Foundation
import Testing
import LumenCore
@testable import LumenStorage

struct PageVersionRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func versionsAreSavedOnlyWhenDueAndChanged() async throws {
        let page = try await db.createQuickNote("Конспект\nпервая строка")
        var blocks = try await db.blocks(of: page.id)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(try await db.savePageVersion(pageId: page.id, title: "Конспект", blocks: blocks, now: start))
        // Раньше десяти минут новой версии нет.
        blocks[0].text = "вторая"
        #expect(try await !db.savePageVersion(pageId: page.id, title: "Конспект", blocks: blocks, now: start.addingTimeInterval(60)))
        // Через десять минут есть, но только если что-то поменялось.
        #expect(try await db.savePageVersion(pageId: page.id, title: "Конспект", blocks: blocks, now: start.addingTimeInterval(700)))
        #expect(try await !db.savePageVersion(pageId: page.id, title: "Конспект", blocks: blocks, now: start.addingTimeInterval(1400)))
        // `force` не ждёт десяти минут.
        #expect(try await db.savePageVersion(pageId: page.id, title: "Новое название", blocks: blocks, force: true, now: start.addingTimeInterval(1450)))

        let versions = try await db.pageVersions(of: page.id)
        #expect(versions.map(\.title) == ["Новое название", "Конспект", "Конспект"])
        let first = try #require(try await db.pageVersion(versions[2].id))
        #expect(try first.decodedBlocks().first?.text == "первая строка")
    }

    @Test func versionsGoWithThePage() async throws {
        let page = try await db.createQuickNote("Черновик\nтекст")
        let blocks = try await db.blocks(of: page.id)
        try await db.savePageVersion(pageId: page.id, title: "Черновик", blocks: blocks)
        try await db.trashPage(page.id)
        try await db.emptyTrash()
        let count = try await db.reader.read { try PageVersion.fetchCount($0) }
        #expect(count == 0)
    }
}
