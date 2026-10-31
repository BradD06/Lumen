import CoreGraphics
import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct PagePDFTests {
    private func pageCount(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return 0 }
        return document.numberOfPages
    }

    @Test func longPageIsSplitIntoSheets() async throws {
        let db = try AppDatabase.inMemory()
        let page = try await db.createPage(title: "Длинный конспект")
        let paragraph = String(repeating: "Предел последовательности это число, к которому она стремится. ", count: 6)
        var key = "a"
        for index in 0..<120 {
            let type: BlockType = index % 10 == 0 ? .heading2 : index % 3 == 0 ? .bulletedList : .paragraph
            try await db.saveBlock(Block(pageId: page.id, type: type, content: BlockContent(text: paragraph), sortKey: key))
            key = SortKey.between(key, nil)
        }
        try await db.saveBlock(Block(pageId: page.id, type: .divider, sortKey: key))

        let export = try #require(try await db.pageExport(page.id))
        let data = PagePDFRenderer.pdf(for: export, attachments: db.attachments)
        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(pageCount(data) > 3)
    }

    @Test func shortPageFitsOneSheet() async throws {
        let db = try AppDatabase.inMemory()
        let page = try await db.createPage(title: "Покупки")
        let export = try #require(try await db.pageExport(page.id))
        #expect(pageCount(PagePDFRenderer.pdf(for: export, attachments: db.attachments)) == 1)
    }
}
