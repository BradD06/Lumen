import Foundation
import Testing
@testable import LumenCore

struct MentionTriggerTests {
    @Test(arguments: [
        ("[[", "", ""),
        ("[[Лекц", "", "Лекц"),
        ("см. [[Матан", "см. ", "Матан"),
        ("@", "", ""),
        ("спросить @Анн", "спросить ", "Анн"),
    ])
    func triggers(input: String, prefix: String, query: String) throws {
        let match = try #require(MentionTrigger.match(input))
        #expect(match.prefix == prefix)
        #expect(match.query == query)
    }

    @Test(arguments: ["обычный текст", "почта me@mail.ru", "[[Готово]]", "@ пробел", ""])
    func notATrigger(input: String) {
        #expect(MentionTrigger.match(input) == nil)
    }
}

struct PageCoverTests {
    @Test func roundTrip() {
        for cover in [PageCover.gradient(3), .image("ABC.jpg")] {
            #expect(PageCover(rawValue: cover.rawValue) == cover)
        }
    }

    @Test(arguments: ["", "gradient:", "gradient:x", "image:", "что-то"])
    func invalid(raw: String) {
        #expect(PageCover(rawValue: raw) == nil)
    }
}

struct BlockContentCompatibilityTests {
    /// Блоки, сохранённые до появления ссылок и картинок, читаются без ошибок.
    @Test func decodesOldJSON() throws {
        let json = Data(#"{"runs":[{"text":"старый","marks":[]}],"isChecked":true}"#.utf8)
        let content = try JSONDecoder().decode(BlockContent.self, from: json)
        #expect(content.text == "старый")
        #expect(content.isChecked)
        #expect(content.pageId == nil)
        #expect(content.attachment == nil)
    }
}

struct BlockColorDecodingTests {
    @Test func unknownColorIsIgnored() throws {
        let json = Data(#"{"runs":[],"textColor":"neon","backgroundColor":"blue","isCollapsed":true}"#.utf8)
        let content = try JSONDecoder().decode(BlockContent.self, from: json)
        #expect(content.textColor == nil)
        #expect(content.backgroundColor == .blue)
        #expect(content.isCollapsed)
    }
}
