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
