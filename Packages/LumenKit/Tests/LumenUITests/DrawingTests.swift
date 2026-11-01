import Foundation
import PencilKit
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct DrawingTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func waitForAutosave() async throws {
        try await Task.sleep(for: .milliseconds(900))
    }

    /// Штрих из двух точек: от `from` до `to` по прямой.
    private func stroke(from: CGPoint, to: CGPoint) -> PKStroke {
        let points = [from, to].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.05,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    @Test func slashMenuDrawingStartsDrawingRightAway() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)
        model.updateText(blockId, to: "/рис")

        model.setType(blockId, .drawing)

        let block = try #require(model.findBlock(blockId))
        #expect(block.type == .drawing)
        #expect(block.text.isEmpty)
        #expect(model.activeDrawingId == blockId)
        #expect(model.children(of: nil).map(\.type) == [.drawing, .paragraph])
    }

    @Test func drawingIsSavedAndUndoable() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)
        model.setType(blockId, .drawing)

        let data = try #require(DrawingSupport.data(of: PKDrawing(strokes: [stroke(from: .zero, to: CGPoint(x: 50, y: 50))])))
        model.setDrawing(blockId, data: data)
        try await waitForAutosave()
        #expect(try await db.blocks(of: page.id).first { $0.id == blockId }?.drawing == data)

        model.undo()
        #expect(model.findBlock(blockId)?.drawing == nil)
        try await waitForAutosave()
        #expect(try await db.blocks(of: page.id).first { $0.id == blockId }?.drawing == nil)
    }

    @Test func drawingAreaHeightIsClampedAndUndoable() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)
        model.setType(blockId, .drawing)

        model.setDrawingHeight(blockId, 480)
        #expect(model.findBlock(blockId)?.content.drawingHeight == 480)
        model.setDrawingHeight(blockId, 5)
        #expect(model.findBlock(blockId)?.content.drawingHeight == DrawingArea.minHeight)
        model.undo()
        #expect(model.findBlock(blockId)?.content.drawingHeight == 480)

        try await waitForAutosave()
        #expect(try await db.blocks(of: page.id).first { $0.id == blockId }?.content.drawingHeight == 480)
    }

    @Test func drawingStartsOnlyInDrawingBlocks() async throws {
        let page = try await db.createPage()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let blockId = try #require(model.blocks.first?.id)
        model.startDrawing(blockId)
        #expect(model.activeDrawingId == nil, "Рисовать можно только в блоке «Рисунок»")
        model.setType(blockId, .drawing)
        model.stopDrawing()
        model.startDrawing(blockId)
        #expect(model.activeDrawingId == blockId)
    }

    @Test func notebookSheetsCanBeAddedAndRemoved() async throws {
        let page = try await db.createNotebook()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        #expect(model.isNotebook)
        let block = try #require(model.notebookBlock)
        #expect(model.notebookSheetCount == 1)

        // Штрих на первом листе и штрих на втором.
        model.addNotebookSheet()
        let second = NotebookLayout.sheetRect(1)
        let drawing = PKDrawing(strokes: [
            stroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 120)),
            stroke(from: CGPoint(x: 100, y: second.minY + 100), to: CGPoint(x: 200, y: second.minY + 120)),
        ])
        model.setDrawing(block.id, data: DrawingSupport.data(of: drawing))
        #expect(model.notebookSheetCount == 2)

        // Удаляем первый лист: остаётся один штрих, и он поднимается на первый лист.
        model.removeNotebookSheet(0)
        #expect(model.notebookSheetCount == 1)
        let remaining = DrawingSupport.drawing(from: model.notebookBlock?.drawing)
        #expect(remaining.strokes.count == 1)
        let bounds = try #require(remaining.strokes.first?.renderBounds)
        #expect(NotebookLayout.sheetRect(0).contains(CGPoint(x: bounds.midX, y: bounds.midY)))

        // Последний лист не удаляется.
        model.removeNotebookSheet(0)
        #expect(model.notebookSheetCount == 1)

        model.setPaper(.dotted)
        model.setPaperTone(.cream)
        try await waitForAutosave()
        let saved = try #require(try await db.blocks(of: page.id).first)
        #expect(saved.content.sheetCount == 1)
        #expect(saved.content.paper == .dotted)
        #expect(saved.content.paperTone == .cream)
    }

    @Test func insertingASheetPushesLaterStrokesDown() {
        let first = stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 90, y: 60))
        let secondY = NotebookLayout.sheetRect(1).minY + 40
        let second = stroke(from: CGPoint(x: 50, y: secondY), to: CGPoint(x: 90, y: secondY + 10))
        let result = NotebookEditing.insertingSheet(after: 0, in: PKDrawing(strokes: [first, second]))
        #expect(result.strokes.count == 2)
        let moved = result.strokes[1].renderBounds
        #expect(NotebookLayout.sheetIndex(at: moved.midY, sheets: 3) == 2)
        #expect(NotebookLayout.sheetIndex(at: result.strokes[0].renderBounds.midY, sheets: 3) == 0)
    }

    @Test func eraserRemovesOnlyTouchedStrokes() {
        let touched = stroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let untouched = stroke(from: CGPoint(x: 0, y: 200), to: CGPoint(x: 100, y: 200))
        let drawing = PKDrawing(strokes: [touched, untouched])
        let erased = DrawingSupport.erasing(at: CGPoint(x: 50, y: 3), radius: 6, in: drawing)
        #expect(erased?.strokes.count == 1)
        #expect(DrawingSupport.erasing(at: CGPoint(x: 50, y: 100), radius: 6, in: drawing) == nil)
    }

    @Test func emptyDrawingIsNotStored() {
        #expect(DrawingSupport.data(of: PKDrawing()) == nil)
        #expect(DrawingSupport.drawing(from: nil).strokes.isEmpty)
        #expect(DrawingSupport.drawing(from: Data([1, 2, 3])).strokes.isEmpty)
    }
}
