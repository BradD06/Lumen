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

struct CoverCropTests {
    @Test func roundTrip() throws {
        let crop = CoverCrop(focusX: 0.25, focusY: 0.8, zoom: 1.6, height: .high)
        let parsed = try #require(CoverCrop(rawValue: crop.rawValue))
        #expect(abs(parsed.focusX - 0.25) < 0.001)
        #expect(abs(parsed.focusY - 0.8) < 0.001)
        #expect(abs(parsed.zoom - 1.6) < 0.001)
        #expect(parsed.height == .high)
    }

    @Test(arguments: ["", "0.5,0.5", "x,0.5,1,medium", "nan,0.5,1,medium"])
    func invalid(raw: String) {
        #expect(CoverCrop(rawValue: raw) == nil)
    }

    @Test func valuesAreClamped() {
        let crop = CoverCrop(focusX: -2, focusY: 5, zoom: 10)
        #expect(crop.focusX == 0)
        #expect(crop.focusY == 1)
        #expect(crop.zoom == CoverCrop.maxZoom)
        // Неизвестная высота из более новой версии: средняя.
        #expect(CoverCrop(rawValue: "0.5,0.5,1,huge")?.height == .medium)
    }

    @Test func pageWithoutCropIsCentered() {
        var page = Page(sortKey: "a")
        #expect(page.pageCoverCrop == CoverCrop())
        page.pageCoverCrop = CoverCrop(focusY: 0.2)
        #expect(page.coverCrop != nil)
        // Ракурс по умолчанию в базе не хранится.
        page.pageCoverCrop = CoverCrop()
        #expect(page.coverCrop == nil)
    }

    @Test func wideImageHidesItsSides() {
        // Панорама 3000×500 в полосе 1000×240: закрывает высоту, по ширине лишнее скрыто.
        let layout = CoverCrop().layout(boxWidth: 1000, boxHeight: 240, imageWidth: 3000, imageHeight: 500)
        #expect(abs(layout.height - 240) < 0.001)
        #expect(abs(layout.width - 1440) < 0.001)
        #expect(layout.spanY == 0)
        #expect(abs(layout.spanX - 440) < 0.001)
        #expect(layout.canMove)
        #expect(abs(layout.offsetX + 220) < 0.001)
    }

    @Test func tallImageMovesVertically() {
        // Фото 1000×1500 в полосе 1000×240: видна полоса, остальное по высоте скрыто.
        let top = CoverCrop(focusY: 0).layout(boxWidth: 1000, boxHeight: 240, imageWidth: 1000, imageHeight: 1500)
        #expect(top.spanX == 0)
        #expect(abs(top.spanY - 1260) < 0.001)
        #expect(top.offsetY == 0)
        let bottom = CoverCrop(focusY: 1).layout(boxWidth: 1000, boxHeight: 240, imageWidth: 1000, imageHeight: 1500)
        #expect(abs(bottom.offsetY + 1260) < 0.001)
    }

    @Test func zoomLetsAnyImageMove() {
        let plain = CoverCrop().layout(boxWidth: 1000, boxHeight: 240, imageWidth: nil, imageHeight: nil)
        #expect(!plain.canMove)
        let zoomed = CoverCrop(zoom: 2).layout(boxWidth: 1000, boxHeight: 240, imageWidth: nil, imageHeight: nil)
        #expect(abs(zoomed.spanX - 1000) < 0.001)
        #expect(abs(zoomed.spanY - 240) < 0.001)
    }

    @Test func draggingDownShowsWhatWasAbove() {
        let crop = CoverCrop(focusY: 0.5)
        let moved = crop.dragged(dx: 0, dy: 100, spanX: 0, spanY: 1000)
        #expect(abs(moved.focusY - 0.4) < 0.001)
        #expect(moved.focusX == crop.focusX)
        #expect(crop.dragged(dx: 0, dy: 5000, spanX: 0, spanY: 1000).focusY == 0)
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
