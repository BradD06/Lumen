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
        for cover in [PageCover.gradient(3), .wallpaper(Wallpaper(palette: 4, layers: 3, isFaceted: true, seed: 11)), .image("ABC.jpg")] {
            #expect(PageCover(rawValue: cover.rawValue) == cover)
        }
    }

    @Test(arguments: ["", "gradient:", "gradient:x", "image:", "что-то"])
    func invalid(raw: String) {
        #expect(PageCover(rawValue: raw) == nil)
    }
}

struct PageBackgroundTests {
    @Test func roundTrip() {
        let backgrounds: [PageBackground] = [
            .wallpaper(Wallpaper(palette: 2, layers: 6, hasSun: false, seed: 1234)),
            .wallpaper(Wallpaper(palette: 1, layers: 3, hasSun: true, isFaceted: true, seed: 8)),
            .image("BG.png"),
        ]
        for background in backgrounds {
            #expect(PageBackground(rawValue: background.rawValue) == background)
        }
    }

    @Test func layersAreClamped() {
        #expect(Wallpaper(layers: 40).layers == Wallpaper.layerRange.upperBound)
        #expect(PageBackground(rawValue: "wallpaper:0,1,1,5") == .wallpaper(Wallpaper(palette: 0, layers: 2, hasSun: true, seed: 5)))
    }

    @Test(arguments: ["", "wallpaper:", "wallpaper:1,2,3", "wallpaper:1,2,3,4,5,6", "wallpaper:a,b,c,d", "image:", "gradient:1"])
    func invalid(raw: String) {
        #expect(PageBackground(rawValue: raw) == nil)
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
