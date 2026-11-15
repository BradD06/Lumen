import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct PageTemplateModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func blankPageTakesTheTemplate() async throws {
        let page = try await db.createQuickNote("Лекция 5")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        #expect(model.isBlankPage)

        let template = PageTemplate.builtIn[0]
        model.applyTemplate(template)
        #expect(!model.isBlankPage)
        #expect(model.blocks.count == template.blocks.blocks.count)
        #expect(model.blocks.first?.type == .heading2)
        #expect(model.page?.icon == template.icon)
        #expect(model.focusRequest.flatMap { model.findBlock($0)?.type } == .paragraph)
        await model.flush()
        #expect(try await db.blocks(of: page.id).count == template.blocks.blocks.count)

        model.undo()
        #expect(model.isBlankPage)
    }

    @Test func templateGoesToTheEndOfAWrittenPage() async throws {
        let page = try await db.createQuickNote("Заметка\nуже есть текст")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        #expect(!model.isBlankPage)
        model.applyTemplate(PageTemplate.builtIn[1])
        #expect(model.children(of: nil).first?.text == "уже есть текст")
        #expect(model.children(of: nil).count == 1 + PageTemplate.builtIn[1].blocks.rootIds.count)

        await model.saveAsTemplate()
        let saved = try await db.pageTemplates()
        #expect(saved.map(\.title) == ["Заметка"])
        #expect(saved.first?.blocks.blocks.count == model.blocks.count)
    }
}
