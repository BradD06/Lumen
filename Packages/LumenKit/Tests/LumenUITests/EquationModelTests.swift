import CoreGraphics
import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

/// Блок «Формула» и формулы в строке: правка, Return, оформление и PDF.
@MainActor
struct EquationModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func openPage() async throws -> (PageEditorModel, UUID) {
        let page = try await db.createQuickNote("Страница\nа")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        return (model, model.blocks[0].id)
    }

    @Test func returnLeavesEquationForNewParagraph() async throws {
        let (model, id) = try await openPage()
        model.setType(id, .equation)
        model.updateText(id, to: "x^2")
        let before = model.children(of: nil).count
        model.submit(id)

        let top = model.children(of: nil)
        #expect(top.count == before + 1)
        let index = try #require(top.firstIndex { $0.id == id })
        #expect(top[index].type == .equation)
        #expect(top[index].text == "x^2")
        #expect(top[index + 1].type == .paragraph)
        #expect(top[index + 1].text.isEmpty)
        #expect(model.focusRequest == top[index + 1].id)

        // Второй Return не плодит пустые абзацы: курсор встаёт в тот же.
        model.submit(id)
        #expect(model.children(of: nil).count == before + 1)
    }

    @Test func newlineFromKeyboardLeavesEquationAndPasteStaysOneFormula() async throws {
        let (model, id) = try await openPage()
        model.setType(id, .equation)
        model.updateText(id, to: "\\sqrt{x}")
        let before = model.children(of: nil).count
        // Return на iPhone приходит переводом строки в тексте поля.
        model.updateText(id, to: "\\sqrt{x}\n")
        #expect(model.findBlock(id)?.text == "\\sqrt{x}")
        #expect(model.children(of: nil).count == before + 1)

        // Вставка в несколько строк остаётся одной формулой.
        model.updateText(id, to: "a\n+ b")
        #expect(model.findBlock(id)?.text == "a + b")
        #expect(model.findBlock(id)?.type == .equation)
        #expect(model.children(of: nil).count == before + 1)
    }

    @Test func equationHasNoInlineFormatting() async throws {
        let (model, id) = try await openPage()
        model.setType(id, .equation)
        model.updateText(id, to: "a*b*c")
        #expect(model.wholeText(of: id) == nil)
        #expect(model.findBlock(id)?.content.runs == [TextRun("a*b*c")])
    }

    @Test func inlineMathFromFormatAction() async throws {
        let (model, id) = try await openPage()
        model.updateMarkup(id, to: "x^2 растёт")
        model.apply(.math, to: TextSelectionInfo(blockId: id, range: 0..<3))
        #expect(model.findBlock(id)?.content.runs == [TextRun("x^2", marks: [.math]), TextRun(" растёт")])
        model.undo()
        #expect(model.findBlock(id)?.content.runs == [TextRun("x^2 растёт")])
    }

    @Test func dollarShortcutTurnsParagraphIntoEquation() async throws {
        let (model, id) = try await openPage()
        model.updateMarkup(id, to: "$$ ")
        #expect(model.findBlock(id)?.type == .equation)
        #expect(model.findBlock(id)?.text == "")
    }

    @Test func rendererReadsTexAndReportsErrors() {
        guard case .image(let rendered) = MathRenderer.render("\\frac{a}{b} + \\sqrt{x}", fontSize: 17, display: true) else {
            Issue.record("Формула не нарисовалась")
            return
        }
        #expect(rendered.size.width > 10)
        #expect(rendered.size.height > 10)
        if case .image = MathRenderer.render("{1+\\frac{3+2", fontSize: 17, display: true) {
            Issue.record("Незакрытая скобка должна быть ошибкой")
        }
    }

    @Test func pdfExportDrawsEquations() async throws {
        let page = try await db.createPage(title: "Формулы")
        try await db.saveBlock(Block(pageId: page.id, type: .equation, content: BlockContent(text: "e^{i\\pi} + 1 = 0"), sortKey: "a"))
        try await db.saveBlock(Block(
            pageId: page.id,
            type: .paragraph,
            content: BlockContent(runs: [TextRun("где "), TextRun("\\pi", marks: [.math]), TextRun(" это число пи")]),
            sortKey: "b"
        ))
        try await db.saveBlock(Block(pageId: page.id, type: .equation, content: BlockContent(text: "{1+\\frac{3+2"), sortKey: "c"))
        let export = try #require(try await db.pageExport(page.id))
        let data = PagePDFRenderer.pdf(for: export, attachments: db.attachments)
        #expect(data.starts(with: Data("%PDF".utf8)))
        let text = PagePDFRenderer.attributedText(for: export, attachments: db.attachments).string
        #expect(text.contains("это число пи"))
        // Нечитаемый TeX попадает в PDF исходником.
        #expect(text.contains("{1+\\frac{3+2"))
    }
}
