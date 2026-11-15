import Foundation
import Testing
@testable import LumenCore

struct BlockCommentTests {
    @Test func commentsRoundTripAndCountOpenOnes() throws {
        var content = BlockContent(text: "Абзац")
        content.comments = [
            BlockComment(text: "Проверить", createdAt: Date(timeIntervalSince1970: 100)),
            BlockComment(text: "Готово", createdAt: Date(timeIntervalSince1970: 200), isResolved: true),
        ]
        let decoded = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(content))
        #expect(decoded == content)
        #expect(decoded.openComments.map(\.text) == ["Проверить"])
        #expect(decoded.searchText == "Абзац\nПроверить\nГотово")
    }

    @Test func brokenCommentsDoNotBreakTheBlock() throws {
        let json = #"{"runs":[{"text":"Текст","marks":[]}],"comments":"не список"}"#
        let decoded = try JSONDecoder().decode(BlockContent.self, from: Data(json.utf8))
        #expect(decoded.text == "Текст")
        #expect(decoded.comments == nil)
        let partial = try JSONDecoder().decode(BlockComment.self, from: Data(#"{"text":"старый"}"#.utf8))
        #expect(partial.text == "старый")
        #expect(!partial.isResolved)
    }
}
