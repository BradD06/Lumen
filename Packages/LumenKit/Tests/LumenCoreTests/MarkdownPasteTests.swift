import Foundation
import Testing
@testable import LumenCore

struct MarkdownPasteTests {
    @Test func headingsListsAndTasksBecomeBlocks() {
        let blocks = MarkdownPaste.blocks(from: """
            # План
            Вступление с **жирным**

            - пункт
              - вложенный
            1. первый
            - [ ] купить хлеб
            - [x] позвонить
            > цитата
            ---
            """)
        #expect(blocks.map(\.type) == [.heading1, .paragraph, .bulletedList, .bulletedList, .numberedList, .todo, .todo, .quote, .divider])
        #expect(blocks[0].source == "План")
        #expect(blocks[1].content.runs == [TextRun("Вступление с "), TextRun("жирным", marks: [.bold])])
        #expect(blocks.map(\.depth) == [0, 0, 0, 1, 0, 0, 0, 0, 0])
        #expect(blocks[5].isChecked == false)
        #expect(blocks[6].isChecked == true)
        #expect(blocks[6].source == "позвонить")
    }

    @Test func codeFenceKeepsLinesAndMarkup() {
        let blocks = MarkdownPaste.blocks(from: "Пример:\n```swift\nlet a = **b**\n\nprint(a)\n```\nКонец")
        #expect(blocks.map(\.type) == [.paragraph, .code, .paragraph])
        #expect(blocks[1].source == "let a = **b**\n\nprint(a)")
        #expect(blocks[1].content.runs == [TextRun("let a = **b**\n\nprint(a)")])
    }

    @Test func gfmTableBecomesTable() throws {
        let blocks = MarkdownPaste.blocks(from: """
            | Книга | Автор |
            |---|:---:|
            | Война \\| мир | Толстой |
            | Идиот |
            """)
        #expect(blocks.count == 1)
        let table = try #require(blocks.first?.table)
        #expect(blocks.first?.type == .table)
        #expect(table.rowCount == 3)
        #expect(table.columnCount == 2)
        #expect(table.hasHeaderRow)
        #expect(table.cell(1, 0).text == "Война | мир")
        #expect(table.cell(2, 1).text == "")
    }

    @Test func plainLinesHaveNoStructure() {
        let blocks = MarkdownPaste.blocks(from: "первая строка\n    вторая с отступом\nтретья")
        #expect(!MarkdownPaste.hasStructure(blocks))
        #expect(!MarkdownPaste.hasStructure(MarkdownPaste.blocks(from: "**жирно** и всё\nещё строка")))
    }

    @Test func nestingNeverSkipsALevel() {
        let blocks = MarkdownPaste.blocks(from: "- a\n        - b\n    - c\n- d")
        #expect(blocks.map(\.depth) == [0, 1, 1, 0])
    }

    @Test func dividersAndNotHeadings() {
        #expect(MarkdownPaste.parseLine("***").type == .divider)
        #expect(MarkdownPaste.parseLine("- - -").type == .divider)
        #expect(MarkdownPaste.parseLine("#хештег").type == .paragraph)
        #expect(MarkdownPaste.parseLine("**жирно**").type == .paragraph)
        #expect(MarkdownPaste.parseLine("#### Мелкий").type == .heading3)
        #expect(MarkdownPaste.parseLine("## Глава ##").source == "Глава")
        #expect(MarkdownPaste.parseLine("2) второй").type == .numberedList)
    }

    @Test func imagesBecomeLinksAndUnderscoresBold() {
        #expect(MarkdownPaste.inline("см. ![схема](https://a.b/c.png)") == "см. [схема](https://a.b/c.png)")
        #expect(MarkdownPaste.inline("__важно__ и snake__case__name") == "**важно** и snake__case__name")
    }

    @Test func differenceFindsInsertedText() {
        let change = MarkdownPaste.difference(old: "начало конец", new: "начало # A\n- b конец")
        #expect(change.prefix == "начало ")
        #expect(change.inserted == "# A\n- b")
        #expect(change.suffix == " конец")
    }
}
