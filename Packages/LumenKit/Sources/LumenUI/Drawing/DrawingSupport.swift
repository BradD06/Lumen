import CoreGraphics
import LumenCore
import PencilKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Общее для рисунков в заметках и рукописных заметок: чтение штрихов, картинки, бумага.
enum DrawingSupport {
    static func drawing(from data: Data?) -> PKDrawing {
        guard let data, !data.isEmpty, let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    /// Данные для базы: пустой рисунок не хранится.
    static func data(of drawing: PKDrawing) -> Data? {
        drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
    }

    /// Картинка части рисунка. Цвета чернил PencilKit хранит для светлой темы, а в тёмной
    /// сам осветляет тёмные: чёрная ручка на тёмном фоне становится белой, как в Заметках.
    @MainActor
    static func image(of drawing: PKDrawing, in rect: CGRect, scale: CGFloat, isDark: Bool) -> PlatformImage? {
        guard rect.width > 0, rect.height > 0, scale > 0 else { return nil }
        #if canImport(UIKit)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: isDark ? .dark : .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image
        #else
        // На Mac картинка рисуется сразу в растр, пока действует нужное оформление:
        // NSImage мог бы отложить отрисовку до показа, и цвета взялись бы из другой темы.
        var image: NSImage?
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        let render = {
            let source = drawing.image(from: rect, scale: scale)
            if let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                image = NSImage(cgImage: cgImage, size: rect.size)
            }
        }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(render)
        } else {
            render()
        }
        return image
        #endif
    }

    /// Штрих, которого касается точка: по нему проходит ластик.
    static func stroke(_ stroke: PKStroke, isHitBy point: CGPoint, radius: CGFloat) -> Bool {
        guard stroke.renderBounds.insetBy(dx: -radius, dy: -radius).contains(point) else { return false }
        let local = point.applying(stroke.transform.inverted())
        for strokePoint in stroke.path.interpolatedPoints(by: .distance(2)) {
            let reach = radius + strokePoint.size.width / 2
            let dx = strokePoint.location.x - local.x
            let dy = strokePoint.location.y - local.y
            if dx * dx + dy * dy <= reach * reach { return true }
        }
        return false
    }

    /// Рисунок без штрихов, которых касается точка. `nil`, если ластик ничего не задел.
    static func erasing(at point: CGPoint, radius: CGFloat, in drawing: PKDrawing) -> PKDrawing? {
        let kept = drawing.strokes.filter { !stroke($0, isHitBy: point, radius: radius) }
        guard kept.count != drawing.strokes.count else { return nil }
        return PKDrawing(strokes: kept)
    }
}

// MARK: - Листы рукописной заметки

enum NotebookEditing {
    /// Рисунок без листа `index`: его штрихи стираются, а штрихи листов ниже поднимаются на его место.
    /// Лист штриха определяется по середине штриха.
    static func removingSheet(_ index: Int, from drawing: PKDrawing) -> PKDrawing {
        let rect = NotebookLayout.sheetRect(index)
        let top = rect.minY - NotebookLayout.sheetGap / 2
        let bottom = rect.maxY + NotebookLayout.sheetGap / 2
        let lift = CGAffineTransform(translationX: 0, y: -NotebookLayout.sheetStride)
        var strokes: [PKStroke] = []
        for var stroke in drawing.strokes {
            let middle = stroke.renderBounds.midY
            if middle >= top && middle < bottom { continue }
            if middle >= bottom {
                stroke.transform = stroke.transform.concatenating(lift)
            }
            strokes.append(stroke)
        }
        return PKDrawing(strokes: strokes)
    }

    /// Рисунок с чистым листом после листа `index`: штрихи ниже опускаются на один лист.
    static func insertingSheet(after index: Int, in drawing: PKDrawing) -> PKDrawing {
        let boundary = NotebookLayout.sheetRect(index).maxY + NotebookLayout.sheetGap / 2
        let drop = CGAffineTransform(translationX: 0, y: NotebookLayout.sheetStride)
        return PKDrawing(strokes: drawing.strokes.map { stroke in
            var stroke = stroke
            if stroke.renderBounds.midY >= boundary {
                stroke.transform = stroke.transform.concatenating(drop)
            }
            return stroke
        })
    }
}

// MARK: - Бумага

/// Цвета бумаги и линовки.
struct PaperColors {
    var paper: CGColor
    var line: CGColor
    var margin: CGColor

    init(_ tone: PaperTone) {
        switch tone {
        case .white:
            paper = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            line = CGColor(srgbRed: 0.62, green: 0.70, blue: 0.82, alpha: 0.55)
            margin = CGColor(srgbRed: 0.93, green: 0.45, blue: 0.40, alpha: 0.45)
        case .cream:
            paper = CGColor(srgbRed: 0.99, green: 0.96, blue: 0.90, alpha: 1)
            line = CGColor(srgbRed: 0.72, green: 0.62, blue: 0.50, alpha: 0.45)
            margin = CGColor(srgbRed: 0.90, green: 0.48, blue: 0.36, alpha: 0.45)
        case .dark:
            paper = CGColor(srgbRed: 0.15, green: 0.13, blue: 0.14, alpha: 1)
            line = CGColor(srgbRed: 1, green: 0.88, blue: 0.80, alpha: 0.16)
            margin = CGColor(srgbRed: 1, green: 0.55, blue: 0.40, alpha: 0.35)
        }
    }
}

/// Линии и точки линовки листа в координатах листа.
enum PaperGeometry {
    static let dotRadius: CGFloat = 1.6
    static let lineWidth: CGFloat = 1

    /// Линии: строки в линейку, клетка. Для чистого листа и листа в точку `nil`.
    static func lines(_ pattern: PaperPattern, size: CGSize) -> CGPath? {
        let path = CGMutablePath()
        switch pattern {
        case .blank, .dotted:
            return nil
        case .lined:
            var y = NotebookLayout.topMargin
            while y < size.height - 24 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += NotebookLayout.lineSpacing
            }
        case .grid:
            let step = NotebookLayout.gridSpacing
            var y = step
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            var x = step
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
        }
        return path
    }

    /// Поля слева на листе в линейку, как в школьной тетради.
    static func margin(_ pattern: PaperPattern, size: CGSize) -> CGPath? {
        guard pattern == .lined else { return nil }
        let path = CGMutablePath()
        let x: CGFloat = 72
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        return path
    }

    static func dots(_ pattern: PaperPattern, size: CGSize) -> CGPath? {
        guard pattern == .dotted else { return nil }
        let path = CGMutablePath()
        let step = NotebookLayout.gridSpacing
        var y = step
        while y < size.height {
            var x = step
            while x < size.width {
                path.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                x += step
            }
            y += step
        }
        return path
    }

    /// Рисует лист в контексте в координатах листа: бумага, линии, точки.
    static func draw(_ pattern: PaperPattern, tone: PaperTone, size: CGSize, in context: CGContext) {
        let colors = PaperColors(tone)
        context.setFillColor(colors.paper)
        context.fill(CGRect(origin: .zero, size: size))
        context.setLineWidth(lineWidth)
        if let lines = lines(pattern, size: size) {
            context.addPath(lines)
            context.setStrokeColor(colors.line)
            context.strokePath()
        }
        if let margin = margin(pattern, size: size) {
            context.addPath(margin)
            context.setStrokeColor(colors.margin)
            context.strokePath()
        }
        if let dots = dots(pattern, size: size) {
            context.addPath(dots)
            context.setFillColor(colors.line)
            context.fillPath()
        }
    }
}

/// Лист бумаги в SwiftUI: для листов рукописной заметки на Mac.
struct PaperSheet: View {
    let pattern: PaperPattern
    let tone: PaperTone

    var body: some View {
        Canvas { context, size in
            let scale = size.width / NotebookLayout.sheetWidth
            let sheetSize = CGSize(width: NotebookLayout.sheetWidth, height: size.height / max(scale, 0.01))
            context.scaleBy(x: scale, y: scale)
            let colors = PaperColors(tone)
            context.fill(Path(CGRect(origin: .zero, size: sheetSize)), with: .color(Color(cgColor: colors.paper)))
            let style = StrokeStyle(lineWidth: PaperGeometry.lineWidth / max(scale, 0.5))
            if let lines = PaperGeometry.lines(pattern, size: sheetSize) {
                context.stroke(Path(lines), with: .color(Color(cgColor: colors.line)), style: style)
            }
            if let margin = PaperGeometry.margin(pattern, size: sheetSize) {
                context.stroke(Path(margin), with: .color(Color(cgColor: colors.margin)), style: style)
            }
            if let dots = PaperGeometry.dots(pattern, size: sheetSize) {
                context.fill(Path(dots), with: .color(Color(cgColor: colors.line)))
            }
        }
    }
}

// MARK: - Картинка рисунка

/// Готовая картинка рисунка. Перерисовывается, только когда меняются штрихи, размер или тема.
final class DrawingImageCache {
    private struct Key: Equatable {
        var data: Data?
        var rect: CGRect
        var scale: CGFloat
        var isDark: Bool
    }

    private var key: Key?
    private var image: PlatformImage?

    @MainActor
    func image(data: Data?, drawing: () -> PKDrawing, rect: CGRect, scale: CGFloat, isDark: Bool) -> PlatformImage? {
        let newKey = Key(data: data, rect: rect, scale: scale, isDark: isDark)
        if newKey != key {
            key = newKey
            image = data == nil ? nil : DrawingSupport.image(of: drawing(), in: rect, scale: scale, isDark: isDark)
        }
        return image
    }
}

/// Штрихи из части рисунка, растянутые на весь размер вью.
struct DrawingImageView: View {
    let data: Data?
    /// Уже прочитанный рисунок, если он есть у экрана вокруг: так его не разбирают для каждого листа заново.
    var drawing: PKDrawing?
    /// Какая часть рисунка видна, в его координатах.
    let rect: CGRect
    let isDark: Bool

    @State private var cache = DrawingImageCache()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let zoom = rect.width > 0 ? geometry.size.width / rect.width : 1
            if let image = cache.image(
                data: data,
                drawing: { drawing ?? DrawingSupport.drawing(from: data) },
                rect: rect,
                // Больше трёх пикселей на пункт глаз не различит, а память такая картинка съест.
                scale: min(max(zoom * displayScale, 1), 3),
                isDark: isDark
            ) {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
