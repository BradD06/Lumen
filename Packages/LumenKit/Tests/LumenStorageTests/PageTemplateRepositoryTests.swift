import Foundation
import Testing
import LumenCore
@testable import LumenStorage

struct PageTemplateRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func templatesAreSavedListedSyncedAndDeleted() async throws {
        let page = try await db.createQuickNote("Конспект\nстрока")
        let blocks = try await db.blocks(of: page.id)
        let saved = try await db.savePageTemplate(title: "  Мой конспект ", icon: "🧪", blocks: BlockClipboard(blocks: blocks))
        let other = try await db.savePageTemplate(title: "", icon: nil, blocks: BlockClipboard(blocks: blocks))

        let templates = try await db.pageTemplates()
        #expect(templates.map(\.title) == ["Без названия", "Мой конспект"])
        #expect(templates.first { $0.id == saved.id }?.blocks.blocks.map(\.text) == ["строка"])

        let logged = try await db.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncChange WHERE tableName = 'pageTemplate'") ?? 0
        }
        #expect(logged == 2, "Свои шаблоны ездят между устройствами")

        try await db.deletePageTemplate(other.id)
        #expect(try await db.pageTemplates().map(\.id) == [saved.id])
    }
}
