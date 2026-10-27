import Foundation
import Testing
@testable import LumenCore

struct MarkdownShortcutTests {
    @Test(arguments: [
        ("# Глава", BlockType.heading1, "Глава"),
        ("## Раздел", .heading2, "Раздел"),
        ("### Пункт", .heading3, "Пункт"),
        ("- молоко", .bulletedList, "молоко"),
        ("* хлеб", .bulletedList, "хлеб"),
        ("1. первое", .numberedList, "первое"),
        ("[] сдать курсовую", .todo, "сдать курсовую"),
        ("[ ] позвонить", .todo, "позвонить"),
        ("> мысль", .quote, "мысль"),
        ("```", .code, ""),
        ("---", .divider, ""),
    ])
    func shortcuts(input: String, type: BlockType, remainder: String) throws {
        let match = try #require(MarkdownShortcut.match(input))
        #expect(match.type == type)
        #expect(match.remainder == remainder)
    }

    @Test(arguments: ["Обычный текст", "#хештег", "--- после", "-минус", ""])
    func plainTextIsNotAShortcut(input: String) {
        #expect(MarkdownShortcut.match(input) == nil)
    }
}

struct BlockContentTests {
    @Test func textRoundTrip() throws {
        var content = BlockContent(text: "Привет")
        #expect(content.text == "Привет")
        content.text = ""
        #expect(content.runs.isEmpty)

        let data = try JSONEncoder().encode(BlockContent(text: "Цитата", isChecked: true))
        let decoded = try JSONDecoder().decode(BlockContent.self, from: data)
        #expect(decoded.text == "Цитата")
        #expect(decoded.isChecked)
    }

    @Test func missingFieldsDecodeWithDefaults() throws {
        let decoded = try JSONDecoder().decode(BlockContent.self, from: Data("{}".utf8))
        #expect(decoded.runs.isEmpty)
        #expect(!decoded.isChecked)
    }

    @Test func listsContinueOtherBlocksBecomeText() {
        #expect(BlockType.todo.continuation == .todo)
        #expect(BlockType.bulletedList.continuation == .bulletedList)
        #expect(BlockType.heading1.continuation == .paragraph)
        #expect(BlockType.quote.continuation == .paragraph)
    }

    @Test func slashMenuMatching() {
        #expect(BlockType.todo.matches("зад"))
        #expect(BlockType.heading2.matches("h2"))
        #expect(BlockType.heading2.matches(""))
        #expect(!BlockType.divider.matches("заголовок"))
    }

    @Test func untitledPageHasDisplayTitle() {
        #expect(Page(sortKey: "V").displayTitle == "Без названия")
        #expect(Page(title: "  Идеи ", sortKey: "V").displayTitle == "Идеи")
    }
}
