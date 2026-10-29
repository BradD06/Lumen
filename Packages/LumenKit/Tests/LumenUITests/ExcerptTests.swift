import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct ExcerptTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func reference() -> ExcerptReference {
        ExcerptReference(sourceId: UUID(), highlightId: UUID(), label: "стр. 7")
    }

    @Test func firstExcerptReplacesTheEmptyParagraph() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()

        model.appendExcerpt(text: "Рукописи не горят", reference: reference())

        let top = model.children(of: nil)
        #expect(top.map(\.type) == [.excerpt, .paragraph])
        #expect(top.first?.text == "Рукописи не горят")
        #expect(top.last?.text.isEmpty == true)
    }

    @Test func excerptGoesBeforeTheTrailingEmptyParagraph() async throws {
        let page = try await db.createQuickNote("Заметки\nПервая мысль\n")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let first = try #require(model.children(of: nil).first)
        model.submit(first.id)

        model.appendExcerpt(text: "Цитата", reference: reference())
        model.appendExcerpt(text: "Ещё цитата", reference: reference())

        let top = model.children(of: nil)
        #expect(top.map(\.type) == [.paragraph, .excerpt, .excerpt, .paragraph])
        #expect(top.map(\.text) == ["Первая мысль", "Цитата", "Ещё цитата", ""])

        await model.flush()
        let saved = try await db.blocks(of: page.id).filter { $0.type == .excerpt }
        #expect(saved.compactMap(\.content.excerpt?.label) == ["стр. 7", "стр. 7"])
    }

    @Test func loadRunsOnce() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        model.appendExcerpt(text: "Цитата", reference: reference())
        // Встроенный редактор вызывает load ещё раз, когда появляется на экране.
        await model.load()
        #expect(model.children(of: nil).first?.type == .excerpt)
    }
}
