#if os(macOS)
import AppKit
import LumenCore
import LumenThemes
import PencilKit
import SwiftUI

/// Перо для рисования мышью и трекпадом на Mac: на Mac нет PKCanvasView и панели инструментов
/// PencilKit, поэтому штрихи собираются сами, но в том же формате, что и на iPad.
/// Одно перо на всё приложение: выбранный цвет остаётся и в заметке, и в рукописной тетради.
@MainActor
@Observable
final class MouseInk {
    static let shared = MouseInk()

    var tool: Tool = .pen
    /// Цвет чернил для светлой бумаги, в нём PencilKit хранит штрихи.
    var color = HexColor(red: 0.08, green: 0.08, blue: 0.1)
    /// Толщина ручки и карандаша в пунктах рисунка.
    var penWidth: Double = 4
    var markerWidth: Double = 20
    /// Последние цвета, которыми писали: сверху панели, чтобы не искать их в палитре.
    private(set) var recentColors: [HexColor]

    static let penWidthRange: ClosedRange<Double> = 1...30
    static let markerWidthRange: ClosedRange<Double> = 6...60
    private static let recentKey = "drawing.recentColors"
    private static let recentLimit = 8

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        let colors = saved.compactMap(HexColor.init(hex:))
        recentColors = colors.isEmpty ? MouseInk.starterColors : colors
    }

    /// Цвета для начала: чёрный, синий, красный, зелёный, оранжевый, фиолетовый, жёлтый.
    static let starterColors: [HexColor] = ["#141419", "#2A6BE6", "#E03D3D", "#2E9E57", "#F28533", "#8C57DB", "#F9CC29"]
        .compactMap(HexColor.init(hex:))

    /// Перекрашивает обведённое лассо. Ставит его тот слой, где сейчас есть выделение.
    @ObservationIgnored var recolorLassoSelection: ((HexColor) -> Void)?
    @ObservationIgnored var recolorOwner: UUID?

    /// Выбрать цвет. Цвет из палитры запоминается среди последних, выбор из последних их не переставляет.
    /// С лассо цвет достаётся обведённому.
    func choose(_ color: HexColor, remember: Bool) {
        self.color = color
        if tool == .eraser { tool = .pen }
        if tool == .lasso { recolorLassoSelection?(color) }
        if remember { rememberRecent(color) }
    }

    private func rememberRecent(_ color: HexColor) {
        var colors = recentColors.filter { $0 != color }
        colors.insert(color, at: 0)
        recentColors = Array(colors.prefix(Self.recentLimit))
        UserDefaults.standard.set(recentColors.map(\.hex), forKey: Self.recentKey)
    }

    enum Tool: String, CaseIterable, Identifiable {
        case pen, pencil, marker, eraser, lasso

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pen: "Ручка"
            case .pencil: "Карандаш"
            case .marker: "Маркер"
            case .eraser: "Ластик"
            case .lasso: "Лассо: обвести и двигать"
            }
        }

        var symbolName: String {
            switch self {
            case .pen: "pencil.tip"
            case .pencil: "pencil"
            case .marker: "highlighter"
            case .eraser: "eraser"
            case .lasso: "lasso"
            }
        }

        var inkType: PKInk.InkType {
            switch self {
            case .pen, .eraser, .lasso: .pen
            case .pencil: .pencil
            case .marker: .marker
            }
        }
    }

    var nsColor: NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    /// Толщина штриха в пунктах рисунка.
    var width: CGFloat {
        CGFloat(tool == .marker ? markerWidth : penWidth)
    }

    /// Ластик стирает штрихи целиком, которых касается в этом радиусе (в пунктах экрана).
    var eraserRadius: CGFloat {
        CGFloat(min(max(penWidth * 2.5, 6), 30))
    }
}

/// Слой, по которому рисуют мышью. Лежит поверх картинки рисунка и отдаёт готовый рисунок
/// после каждого штриха. `origin` это точка рисунка в левом верхнем углу слоя,
/// `scale` сколько пунктов экрана в пункте рисунка.
struct MouseDrawingLayer: View {
    let drawing: PKDrawing
    var origin: CGPoint = .zero
    var scale: CGFloat = 1
    let isDark: Bool
    /// Тексты и картинки тетради: лассо обводит и их.
    var items: [NotebookItem] = []
    /// Новый рисунок. Второй аргумент говорит, начинается ли новый шаг отмены.
    var onChange: (PKDrawing, Bool) -> Void
    /// Правка лассо: новый рисунок и элементы (`nil`, если не менялись) и начало шага отмены.
    /// Без него лассо правит только штрихи.
    var onLasso: ((PKDrawing?, [NotebookItem]?, Bool) -> Void)?

    private struct TimedPoint {
        var location: CGPoint
        var time: TimeInterval
    }

    /// Обведённое, которое сейчас тащат или растягивают. Штрихи на это время вынуты из рисунка
    /// и показаны отдельной картинкой: так не перерисовывается весь лист на каждый сдвиг мыши.
    private struct Lift {
        var selection: LassoSelection
        /// Рисунок без поднятых штрихов.
        var base: PKDrawing
        var strokes: [PKStroke]
        var items: [NotebookItem]
        var image: PlatformImage?
        var transform: CGAffineTransform = .identity
    }

    /// Чем занято текущее движение мыши.
    private enum DragMode {
        case ink, lasso, move, resize
    }

    @State private var points: [TimedPoint] = []
    @State private var startedAt = Date()
    @State private var isDragging = false
    /// Рисунок во время стирания: ластик за одно движение задевает много штрихов.
    @State private var erasing: PKDrawing?
    @State private var mode: DragMode = .ink
    /// Метка слоя: перекраску в общем пере ставит и убирает только тот слой, где выделение.
    @State private var token = UUID()
    @State private var selection: LassoSelection?
    @State private var lift: Lift?
    /// Рисунок, который слой отдал сам. Если пришёл другой (отмена, правка на другом листе),
    /// выделение сбрасывается: номера штрихов в нём уже не те.
    @State private var expected: DrawingSignature?
    @State private var isPaletteShown = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.lumenTheme) private var theme
    private var ink: MouseInk { .shared }

    private struct DrawingSignature: Equatable {
        var count: Int
        var bounds: CGRect

        init(_ drawing: PKDrawing) {
            count = drawing.strokes.count
            bounds = drawing.bounds
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                guard let first = points.first, ink.tool != .eraser else { return }
                var path = Path()
                path.move(to: first.location)
                for point in points.dropFirst() {
                    path.addLine(to: point.location)
                }
                if ink.tool == .lasso {
                    path.closeSubpath()
                    context.fill(path, with: .color(theme.accent.opacity(0.08)))
                    context.stroke(path, with: .color(theme.accent), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    return
                }
                if points.count == 1 {
                    path.addLine(to: CGPoint(x: first.location.x + 0.1, y: first.location.y))
                }
                context.stroke(
                    path,
                    with: .color(ink.color.display(isDark: isDark).opacity(ink.tool == .marker ? 0.4 : 1)),
                    style: StrokeStyle(lineWidth: ink.width * scale, lineCap: .round, lineJoin: .round)
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(dragChanged)
                    .onEnded(dragEnded)
            )
            .pointerStyle(ink.tool == .lasso ? PointerStyle.default : PointerStyle.rectSelection)

            if let lift, let image = lift.image {
                let rect = toScreen(LassoGeometry.strokesBounds(lift.strokes).applying(lift.transform))
                Image(platformImage: image)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
            if let frame = selectionFrame {
                selectionChrome(frame)
            }
        }
        .accessibilityLabel("Холст для рисования")
        .onChange(of: DrawingSignature(drawing)) { _, signature in
            if signature != expected, lift == nil {
                selection = nil
            }
            installRecolor()
        }
        .onChange(of: ink.tool) { _, tool in
            if tool != .lasso { clearSelection() }
        }
        .onChange(of: selection) { _, _ in
            installRecolor()
        }
        .onDisappear {
            if ink.recolorOwner == token {
                ink.recolorLassoSelection = nil
                ink.recolorOwner = nil
            }
        }
    }

    // MARK: Координаты

    private func toDrawing(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale + origin.x, y: point.y / scale + origin.y)
    }

    private func toScreen(_ rect: CGRect) -> CGRect {
        CGRect(x: (rect.minX - origin.x) * scale, y: (rect.minY - origin.y) * scale, width: rect.width * scale, height: rect.height * scale)
    }

    /// Рамка выделения на экране, с запасом, чтобы тонкую линию было легко схватить.
    private var selectionFrame: CGRect? {
        guard let selection, !selection.bounds.isNull else { return nil }
        let bounds = selection.bounds.applying(lift?.transform ?? .identity)
        return toScreen(bounds).insetBy(dx: -6, dy: -6)
    }

    // MARK: Рамка и панель выделения

    private func selectionChrome(_ frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
            Circle()
                .fill(theme.accent)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle().inset(by: -6))
                .offset(x: frame.maxX - 9, y: frame.maxY - 9)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in resize(by: value.translation) }
                        .onEnded { _ in dropLift() }
                )
                .pointerStyle(.frameResize(position: .bottomTrailing))
                .help("Растянуть")
            if lift == nil {
                actionBar
                    .fixedSize()
                    .offset(x: frame.minX, y: max(frame.minY - 42, 0))
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            Button {
                isPaletteShown = true
            } label: {
                Image(systemName: "paintpalette")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .help("Перекрасить")
            .popover(isPresented: $isPaletteShown) {
                ColorPalette(selection: ink.color) { color in
                    ink.choose(color, remember: true)
                }
                .padding(16)
            }
            Button {
                applyResult { DrawingLasso.duplicating($0, in: drawing, items: items) }
            } label: {
                Image(systemName: "plus.square.on.square")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .help("Дублировать")
            Button {
                applyResult { DrawingLasso.deleting($0, in: drawing, items: items) }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .help("Удалить")
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.textSecondary.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }

    // MARK: Мышь

    private func dragChanged(_ value: DragGesture.Value) {
        if !isDragging {
            isDragging = true
            startedAt = Date()
            points = []
            erasing = nil
            if ink.tool == .lasso {
                if let frame = selectionFrame, frame.contains(value.startLocation) {
                    mode = .move
                } else {
                    mode = .lasso
                    selection = nil
                }
            } else {
                mode = .ink
            }
        }
        switch mode {
        case .move:
            liftIfNeeded()
            lift?.transform = CGAffineTransform(
                translationX: value.translation.width / scale,
                y: value.translation.height / scale
            )
            emitLiveItems()
        case .lasso:
            points.append(TimedPoint(location: value.location, time: 0))
        case .resize:
            break
        case .ink:
            if ink.tool == .eraser {
                let current = erasing ?? drawing
                let radius = ink.eraserRadius / max(scale, 0.1)
                if let erased = DrawingSupport.erasing(at: toDrawing(value.location), radius: radius, in: current) {
                    // Первое стёртое за движение начинает шаг отмены, остальные входят в него.
                    onChange(erased, erasing == nil)
                    erasing = erased
                }
            } else {
                points.append(TimedPoint(location: value.location, time: Date().timeIntervalSince(startedAt)))
            }
        }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        defer {
            isDragging = false
            points = []
            erasing = nil
        }
        switch mode {
        case .move:
            dropLift()
        case .lasso:
            let polygon = points.map { toDrawing($0.location) }
            selection = DrawingLasso.select(polygon: polygon, in: drawing, items: onLasso == nil ? [] : items)
            expected = DrawingSignature(drawing)
        case .resize:
            break
        case .ink:
            guard ink.tool != .eraser, !points.isEmpty else { return }
            var result = drawing
            result.strokes.append(makeStroke())
            onChange(result, true)
        }
    }

    // MARK: Правка выделенного

    /// Поднимает обведённые штрихи из рисунка. Это первый шаг отмены всего движения.
    private func liftIfNeeded() {
        guard lift == nil, let selection else { return }
        let strokes = DrawingLasso.strokes(selection.strokes, of: drawing)
        let base = DrawingLasso.removing(selection.strokes, from: drawing)
        let bounds = LassoGeometry.strokesBounds(strokes)
        let image = strokes.isEmpty || bounds.isNull ? nil : DrawingSupport.image(
            of: PKDrawing(strokes: strokes),
            in: bounds,
            scale: min(max(scale * displayScale, 1), 3),
            isDark: isDark
        )
        lift = Lift(selection: selection, base: base, strokes: strokes, items: items, image: image)
        if !strokes.isEmpty {
            emit(drawing: base, items: nil, newStep: true)
        } else {
            emit(drawing: nil, items: items, newStep: true)
        }
    }

    private func resize(by translation: CGSize) {
        if lift == nil {
            mode = .resize
            liftIfNeeded()
        }
        guard let current = lift, !current.selection.bounds.isNull, current.selection.bounds.width > 0 else { return }
        let bounds = current.selection.bounds
        let width = max(bounds.width + translation.width / scale, 8)
        let factor = max(width / bounds.width, 0.1)
        lift?.transform = DrawingLasso.scaling(factor, around: bounds.origin)
        emitLiveItems()
    }

    /// Тексты и картинки двигаются вживую: они лёгкие, в отличие от штрихов.
    private func emitLiveItems() {
        guard let lift, !lift.selection.items.isEmpty else { return }
        let moved = lift.items.map { lift.selection.items.contains($0.id) ? DrawingLasso.transformed($0, by: lift.transform) : $0 }
        emit(drawing: nil, items: moved, newStep: false)
    }

    /// Кладёт поднятое на новое место одним шагом отмены вместе с подъёмом.
    private func dropLift() {
        defer { mode = .ink }
        guard let current = lift else { return }
        lift = nil
        var result = current.base
        let start = result.strokes.count
        result.strokes.append(contentsOf: DrawingLasso.transformed(current.strokes, by: current.transform))
        let movedItems = current.items.map {
            current.selection.items.contains($0.id) ? DrawingLasso.transformed($0, by: current.transform) : $0
        }
        var moved = LassoSelection(strokes: Array(start..<result.strokes.count), items: current.selection.items, bounds: .null)
        moved.bounds = DrawingLasso.bounds(of: moved, in: result, items: movedItems)
        selection = moved
        emit(drawing: current.strokes.isEmpty ? nil : result, items: current.selection.items.isEmpty ? nil : movedItems, newStep: false)
    }

    private func recolor(_ color: HexColor) {
        applyResult { DrawingLasso.recoloring($0, to: color, in: drawing, items: items) }
    }

    private func applyResult(_ make: (LassoSelection) -> DrawingLasso.Result) {
        guard let selection else { return }
        let result = make(selection)
        self.selection = result.selection
        emit(drawing: result.drawing, items: result.items, newStep: true)
    }

    /// Перекраска из общей панели пера достаётся выделению этого слоя. Замыкание ставится
    /// заново при каждой правке, чтобы оно видело свежий рисунок.
    private func installRecolor() {
        if selection != nil {
            ink.recolorOwner = token
            ink.recolorLassoSelection = { color in recolor(color) }
        } else if ink.recolorOwner == token {
            ink.recolorLassoSelection = nil
            ink.recolorOwner = nil
        }
    }

    private func clearSelection() {
        if lift != nil { dropLift() }
        selection = nil
    }

    private func emit(drawing newDrawing: PKDrawing?, items newItems: [NotebookItem]?, newStep: Bool) {
        if let newDrawing { expected = DrawingSignature(newDrawing) }
        if let onLasso {
            onLasso(newDrawing, newItems, newStep)
        } else if let newDrawing {
            onChange(newDrawing, newStep)
        }
    }

    private func makeStroke() -> PKStroke {
        let size = CGSize(width: ink.width, height: ink.width)
        var controlPoints = points.map { point in
            PKStrokePoint(
                location: toDrawing(point.location),
                timeOffset: point.time,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        // Щелчок без движения: точка из двух совпадающих точек, иначе PencilKit её не нарисует.
        if controlPoints.count == 1, let only = controlPoints.first {
            controlPoints.append(PKStrokePoint(
                location: CGPoint(x: only.location.x + 0.5, y: only.location.y),
                timeOffset: only.timeOffset + 0.01,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ))
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: startedAt)
        return PKStroke(ink: PKInk(ink.tool.inkType, color: ink.nsColor), path: path)
    }
}

/// Рамка штрихов без учёта текстов и картинок.
enum LassoGeometry {
    static func strokesBounds(_ strokes: [PKStroke]) -> CGRect {
        strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
    }
}

/// Панель пера на Mac: ручка, карандаш, маркер, ластик, последние цвета, вся палитра и толщина.
struct MouseInkBar: View {
    private var ink: MouseInk { .shared }
    @State private var isPaletteShown = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(MouseInk.Tool.allCases) { tool in
                    Button {
                        ink.tool = tool
                    } label: {
                        Image(systemName: tool.symbolName)
                            .font(.body.weight(.medium))
                            .frame(width: 30, height: 28)
                            .background(
                                ink.tool == tool ? theme.accent.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .foregroundStyle(ink.tool == tool ? theme.accent : theme.textPrimary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)
                    .accessibilityLabel(tool.title)
                }
            }
            Divider().frame(height: 20)
            HStack(spacing: 5) {
                ForEach(ink.recentColors, id: \.self) { color in
                    ColorDot(color: color, isSelected: ink.color == color && ink.tool != .eraser, size: 18) {
                        ink.choose(color, remember: false)
                    }
                }
                Button {
                    isPaletteShown = true
                } label: {
                    Image(systemName: "paintpalette")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textPrimary)
                .help("Все цвета и толщина")
                .popover(isPresented: $isPaletteShown, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 14) {
                        ColorPalette(selection: ink.color) { color in
                            ink.choose(color, remember: true)
                        }
                        WidthSlider(title: "Ручка и карандаш", value: Binding(get: { ink.penWidth }, set: { ink.penWidth = $0 }), range: MouseInk.penWidthRange)
                        WidthSlider(title: "Маркер", value: Binding(get: { ink.markerWidth }, set: { ink.markerWidth = $0 }), range: MouseInk.markerWidthRange)
                    }
                    .padding(16)
                    .frame(width: 360)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.textSecondary.opacity(0.15), lineWidth: 1))
    }
}

/// Толщина пера ползунком, с кружком той же толщины.
private struct WidthSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(value, format: .number.precision(.fractionLength(0...1))) пт")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                Circle()
                    .fill(theme.textPrimary)
                    .frame(width: min(value, 28), height: min(value, 28))
                    .frame(width: 30, height: 30)
            }
        }
    }
}
#endif
