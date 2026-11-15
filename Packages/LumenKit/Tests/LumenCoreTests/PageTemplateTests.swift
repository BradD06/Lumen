import Foundation
import Testing
@testable import LumenCore

struct PageTemplateTests {
    @Test func builtInTemplatesHaveBlocks() {
        #expect(PageTemplate.builtIn.count == 5)
        #expect(Set(PageTemplate.builtIn.map(\.id)).count == 5)
        for template in PageTemplate.builtIn {
            #expect(!template.blocks.blocks.isEmpty)
            #expect(template.isBuiltIn)
        }
        let lecture = PageTemplate.builtIn[0]
        #expect(lecture.blocks.blocks.first?.type == .heading2)
        #expect(lecture.blocks.blocks.contains { $0.type == .todo })
    }

    @Test func markdownBlocksKeepNestingAndOrder() {
        let parsed = MarkdownPaste.blocks(from: "- a\n  - b\n  - c\n- d")
        let blocks = MarkdownPaste.makeBlocks(parsed, pageId: UUID())
        #expect(blocks.map(\.text) == ["a", "b", "c", "d"])
        #expect(blocks[1].parentBlockId == blocks[0].id)
        #expect(blocks[2].parentBlockId == blocks[0].id)
        #expect(blocks[3].parentBlockId == nil)
        #expect(blocks[1].sortKey < blocks[2].sortKey)
        #expect(blocks[0].sortKey < blocks[3].sortKey)
    }
}
