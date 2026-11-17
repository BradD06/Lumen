import Foundation
import PencilKit
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct NotebookShapesTests {
    /// Штрих по точкам, как от руки: `pause` секунд в конце перо стоит на месте.
    private func stroke(_ locations: [CGPoint], startedAgo: TimeInterval = 1, pause: TimeInterval = 0, width: CGFloat = 4) -> PKStroke {
        let step = 0.01
        var points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * step,
                size: CGSize(width: width, height: width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        if pause > 0, let last = points.last {
            points.append(PKStrokePoint(
                location: last.location,
                timeOffset: last.timeOffset + pause,
                size: last.size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ))
        }
        let created = Date().addingTimeInterval(-startedAgo)
        return PKStroke(ink: PKInk(.pen, color: .systemBlue), path: PKStrokePath(controlPoints: points, creationDate: created))
    }

    private func circlePoints(center: CGPoint = CGPoint(x: 200, y: 200), radius: CGFloat = 80) -> [CGPoint] {
        (0...100).map { step in
            let t = CGFloat(step) / 100 * 2.08 * .pi
            let r = radius * (1 + 0.03 * sin(CGFloat(step) * 1.3))
            return CGPoint(x: center.x + r * cos(t), y: center.y + r * sin(t))
        }
    }

    private func linePoints() -> [CGPoint] {
        (0...40).map { CGPoint(x: 20 + CGFloat($0) * 6, y: 300 + sin(CGFloat($0)) * 1.2) }
    }

    @Test func snappedCircleKeepsInkAndWidth() throws {
        let original = stroke(circlePoints(), width: 6)
        let snapped = try #require(ShapeStrokes.snapped(original))
        #expect(snapped.ink.inkType == .pen)
        #expect(snapped.path.first?.size.width == 6)
        for point in snapped.path {
            #expect(abs(hypot(point.location.x - 200, point.location.y - 200) - 80) < 8)
        }
        // В штрихе нет фигуры: ровнять нечего.
        #expect(ShapeStrokes.snapped(stroke([CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 3)])) == nil)
    }

    @Test func newStrokeSnapsWhenThePenWasHeld() throws {
        ShapeSnap.shared.isOn = false
        let old = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        let quick = PKDrawing(strokes: [old, stroke(linePoints(), startedAgo: 0.4)])
        // Перо не задержали: штрих остаётся как есть.
        #expect(ShapeStrokes.snappingNewStroke(in: quick, previousCount: 1) == nil)

        let now = Date()
        let held = PKDrawing(strokes: [old, stroke(linePoints(), startedAgo: 1.2, pause: 0.8)])
        let snapped = try #require(ShapeStrokes.snappingNewStroke(in: held, previousCount: 1, now: now))
        #expect(snapped.strokes.count == 2)
        let line = snapped.strokes[1].renderBounds
        // Почти горизонтальная линия стала ровно горизонтальной.
        #expect(line.height < 10)
        // Старый штрих не тронут, а не новый штрих (стёрли, вернули отменой) не ровняется.
        #expect(snapped.strokes[0].renderBounds == old.renderBounds)
        #expect(ShapeStrokes.snappingNewStroke(in: held, previousCount: 2, now: now) == nil)
    }

    @Test func shapeModeSnapsEveryStroke() throws {
        defer { ShapeSnap.shared.isOn = false }
        ShapeSnap.shared.isOn = true
        let drawing = PKDrawing(strokes: [stroke(circlePoints(), startedAgo: 1.1)])
        let snapped = try #require(ShapeStrokes.snappingNewStroke(in: drawing, previousCount: 0))
        #expect(snapped.strokes.count == 1)
        // Давний штрих (например, вставленный) не ровняется даже в режиме фигур.
        let old = PKDrawing(strokes: [stroke(circlePoints(), startedAgo: 60)])
        #expect(ShapeStrokes.snappingNewStroke(in: old, previousCount: 0) == nil)
    }

    @Test func lassoStraightensSelectedStrokes() throws {
        let circle = stroke(circlePoints())
        let scribble = stroke([CGPoint(x: 400, y: 400), CGPoint(x: 404, y: 402)])
        let drawing = PKDrawing(strokes: [circle, scribble])
        let selection = LassoSelection(strokes: [0, 1], items: [], bounds: drawing.bounds)
        let result = try #require(DrawingLasso.straightening(selection, in: drawing, items: []))
        #expect(result.drawing.strokes.count == 2)
        #expect(result.selection?.strokes.count == 2)
        // Каракуля осталась как была, круг стал ровным.
        #expect(result.drawing.strokes.contains { $0.renderBounds == scribble.renderBounds })
        let onlyScribble = LassoSelection(strokes: [1], items: [], bounds: scribble.renderBounds)
        #expect(DrawingLasso.straightening(onlyScribble, in: drawing, items: []) == nil)
    }

    @Test func rotatingTurnsStrokesButOnlyMovesItems() throws {
        let line = stroke([CGPoint(x: 100, y: 200), CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 200)])
        let item = NotebookItem(kind: .image, frame: CGRect(x: 280, y: 180, width: 40, height: 40), attachment: "a.png")
        let drawing = PKDrawing(strokes: [line])
        let selection = LassoSelection(strokes: [0], items: [item.id], bounds: CGRect(x: 100, y: 180, width: 220, height: 40))
        let turn = DrawingLasso.rotation(.pi / 2, around: CGPoint(x: 200, y: 200))
        let result = DrawingLasso.moving(selection, by: turn, in: drawing, items: [item])

        let turned = result.drawing.strokes[0].renderBounds
        #expect(turned.width < 20)
        #expect(turned.height > 190)
        // Картинка не повернулась и не выросла, её середина переехала по кругу.
        let moved = result.items[0].frame
        #expect(moved.size == item.frame.size)
        #expect(abs(moved.midX - 200) < 0.01)
        #expect(abs(moved.midY - 300) < 0.01)

        #expect(abs(DrawingLasso.snappedAngle(.pi / 2 + 0.03) - .pi / 2) < 0.0001)
        #expect(DrawingLasso.snappedAngle(0.35) == 0.35)
    }

    @Test func sheetTemplatesFollowSheets() async throws {
        let db = try AppDatabase.inMemory()
        let page = try await db.createNotebook()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        model.addNotebookSheet()
        #expect(model.notebookSheetCount == 2)

        model.setSheetPaper(.cornell, sheet: 1)
        #expect(model.sheetPaper(0) == .lined)
        #expect(model.sheetPaper(1) == .cornell)

        // Новый лист после листа Корнелла тоже Корнелл, лист после обычного обычный.
        model.addNotebookSheet(after: 1)
        #expect(model.sheetPaper(2) == .cornell)
        model.addNotebookSheet(after: 0)
        #expect(model.sheetPaper(1) == .lined)
        #expect(model.sheetPaper(2) == .cornell)
        #expect(model.sheetPaper(3) == .cornell)

        // Удалили лист: шаблоны ниже поднялись вместе с листами.
        model.removeNotebookSheet(1)
        #expect(model.notebookBlock?.content.sheetPapers == [nil, .cornell, .cornell])

        model.undo()
        #expect(model.notebookSheetCount == 4)

        // Шаблон всех листов сбрасывает свои шаблоны листов.
        model.setPaper(.smallGrid)
        #expect(model.notebookBlock?.content.sheetPapers == nil)
        #expect((0..<model.notebookSheetCount).allSatisfy { model.sheetPaper($0) == .smallGrid })
        #expect(!model.hasSheetPapers)

        await model.flush()
        let saved = try #require(try await db.blocks(of: page.id).first)
        #expect(saved.content.paper == .smallGrid)
        #expect(saved.content.sheetPapers == nil)
    }

    @Test func everyTemplateDrawsSomething() {
        let size = CGSize(width: NotebookLayout.sheetWidth, height: NotebookLayout.sheetHeight)
        for pattern in PaperPattern.allCases where pattern != .blank {
            let drawn = [
                PaperGeometry.lines(pattern, size: size),
                PaperGeometry.margin(pattern, size: size),
                PaperGeometry.dots(pattern, size: size),
            ].compactMap { $0 }
            #expect(!drawn.isEmpty, "\(pattern) пустой")
        }
        #expect(PaperGeometry.lines(.blank, size: size) == nil)
        // У конспекта Корнелла поле вопросов и итог внизу.
        let cornell = PaperGeometry.margin(.cornell, size: size)?.boundingBox
        #expect(cornell?.width == size.width)
        // Нотный стан: линии не залезают на поля.
        let staff = PaperGeometry.lines(.staff, size: size)?.boundingBox
        #expect(staff?.minX == NotebookLayout.staffSideMargin)
        #expect((staff?.maxY ?? .infinity) <= size.height - NotebookLayout.staffSideMargin)
    }
}
