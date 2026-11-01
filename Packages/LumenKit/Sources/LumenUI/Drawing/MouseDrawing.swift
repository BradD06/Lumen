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

    /// Выбрать цвет. Цвет из палитры запоминается среди последних, выбор из последних их не переставляет.
    func choose(_ color: HexColor, remember: Bool) {
        self.color = color
        if tool == .eraser { tool = .pen }
        if remember { rememberRecent(color) }
    }

    private func rememberRecent(_ color: HexColor) {
        var colors = recentColors.filter { $0 != color }
        colors.insert(color, at: 0)
        recentColors = Array(colors.prefix(Self.recentLimit))
        UserDefaults.standard.set(recentColors.map(\.hex), forKey: Self.recentKey)
    }

    enum Tool: String, CaseIterable, Identifiable {
        case pen, pencil, marker, eraser

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pen: "Ручка"
            case .pencil: "Карандаш"
            case .marker: "Маркер"
            case .eraser: "Ластик"
            }
        }

        var symbolName: String {
            switch self {
            case .pen: "pencil.tip"
            case .pencil: "pencil"
            case .marker: "highlighter"
            case .eraser: "eraser"
            }
        }

        var inkType: PKInk.InkType {
            switch self {
            case .pen, .eraser: .pen
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
    /// Новый рисунок. Второй аргумент говорит, начинается ли новый шаг отмены.
    var onChange: (PKDrawing, Bool) -> Void

    private struct TimedPoint {
        var location: CGPoint
        var time: TimeInterval
    }

    @State private var points: [TimedPoint] = []
    @State private var startedAt = Date()
    @State private var isDragging = false
    /// Рисунок во время стирания: ластик за одно движение задевает много штрихов.
    @State private var erasing: PKDrawing?
    private var ink: MouseInk { .shared }

    var body: some View {
        Canvas { context, _ in
            guard let first = points.first, ink.tool != .eraser else { return }
            var path = Path()
            path.move(to: first.location)
            for point in points.dropFirst() {
                path.addLine(to: point.location)
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
                .onEnded { _ in dragEnded() }
        )
        .pointerStyle(.rectSelection)
        .accessibilityLabel("Холст для рисования")
    }

    private func toDrawing(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale + origin.x, y: point.y / scale + origin.y)
    }

    private func dragChanged(_ value: DragGesture.Value) {
        if !isDragging {
            isDragging = true
            startedAt = Date()
            points = []
            erasing = nil
        }
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

    private func dragEnded() {
        defer {
            isDragging = false
            points = []
            erasing = nil
        }
        guard ink.tool != .eraser, !points.isEmpty else { return }
        var result = drawing
        result.strokes.append(makeStroke())
        onChange(result, true)
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
