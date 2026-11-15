import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct MarkdownPasteModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func openPage(_ body: String = "") async throws -> (PageEditorModel, UUID) {
        let page = try await db.createQuickNote("Страница\nа")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let id = model.blocks[0].id
        model.updateText(id, to: body)
        return (model, id)
    }

    @Test func pasteIntoEmptyParagraphBuildsBlocks() async throws {
        let (model, id) = try await openPage()
        model.updateMarkup(id, to: "# Заголовок\n- один\n  - вложенный\n- два\n| a | b |\n|---|---|\n| 1 | 2 |")
        let top = model.children(of: nil)
        #expect(top.map(\.type) == [.heading1, .bulletedList, .bulletedList, .table, .paragraph])
        #expect(top[0].id == id, "Пустой абзац сам становится первым блоком")
        #expect(top[0].text == "Заголовок")
        let nested = model.children(of: top[1].id)
        #expect(nested.map(\.text) == ["вложенный"])
        #expect(top[3].content.table?.cell(1, 1).text == "2")
        #expect(model.focusRequest == top[4].id, "После таблицы курсор в новом абзаце")

        await model.flush()
        let saved = try await db.blocks(of: model.pageId)
        #expect(saved.count == 6)
        model.undo()
        #expect(model.children(of: nil).count == 1)
        #expect(model.findBlock(id)?.type == .paragraph)
        #expect(model.findBlock(id)?.text == "")
    }

    @Test func pasteInTheMiddleKeepsTextAround() async throws {
        let (model, id) = try await openPage("до после")
        model.updateMarkup(id, to: "до **x**\n## Глава\n- пункт после")
        let top = model.children(of: nil)
        #expect(top.map(\.type) == [.paragraph, .heading2, .bulletedList])
        #expect(top[0].content.runs == [TextRun("до "), TextRun("x", marks: [.bold])])
        #expect(top[2].text == "пункт после")
        #expect(model.focusRequest == top[2].id)
    }

    @Test func plainLinesStillSplitAsBefore() async throws {
        let (model, id) = try await openPage("а")
        model.setType(id, .bulletedList)
        model.updateMarkup(id, to: "раз\nдва\nтри")
        let top = model.children(of: nil)
        #expect(top.map(\.type) == [.bulletedList, .bulletedList, .bulletedList])
        #expect(top.map(\.text) == ["раз", "два", "три"])
    }

    @Test func pasteEndingWithNewLinePutsRestOnItsOwnLine() async throws {
        let (model, id) = try await openPage("хвост")
        model.updateMarkup(id, to: "- один\n- два\nхвост")
        let top = model.children(of: nil)
        #expect(top.map(\.type) == [.bulletedList, .bulletedList, .paragraph])
        #expect(top.map(\.text) == ["один", "два", "хвост"])
    }
}
