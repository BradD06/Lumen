import Foundation
import Testing
@testable import LumenCore

struct NotebookTests {
    @Test func drawingFieldsRoundTripThroughJSON() throws {
        let content = BlockContent(drawingHeight: 420, sheetCount: 3, paper: .grid, paperTone: .dark)
        let decoded = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.drawingHeight == 420)
        #expect(decoded.sheetCount == 3)
        #expect(decoded.paper == .grid)
        #expect(decoded.paperTone == .dark)
    }

    @Test func unknownPaperFromANewerVersionIsIgnored() throws {
        let json = Data(#"{"runs":[],"paper":"music","paperTone":"pink","sheetCount":2}"#.utf8)
        let decoded = try JSONDecoder().decode(BlockContent.self, from: json)
        #expect(decoded.paper == nil)
        #expect(decoded.paperTone == nil)
        #expect(decoded.sheetCount == 2)
    }

    @Test func drawingAreaHeightStaysWithinLimits() {
        #expect(DrawingArea.height(of: BlockContent()) == DrawingArea.defaultHeight)
        #expect(DrawingArea.height(of: BlockContent(drawingHeight: 10)) == DrawingArea.minHeight)
        #expect(DrawingArea.height(of: BlockContent(drawingHeight: 99_999)) == DrawingArea.maxHeight)
        #expect(DrawingArea.clampedHeight(500) == 500)
    }

    @Test func drawingWidthRoundTripsThroughJSON() throws {
        let content = BlockContent(drawingWidth: 640)
        let decoded = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.drawingWidth == 640)
        let old = try JSONDecoder().decode(BlockContent.self, from: Data(#"{"runs":[]}"#.utf8))
        #expect(old.drawingWidth == nil)
    }

    @Test func narrowAreaShrinksDrawingButWideOneDoesNotStretchIt() {
        #expect(DrawingArea.scale(canvasWidth: 600, available: 300) == 0.5)
        #expect(DrawingArea.scale(canvasWidth: 600, available: 900) == 1)
        // Край штриха чуть за границей области не сжимает рисунок.
        #expect(DrawingArea.scale(canvasWidth: 602, available: 600) == 1)
        // До замера ширины области рисунок в натуральную величину.
        #expect(DrawingArea.scale(canvasWidth: 600, available: 0) == 1)
    }

    @Test func canvasWidthGrowsWithInkButNeverPastWhatIsVisible() {
        #expect(DrawingArea.updatedWidth(stored: nil, inkWidth: 300, visibleWidth: 800) == 300)
        #expect(DrawingArea.updatedWidth(stored: 300, inkWidth: 700, visibleWidth: 800) == 700)
        // Штрих у самого края: холст не шире видимого, иначе рисунок сжимался бы на ходу.
        #expect(DrawingArea.updatedWidth(stored: 300, inkWidth: 806, visibleWidth: 800) == 800)
        // Стёрли дальний штрих: холст прежний, рисунок не прыгает.
        #expect(DrawingArea.updatedWidth(stored: 700, inkWidth: 200, visibleWidth: 800) == 700)
        // Стёрли всё: ширина забыта.
        #expect(DrawingArea.updatedWidth(stored: 700, inkWidth: nil, visibleWidth: 800) == nil)
    }

    @Test func sheetBackgroundsFollowTheirSheets() throws {
        let page = SheetBackground(attachment: "a.pdf", page: 0)
        let other = SheetBackground(attachment: "a.pdf", page: 1)
        // Две страницы после первого из трёх листов: третий лист с PDF уезжает на пятое место.
        let list = NotebookSheets.inserting([page, other], after: 0, into: [nil, nil, page], sheetCount: 3)
        #expect(list == [nil, page, other, nil, page])
        // В конец, когда список короче листов.
        #expect(NotebookSheets.inserting([page], after: nil, into: nil, sheetCount: 2) == [nil, nil, page])
        // Чистый лист без PDF в конец ничего не хранит.
        #expect(NotebookSheets.inserting([nil], after: nil, into: nil, sheetCount: 2) == nil)
        #expect(NotebookSheets.removing(1, from: [nil, page, other]) == [nil, other])
        #expect(NotebookSheets.removing(1, from: [nil, page]) == nil)

        let content = BlockContent(sheetCount: 2, sheetBackgrounds: [nil, other])
        let decoded = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.sheetBackgrounds == [nil, other])
        #expect(NotebookSheets.background(of: decoded, sheet: 1) == other)
        #expect(NotebookSheets.background(of: decoded, sheet: 5) == nil)
    }

    @Test func pdfPageFitsTheSheetWithoutStretching() {
        let sheet = CGRect(x: 0, y: 0, width: 768, height: 1086)
        // Альбомная страница: во всю ширину, по центру по высоте.
        let landscape = NotebookSheets.fit(pageSize: CGSize(width: 842, height: 595), in: sheet)
        #expect(abs(landscape.width - 768) < 0.01)
        #expect(abs(landscape.midY - sheet.midY) < 0.01)
        #expect(abs(landscape.width / landscape.height - 842.0 / 595.0) < 0.001)
    }

    @Test func sheetsAreStackedWithGaps() {
        let stride = NotebookLayout.sheetHeight + NotebookLayout.sheetGap
        #expect(NotebookLayout.sheetRect(0).minY == 0)
        #expect(NotebookLayout.sheetRect(2).minY == stride * 2)
        #expect(NotebookLayout.canvasHeight(sheets: 1) == NotebookLayout.sheetHeight)
        #expect(NotebookLayout.canvasHeight(sheets: 3) == NotebookLayout.sheetHeight * 3 + NotebookLayout.sheetGap * 2)
        // Лист A4: высота к ширине как 297 к 210.
        #expect(abs(NotebookLayout.sheetHeight / NotebookLayout.sheetWidth - 297.0 / 210.0) < 0.01)
    }

    @Test func sheetIndexIsClampedToExistingSheets() {
        #expect(NotebookLayout.sheetIndex(at: -50, sheets: 3) == 0)
        #expect(NotebookLayout.sheetIndex(at: NotebookLayout.sheetStride * 1.5, sheets: 3) == 1)
        #expect(NotebookLayout.sheetIndex(at: NotebookLayout.sheetStride * 10, sheets: 3) == 2)
        #expect(NotebookLayout.sheetCount(of: BlockContent()) == 1)
        #expect(NotebookLayout.sheetCount(of: BlockContent(sheetCount: 0)) == 1)
    }

    @Test func drawingIsNotATextBlock() {
        #expect(!BlockType.drawing.hasText)
        #expect(BlockType.drawing.isInsertable)
        #expect(!BlockType.drawing.isConvertible)
        #expect(BlockType.drawing.matches("рис"))
        #expect(BlockType.drawing.matches("от руки"))
    }

    @Test func markdownMarksADrawing() {
        let page = Page(title: "Схема", sortKey: "a")
        let empty = Block(pageId: page.id, type: .drawing, sortKey: "a")
        let drawn = Block(pageId: page.id, type: .drawing, drawing: Data([1, 2, 3]), sortKey: "b")
        let markdown = PageExport(page: page, blocks: [empty, drawn]).markdown()
        #expect(markdown == "# Схема\n\n_✍️ Рисунок от руки_\n")
    }
}

struct NotebookItemTests {
    @Test func itemsRoundTripAndUnknownKindsAreSkipped() throws {
        let text = NotebookItem(kind: .text, frame: CGRect(x: 10, y: 20, width: 200, height: 40), text: "Тезис", color: "#2A6BE6")
        let image = NotebookItem(kind: .image, frame: CGRect(x: 0, y: 0, width: 300, height: 200), attachment: "a.png")
        let content = BlockContent(sheetCount: 1, items: [text, image])
        let decoded = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.items == [text, image])

        // Вид из более новой версии не ломает остальные элементы.
        var json = try #require(String(data: JSONEncoder().encode(content), encoding: .utf8))
        json = json.replacingOccurrences(of: #""kind":"image""#, with: #""kind":"sticker""#)
        let lossy = try JSONDecoder().decode(BlockContent.self, from: Data(json.utf8))
        #expect(lossy.items == [text])
    }

    @Test func itemKeepsAMinimumSizeAndFontRange() {
        var item = NotebookItem(kind: .text, frame: CGRect(x: 0, y: 0, width: 2, height: 2), fontSize: 500)
        #expect(item.width == NotebookItem.minSize)
        #expect(item.fontSize == NotebookItem.fontSizeRange.upperBound)
        item.frame = CGRect(x: 5, y: 6, width: 1, height: 100)
        #expect(item.frame == CGRect(x: 5, y: 6, width: NotebookItem.minSize, height: 100))
        #expect(NotebookItem(kind: .text, frame: .zero, text: "  \n").isEmpty)
        #expect(!NotebookItem(kind: .image, frame: .zero).isEmpty)
    }

    @Test func hexColorsRoundTrip() throws {
        let color = try #require(HexColor(hex: "#2A6BE6"))
        #expect(color.hex == "#2A6BE6")
        #expect(HexColor(hex: "2a6be6")?.hex == "#2A6BE6")
        #expect(HexColor(hex: "#12") == nil)
        #expect(HexColor(hex: "#141414")?.isNearBlack == true)
        #expect(HexColor(hue: 0, saturation: 1, brightness: 1).hex == "#FF0000")
        #expect(HexColor(hue: 1.0 / 3, saturation: 1, brightness: 1).hex == "#00FF00")
    }

    @Test func paletteIsLargeAndDistinct() {
        let colors = HexColor.palette.flatMap { $0 }
        #expect(colors.count == 72)
        #expect(Set(colors.map(\.hex)).count == 72)
        #expect(HexColor.palette.first?.first?.hex == "#000000")
        #expect(HexColor.palette.first?.last?.hex == "#FFFFFF")
    }
}
