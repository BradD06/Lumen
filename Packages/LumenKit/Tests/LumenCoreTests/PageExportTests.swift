import Foundation
import Testing
@testable import LumenCore

struct PageExportTests {
    let page = Page(title: "Матанализ", icon: "📘", sortKey: "a")

    private func block(
        _ type: BlockType,
        _ text: String = "",
        parent: Block? = nil,
        key: String,
        content: BlockContent? = nil
    ) -> Block {
        Block(
            pageId: page.id,
            parentBlockId: parent?.id,
            type: type,
            content: content ?? BlockContent(text: text),
            sortKey: key
        )
    }

    @Test func markdownKeepsStructure() {
        let list = block(.bulletedList, "Пределы", key: "c")
        let nested = block(.bulletedList, "Замечательные", parent: list, key: "a")
        let blocks = [
            block(.heading1, "Тема 1", key: "a"),
            block(.paragraph, "Вступление", key: "b"),
            list,
            nested,
            block(.numberedList, "Первое", key: "d"),
            block(.numberedList, "Второе", key: "e"),
            block(.todo, "Сдать", key: "f", content: BlockContent(text: "Сдать", isChecked: true)),
            block(.quote, "Цитата\nв две строки", key: "g"),
            block(.code, "let x = 1", key: "h"),
            block(.divider, key: "i"),
            block(.paragraph, "", key: "j"),
        ]
        let markdown = PageExport(page: page, blocks: blocks.shuffled()).markdown()
        #expect(markdown == """
            # 📘 Матанализ

            ## Тема 1

            Вступление

            - Пределы
                - Замечательные
            1. Первое
            2. Второе
            - [x] Сдать

            > Цитата
            > в две строки

            ```
            let x = 1
            ```

            ---

            """)
    }

    @Test func inlineMarksAndEscaping() {
        let runs = [
            TextRun("Жирный ", marks: [.bold]),
            TextRun("и "),
            TextRun("код", marks: [.code]),
            TextRun(" и "),
            TextRun("ссылка", link: "https://example.com"),
            TextRun(" 2*2"),
        ]
        #expect(PageExport.inline(runs, continuation: "") == "**Жирный** и `код` и [ссылка](https://example.com) 2\\*2")
    }

    @Test func columnsAreFlattenedAndImagesListed() {
        let row = block(.columnList, key: "a")
        let left = block(.column, parent: row, key: "a")
        let right = block(.column, parent: row, key: "b")
        let image = block(.image, parent: right, key: "a", content: BlockContent(attachment: "photo.png"))
        let export = PageExport(page: page, blocks: [
            row, left, right,
            block(.paragraph, "Слева", parent: left, key: "a"),
            image,
        ])
        #expect(export.items.map(\.block.type) == [.paragraph, .image])
        #expect(export.imageNames == ["photo.png"])
        #expect(export.markdown().hasSuffix("Слева\n\n![](images/photo.png)\n"))
    }

    @Test func excerptHasBookAndPlace() {
        let sourceId = UUID()
        var content = BlockContent(text: "Рукописи не горят")
        content.excerpt = ExcerptReference(sourceId: sourceId, highlightId: UUID(), label: "стр. 7")
        let export = PageExport(
            page: page,
            blocks: [block(.excerpt, key: "a", content: content)],
            sourceTitles: [sourceId: "Мастер и Маргарита"]
        )
        #expect(export.markdown().hasSuffix("> Рукописи не горят\n>\n> — Мастер и Маргарита, стр. 7\n"))
    }

    @Test func fileNameIsSafe() {
        let export = PageExport(page: Page(title: "План: 1/2 недели?", sortKey: "a"), blocks: [])
        #expect(export.fileName == "План- 1-2 недели-")
        #expect(PageExport(page: Page(title: "  ", sortKey: "a"), blocks: []).fileName == "Без названия")
    }
}
