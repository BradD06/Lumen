import Foundation
import Testing
@testable import LumenCore

/// Формулы TeX: $$…$$ в строке, блок «Формула», Markdown.
struct MathMarkupTests {
    private func run(_ text: String, _ marks: Set<TextMark> = []) -> TextRun {
        TextRun(text, marks: marks)
    }

    @Test func inlineMathKeepsTexAsIs() {
        #expect(InlineMarkup.runs(from: "площадь $$\\pi r^2$$ круга") == [
            run("площадь "), run("\\pi r^2", [.math]), run(" круга"),
        ])
        // Внутри формулы звёздочки и подчёркивания не оформление, а сам TeX.
        #expect(InlineMarkup.runs(from: "$$a*b*c$$") == [run("a*b*c", [.math])])
        #expect(InlineMarkup.runs(from: "**жирно $$x_1$$**") == [run("жирно ", [.bold]), run("x_1", [.bold, .math])])
    }

    @Test func mathSourceRoundTrips() {
        let runs = [run("дробь "), run("\\frac{a}{b}", [.math]), run(" и всё")]
        let source = InlineMarkup.source(runs)
        #expect(source == "дробь $$\\frac{a}{b}$$ и всё")
        #expect(InlineMarkup.runs(from: source) == runs)
    }

    @Test func dollarsInTextStayText() {
        for text in ["цена 5$ и 10$", "$$", "$$$$", "$ x $", "доллары $$ без конца"] {
            let runs = InlineMarkup.runs(from: text)
            #expect(runs == [run(text)], "\(text)")
            #expect(InlineMarkup.source(runs) == text)
        }
        // Текст, который сам выглядит как формула, при сборке экранируется и читается обратно тем же.
        let literal = [run("$$x$$")]
        #expect(InlineMarkup.runs(from: InlineMarkup.source(literal)) == literal)
    }

    @Test func mathAndCodeDoNotMix() {
        let code = [run("x^2", [.code])]
        #expect(InlineMarkup.toggling(.math, in: code, range: 0..<3) == [run("x^2", [.math])])
        let math = [run("x^2", [.math])]
        #expect(InlineMarkup.toggling(.code, in: math, range: 0..<3) == [run("x^2", [.code])])
        #expect(InlineMarkup.toggling(.math, in: math, range: 0..<3) == [run("x^2")])
    }

    @Test func equationBlockType() {
        #expect(BlockType.equation.hasText)
        #expect(BlockType.equation.isPlainText)
        #expect(BlockType.code.isPlainText)
        #expect(!BlockType.paragraph.isPlainText)
        #expect(BlockType.equation.isInsertable)
        #expect(BlockType.equation.matches("формул"))
        #expect(BlockType.equation.matches("math"))
        #expect(BlockType.equation.matches("latex"))
        #expect(BlockType.equation.continuation == .paragraph)
    }

    @Test func dollarShortcutMakesEquation() {
        let match = MarkdownShortcut.match("$$ e^{i\\pi}")
        #expect(match?.type == .equation)
        #expect(match?.remainder == "e^{i\\pi}")
        #expect(MarkdownShortcut.match("$$x$$") == nil)
    }

    @Test func pastedMarkdownEquations() {
        let blocks = MarkdownPaste.blocks(from: "Формула:\n$$\n\\int_0^1 x\\,dx\n= \\frac12\n$$\n$$a^2+b^2=c^2$$\nтекст $$x$$ в строке")
        #expect(blocks.map(\.type) == [.paragraph, .equation, .equation, .paragraph])
        #expect(blocks[1].source == "\\int_0^1 x\\,dx\n= \\frac12")
        #expect(blocks[2].source == "a^2+b^2=c^2")
        // В блоке формулы TeX лежит как есть, без разбора разметки.
        #expect(blocks[1].content.runs == [run("\\int_0^1 x\\,dx\n= \\frac12")])
        #expect(blocks[3].content.runs == [run("текст "), run("x", [.math]), run(" в строке")])
        // Без закрывающих $$ это обычный текст.
        #expect(MarkdownPaste.blocks(from: "$$\nx").map(\.type) == [.paragraph, .paragraph])
    }

    @Test func markdownExportWritesDollars() {
        let page = Page(title: "Геометрия", sortKey: "a")
        let blocks = [
            Block(pageId: page.id, type: .equation, content: BlockContent(text: "a^2+b^2=c^2"), sortKey: "a"),
            Block(pageId: page.id, type: .paragraph, content: BlockContent(runs: [run("где "), run("c", [.math]), run(" гипотенуза")]), sortKey: "b"),
            Block(pageId: page.id, type: .equation, sortKey: "c"),
        ]
        let markdown = PageExport(page: page, blocks: blocks).markdown()
        #expect(markdown.contains("$$\na^2+b^2=c^2\n$$\n\nгде $c$ гипотенуза"))
        #expect(!markdown.contains("$$\n$$"))
    }

    @Test func equationEstimatesSheetSpace() {
        let page = Page(title: "", sortKey: "a")
        let block = Block(pageId: page.id, type: .equation, content: BlockContent(text: "x"), sortKey: "a")
        #expect(NoteSheets.height(of: block) { _ in [] } > 30)
    }
}
