import Foundation
import Testing
@testable import LumenCore

struct TableOfContentsTests {
    let page = Page(title: "Конспект", sortKey: "a")

    private func block(_ type: BlockType, _ text: String = "", parent: Block? = nil, key: String) -> Block {
        Block(pageId: page.id, parentBlockId: parent?.id, type: type, content: BlockContent(text: text), sortKey: key)
    }

    @Test func entriesKeepOrderAndIndentFromTheBiggestHeading() {
        let blocks = [
            block(.heading2, "Введение", key: "a"),
            block(.paragraph, "Текст", key: "b"),
            block(.heading3, "  Детали ", key: "c"),
            block(.heading2, "", key: "d"),
        ]
        let entries = PageContents.entries(blocks)
        #expect(entries.map(\.title) == ["Введение", "Детали", PageContents.untitled])
        // На странице нет «Заголовка 1»: вторые уровни стоят без отступа.
        #expect(entries.map(\.indent) == [0, 1, 0])
        #expect(entries.map(\.level) == [2, 3, 2])
    }

    @Test func noHeadingsGiveEmptyList() {
        #expect(PageContents.entries([block(.paragraph, "Текст", key: "a")]).isEmpty)
    }

    @Test func tableOfContentsIsInsertableWithoutText() {
        #expect(BlockType.tableOfContents.isInsertable)
        #expect(!BlockType.tableOfContents.hasText)
        #expect(!BlockType.tableOfContents.isConvertible)
        #expect(BlockType.tableOfContents.matches("оглав"))
        #expect(BlockType.tableOfContents.matches("toc"))
    }

    @Test func markdownListsHeadingsAsNestedList() {
        let toggle = block(.toggle, "Свернуть", key: "d")
        let blocks = [
            block(.tableOfContents, key: "a"),
            block(.heading1, "Глава", key: "b"),
            block(.heading2, "Раздел", key: "c"),
            toggle,
            block(.heading3, "Внутри", parent: toggle, key: "a"),
        ]
        let markdown = PageExport(page: page, blocks: blocks.shuffled()).markdown(includesTitle: false)
        #expect(markdown.hasPrefix("""
            - Глава
                - Раздел
                    - Внутри

            ## Глава
            """))
    }

    @Test func emptyTableOfContentsIsSkippedInMarkdown() {
        let markdown = PageExport(page: page, blocks: [block(.tableOfContents, key: "a"), block(.paragraph, "Текст", key: "b")])
            .markdown(includesTitle: false)
        #expect(markdown == "Текст\n")
    }
}
