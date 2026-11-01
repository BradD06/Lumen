import Foundation
import PencilKit
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct DrawingLassoTests {
    /// Штрих по прямой из нескольких точек.
    private func stroke(from: CGPoint, to: CGPoint) -> PKStroke {
        let points = (0...4).map { step in
            let t = CGFloat(step) / 4
            return PKStrokePoint(
                location: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t),
                timeOffset: TimeInterval(step) * 0.05,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private func square(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    /// Два коротких штриха слева, длинный через всё поле, текст слева и картинка справа.
    private func sample() -> (PKDrawing, [NotebookItem]) {
        let drawing = PKDrawing(strokes: [
            stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 20)),
            stroke(from: CGPoint(x: 20, y: 60), to: CGPoint(x: 60, y: 80)),
            stroke(from: CGPoint(x: 20, y: 150), to: CGPoint(x: 500, y: 150)),
        ])
        let items = [
            NotebookItem(kind: .text, frame: CGRect(x: 30, y: 100, width: 50, height: 30), text: "Тезис"),
            NotebookItem(kind: .image, frame: CGRect(x: 300, y: 20, width: 100, height: 60), attachment: "a.png"),
        ]
        return (drawing, items)
    }

    @Test func lassoTakesWhatIsMostlyInside() throws {
        let (drawing, items) = sample()
        let selection = try #require(DrawingLasso.select(
            polygon: square(CGRect(x: 0, y: 0, width: 120, height: 170)),
            in: drawing,
            items: items
        ))
        // Длинный штрих лассо задело краем: он остаётся на месте.
        #expect(selection.strokes == [0, 1])
        #expect(selection.items == [items[0].id])
        #expect(selection.bounds.contains(CGPoint(x: 40, y: 115)))
        #expect(DrawingLasso.select(polygon: square(CGRect(x: 600, y: 600, width: 10, height: 10)), in: drawing, items: items) == nil)
        #expect(DrawingLasso.select(polygon: [.zero, CGPoint(x: 10, y: 10)], in: drawing) == nil)
    }

    @Test func movingShiftsStrokesAndItemsTogether() throws {
        let (drawing, items) = sample()
        let selection = try #require(DrawingLasso.select(polygon: square(CGRect(x: 0, y: 0, width: 120, height: 140)), in: drawing, items: items))
        let result = DrawingLasso.moving(selection, by: CGAffineTransform(translationX: 100, y: 50), in: drawing, items: items)

        #expect(result.drawing.strokes.count == 3)
        let moved = try #require(result.selection)
        #expect(abs(moved.bounds.minX - (selection.bounds.minX + 100)) < 0.5)
        #expect(abs(moved.bounds.minY - (selection.bounds.minY + 50)) < 0.5)
        #expect(result.items[0].frame.origin == CGPoint(x: 130, y: 150))
        #expect(result.items[1] == items[1])
        // Невыделенный длинный штрих не сдвинулся.
        #expect(result.drawing.strokes[0].renderBounds == drawing.strokes[2].renderBounds)
    }

    @Test func scalingGrowsTextWithItsFrame() {
        let item = NotebookItem(kind: .text, frame: CGRect(x: 10, y: 10, width: 100, height: 30), text: "a", fontSize: 20)
        let scaled = DrawingLasso.transformed(item, by: DrawingLasso.scaling(2, around: CGPoint(x: 10, y: 10)))
        #expect(scaled.frame == CGRect(x: 10, y: 10, width: 200, height: 60))
        #expect(scaled.fontSize == 40)
    }

    @Test func recolorDuplicateAndDelete() throws {
        let (drawing, items) = sample()
        let selection = try #require(DrawingLasso.select(polygon: square(CGRect(x: 0, y: 0, width: 120, height: 140)), in: drawing, items: items))
        let red = try #require(HexColor(hex: "#E03D3D"))

        let recolored = DrawingLasso.recoloring(selection, to: red, in: drawing, items: items)
        let newSelection = try #require(recolored.selection)
        for index in newSelection.strokes {
            let color = recolored.drawing.strokes[index].ink.color.usingColorSpace(.sRGB)
            #expect(abs((color?.redComponent ?? 0) - red.red) < 0.02)
        }
        #expect(recolored.items[0].color == "#E03D3D")
        #expect(recolored.items[1].color == items[1].color)

        let copy = DrawingLasso.duplicating(selection, in: drawing, items: items)
        #expect(copy.drawing.strokes.count == 5)
        #expect(copy.items.count == 3)
        #expect(copy.selection?.items.count == 1)
        #expect(copy.selection?.items.first != items[0].id)

        let deleted = DrawingLasso.deleting(selection, in: drawing, items: items)
        #expect(deleted.drawing.strokes.count == 1)
        #expect(deleted.items.map(\.id) == [items[1].id])
        #expect(deleted.selection == nil)
    }

    @Test func lassoEditIsOneUndoStep() async throws {
        let db = try AppDatabase.inMemory()
        let page = try await db.createNotebook()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let (drawing, items) = sample()
        model.setNotebookContent(drawing: drawing, items: items, recordsUndo: true)
        let selection = try #require(DrawingLasso.select(polygon: square(CGRect(x: 0, y: 0, width: 120, height: 140)), in: drawing, items: items))

        // Как при перетаскивании: подняли штрихи, двигали текст, положили на место.
        let base = DrawingLasso.removing(selection.strokes, from: drawing)
        model.setNotebookContent(drawing: base, items: nil, recordsUndo: true)
        let moved = DrawingLasso.moving(selection, by: CGAffineTransform(translationX: 40, y: 0), in: drawing, items: items)
        model.setNotebookContent(drawing: nil, items: moved.items, recordsUndo: false)
        model.setNotebookContent(drawing: moved.drawing, items: moved.items, recordsUndo: false)
        #expect(model.notebookItems[0].frame.minX == 70)

        model.undo()
        #expect(model.notebookItems[0].frame.minX == 30)
        #expect(DrawingSupport.drawing(from: model.notebookBlock?.drawing).strokes.count == 3)
    }
}
