import CoreGraphics
import LumenCore
import PencilKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Что обвели лассо: штрихи (их номера в рисунке) и тексты с картинками тетради.
struct LassoSelection: Equatable {
    var strokes: [Int]
    var items: [UUID]
    /// Рамка всего выделенного, в координатах рисунка.
    var bounds: CGRect

    var isEmpty: Bool { strokes.isEmpty && items.isEmpty }
}

/// Правка обведённого лассо: выбрать, сдвинуть, растянуть, перекрасить, скопировать, удалить.
/// Всё в координатах рисунка, без экрана, поэтому проверяется тестами.
enum DrawingLasso {
    /// Штрих попадает в лассо, если внутри больше половины его точек: так не цепляются
    /// длинные штрихи, которые лассо лишь задело краем.
    static let insideShare = 0.6

    static func select(polygon: [CGPoint], in drawing: PKDrawing, items: [NotebookItem] = []) -> LassoSelection? {
        guard polygon.count >= 3 else { return nil }
        let shape = CGMutablePath()
        shape.addLines(between: polygon)
        shape.closeSubpath()
        var strokes: [Int] = []
        for (index, stroke) in drawing.strokes.enumerated() {
            let points = samplePoints(of: stroke)
            guard !points.isEmpty else { continue }
            let inside = points.filter { shape.contains($0) }.count
            if Double(inside) >= Double(points.count) * insideShare {
                strokes.append(index)
            }
        }
        let itemIds = items
            .filter { shape.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .map(\.id)
        var selection = LassoSelection(strokes: strokes, items: itemIds, bounds: .null)
        guard !selection.isEmpty else { return nil }
        selection.bounds = bounds(of: selection, in: drawing, items: items)
        return selection
    }

    /// Точки штриха с шагом в несколько пунктов, уже с его сдвигом и масштабом.
    static func samplePoints(of stroke: PKStroke) -> [CGPoint] {
        var points = stroke.path.interpolatedPoints(by: .distance(4)).map { $0.location.applying(stroke.transform) }
        if points.isEmpty {
            points = stroke.path.map { $0.location.applying(stroke.transform) }
        }
        return points
    }

    static func bounds(of selection: LassoSelection, in drawing: PKDrawing, items: [NotebookItem]) -> CGRect {
        var rect = CGRect.null
        for index in selection.strokes where drawing.strokes.indices.contains(index) {
            rect = rect.union(drawing.strokes[index].renderBounds)
        }
        for item in items where selection.items.contains(item.id) {
            rect = rect.union(item.frame)
        }
        return rect
    }

    /// Выделенные штрихи отдельным рисунком.
    static func strokes(_ indices: [Int], of drawing: PKDrawing) -> [PKStroke] {
        indices.filter { drawing.strokes.indices.contains($0) }.map { drawing.strokes[$0] }
    }

    static func removing(_ indices: [Int], from drawing: PKDrawing) -> PKDrawing {
        let removed = Set(indices)
        var result = drawing
        result.strokes = drawing.strokes.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        return result
    }

    static func transformed(_ strokes: [PKStroke], by transform: CGAffineTransform) -> [PKStroke] {
        strokes.map { stroke in
            var stroke = stroke
            stroke.transform = stroke.transform.concatenating(transform)
            return stroke
        }
    }

    /// Текст или картинка после сдвига и растяжения. Текст растёт вместе с рамкой.
    static func transformed(_ item: NotebookItem, by transform: CGAffineTransform) -> NotebookItem {
        var item = item
        let scale = abs(transform.a)
        item.frame = item.frame.applying(transform)
        if item.kind == .text, abs(scale - 1) > 0.001 {
            let range = NotebookItem.fontSizeRange
            item.fontSize = min(max(item.fontSize * scale, range.lowerBound), range.upperBound)
        }
        return item
    }

    /// Растяжение без искажения: левый верхний угол рамки стоит на месте.
    static func scaling(_ factor: CGFloat, around origin: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: origin.x, y: origin.y)
            .scaledBy(x: factor, y: factor)
            .translatedBy(x: -origin.x, y: -origin.y)
    }

    static func recolored(_ strokes: [PKStroke], to color: HexColor) -> [PKStroke] {
        #if canImport(UIKit)
        let platform = UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        #else
        let platform = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        #endif
        return strokes.map { stroke in
            PKStroke(ink: PKInk(stroke.ink.inkType, color: platform), path: stroke.path, transform: stroke.transform, mask: stroke.mask)
        }
    }

    /// Рисунок и элементы после правки выделенного. Изменённые штрихи встают поверх остальных,
    /// поэтому у выделения новые номера: они в ответе.
    struct Result {
        var drawing: PKDrawing
        var items: [NotebookItem]
        var selection: LassoSelection?
    }

    /// Применяет `change` к выделенным штрихам и `itemChange` к выделенным элементам.
    static func applying(
        to selection: LassoSelection,
        in drawing: PKDrawing,
        items: [NotebookItem],
        strokes change: ([PKStroke]) -> [PKStroke],
        items itemChange: (NotebookItem) -> NotebookItem
    ) -> Result {
        var result = removing(selection.strokes, from: drawing)
        let start = result.strokes.count
        result.strokes.append(contentsOf: change(strokes(selection.strokes, of: drawing)))
        let changedItems = items.map { selection.items.contains($0.id) ? itemChange($0) : $0 }
        var newSelection = LassoSelection(strokes: Array(start..<result.strokes.count), items: selection.items, bounds: .null)
        newSelection.bounds = bounds(of: newSelection, in: result, items: changedItems)
        return Result(drawing: result, items: changedItems, selection: newSelection.isEmpty ? nil : newSelection)
    }

    static func moving(_ selection: LassoSelection, by transform: CGAffineTransform, in drawing: PKDrawing, items: [NotebookItem]) -> Result {
        applying(to: selection, in: drawing, items: items, strokes: { transformed($0, by: transform) }, items: { transformed($0, by: transform) })
    }

    static func recoloring(_ selection: LassoSelection, to color: HexColor, in drawing: PKDrawing, items: [NotebookItem]) -> Result {
        applying(to: selection, in: drawing, items: items, strokes: { recolored($0, to: color) }, items: { item in
            var item = item
            if item.kind == .text { item.color = color.hex }
            return item
        })
    }

    static func deleting(_ selection: LassoSelection, in drawing: PKDrawing, items: [NotebookItem]) -> Result {
        Result(
            drawing: removing(selection.strokes, from: drawing),
            items: items.filter { !selection.items.contains($0.id) },
            selection: nil
        )
    }

    /// Копия выделенного чуть ниже и правее. Выделенной становится копия.
    static func duplicating(_ selection: LassoSelection, in drawing: PKDrawing, items: [NotebookItem], offset: CGFloat = 24) -> Result {
        let shift = CGAffineTransform(translationX: offset, y: offset)
        var result = drawing
        let start = result.strokes.count
        result.strokes.append(contentsOf: transformed(strokes(selection.strokes, of: drawing), by: shift))
        var copies: [NotebookItem] = []
        for item in items where selection.items.contains(item.id) {
            var copy = transformed(item, by: shift)
            copy.id = UUID()
            copies.append(copy)
        }
        let allItems = items + copies
        var newSelection = LassoSelection(strokes: Array(start..<result.strokes.count), items: copies.map(\.id), bounds: .null)
        newSelection.bounds = bounds(of: newSelection, in: result, items: allItems)
        return Result(drawing: result, items: allItems, selection: newSelection.isEmpty ? nil : newSelection)
    }
}
