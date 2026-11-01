import CoreGraphics
import Foundation

/// Вид страницы. Обычная страница из блоков это `nil`.
public enum PageKind: String, Codable, Sendable {
    /// Рукописная заметка, как в Goodnotes: листы бумаги друг под другом, на которых пишут от руки.
    case notebook
}

/// Линовка бумаги рукописной заметки.
public enum PaperPattern: String, Codable, Sendable, CaseIterable, Identifiable {
    case blank
    case lined
    case grid
    case dotted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blank: "Чистый лист"
        case .lined: "В линейку"
        case .grid: "В клетку"
        case .dotted: "В точку"
        }
    }

    public var symbolName: String {
        switch self {
        case .blank: "doc"
        case .lined: "line.3.horizontal"
        case .grid: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        }
    }
}

/// Цвет бумаги рукописной заметки.
public enum PaperTone: String, Codable, Sendable, CaseIterable, Identifiable {
    case white
    case cream
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .white: "Белая"
        case .cream: "Кремовая"
        case .dark: "Тёмная"
        }
    }

    /// На тёмной бумаге PencilKit показывает чернила в тёмной теме: чёрная ручка пишет белым.
    public var isDark: Bool { self == .dark }
}

/// Область рисунка внутри обычной заметки: высота по умолчанию и пределы, до которых её тянут.
public enum DrawingArea {
    public static let defaultHeight: Double = 260
    public static let minHeight: Double = 120
    public static let maxHeight: Double = 2400

    public static func clampedHeight(_ height: Double) -> Double {
        min(max(height, minHeight), maxHeight)
    }

    public static func height(of content: BlockContent) -> Double {
        clampedHeight(content.drawingHeight ?? defaultHeight)
    }

    /// Насколько холст может быть шире области, прежде чем рисунок начнёт уменьшаться:
    /// край штриха у самой границы не должен сжимать весь рисунок.
    public static let widthSlack: Double = 4

    /// Во сколько раз уменьшить рисунок, чтобы холст шириной `canvasWidth` целиком влез
    /// в область шириной `available`. В широком окне рисунок не растягивается, масштаб не больше 1.
    public static func scale(canvasWidth: Double, available: Double) -> Double {
        guard available > 0, canvasWidth > available + widthSlack else { return 1 }
        return available / canvasWidth
    }

    /// Ширина холста после правки. `inkWidth` это правый край штрихов, `visibleWidth` сколько
    /// пунктов рисунка сейчас видно в области. Холст не сужается, пока рисунок не стёрли целиком:
    /// иначе при стирании дальнего штриха рисунок вдруг становился бы крупнее.
    public static func updatedWidth(stored: Double?, inkWidth: Double?, visibleWidth: Double) -> Double? {
        guard let inkWidth, inkWidth > 0 else { return nil }
        return max(stored ?? 0, min(inkWidth, visibleWidth))
    }
}

/// Раскладка листов рукописной заметки. Все листы лежат на одном холсте друг под другом
/// с промежутками, координаты штрихов считаются в пунктах этого холста. Лист размером A4,
/// поэтому заметку можно распечатать или выгрузить в PDF лист в лист.
public enum NotebookLayout {
    public static let sheetWidth: CGFloat = 768
    public static let sheetHeight: CGFloat = (768 * 297 / 210).rounded()
    public static let sheetGap: CGFloat = 28
    public static let maxSheets = 500

    /// Расстояние между верхними краями соседних листов.
    public static var sheetStride: CGFloat { sheetHeight + sheetGap }

    public static func sheetCount(of content: BlockContent) -> Int {
        min(max(content.sheetCount ?? 1, 1), maxSheets)
    }

    public static func sheetRect(_ index: Int) -> CGRect {
        CGRect(x: 0, y: CGFloat(index) * sheetStride, width: sheetWidth, height: sheetHeight)
    }

    /// Высота всего холста: листы и промежутки между ними.
    public static func canvasHeight(sheets: Int) -> CGFloat {
        let count = max(sheets, 1)
        return CGFloat(count) * sheetHeight + CGFloat(count - 1) * sheetGap
    }

    /// Лист, на котором точка холста, или ближайший к ней.
    public static func sheetIndex(at y: CGFloat, sheets: Int) -> Int {
        let index = Int((y / sheetStride).rounded(.down))
        return min(max(index, 0), max(sheets, 1) - 1)
    }

    /// Линии линовки на листе в его собственных координатах: расстояние между линиями
    /// и отступ первой линии сверху. Одни и те же числа для экрана и для PDF.
    public static let lineSpacing: CGFloat = 32
    public static let gridSpacing: CGFloat = 28
    public static let topMargin: CGFloat = 96
}
