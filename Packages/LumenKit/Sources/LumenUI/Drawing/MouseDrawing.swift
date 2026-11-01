#if os(macOS)
import AppKit
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
    var color: InkColor = .black
    var size: InkSize = .medium

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

    enum InkColor: String, CaseIterable, Identifiable {
        case black, blue, red, green, orange, purple, yellow

        var id: String { rawValue }

        var title: String {
            switch self {
            case .black: "Чёрный"
            case .blue: "Синий"
            case .red: "Красный"
            case .green: "Зелёный"
            case .orange: "Оранжевый"
            case .purple: "Фиолетовый"
            case .yellow: "Жёлтый"
            }
        }

        /// Цвет для светлой темы: в нём PencilKit хранит чернила.
        var rgb: (Double, Double, Double) {
            switch self {
            case .black: (0.08, 0.08, 0.10)
            case .blue: (0.16, 0.42, 0.90)
            case .red: (0.88, 0.24, 0.24)
            case .green: (0.18, 0.62, 0.34)
            case .orange: (0.95, 0.52, 0.20)
            case .purple: (0.55, 0.34, 0.86)
            case .yellow: (0.98, 0.80, 0.16)
            }
        }

        var nsColor: NSColor {
            NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }

        /// Как цвет выглядит на экране. На тёмном фоне чёрная ручка пишет белым, как и у PencilKit.
        func display(isDark: Bool) -> Color {
            if isDark, self == .black { return Color(white: 0.94) }
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }
    }

    enum InkSize: String, CaseIterable, Identifiable {
        case thin, medium, thick

        var id: String { rawValue }

        var title: String {
            switch self {
            case .thin: "Тонко"
            case .medium: "Средне"
            case .thick: "Толсто"
            }
        }
    }

    /// Толщина штриха в пунктах рисунка.
    var width: CGFloat {
        let widths: [CGFloat] = switch tool {
        case .pen, .eraser: [2, 4, 7]
        case .pencil: [2, 3.5, 6]
        case .marker: [12, 20, 30]
        }
        return widths[InkSize.allCases.firstIndex(of: size) ?? 1]
    }

    /// Ластик стирает штрихи целиком, которых касается в этом радиусе (в пунктах экрана).
    var eraserRadius: CGFloat {
        [6, 10, 18][InkSize.allCases.firstIndex(of: size) ?? 1]
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
        return PKStroke(ink: PKInk(ink.tool.inkType, color: ink.color.nsColor), path: path)
    }
}

/// Панель пера на Mac: ручка, карандаш, маркер, ластик, цвет и толщина.
struct MouseInkBar: View {
    private var ink: MouseInk { .shared }
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
            HStack(spacing: 6) {
                ForEach(MouseInk.InkColor.allCases) { color in
                    Button {
                        ink.color = color
                        if ink.tool == .eraser { ink.tool = .pen }
                    } label: {
                        Circle()
                            .fill(color.display(isDark: true))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                            .padding(3)
                            .overlay(
                                Circle().strokeBorder(theme.accent, lineWidth: ink.color == color ? 2 : 0)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                    .accessibilityLabel(color.title)
                }
            }
            Divider().frame(height: 20)
            HStack(spacing: 4) {
                ForEach(Array(MouseInk.InkSize.allCases.enumerated()), id: \.element) { index, size in
                    Button {
                        ink.size = size
                    } label: {
                        Circle()
                            .fill(theme.textPrimary)
                            .frame(width: CGFloat(4 + index * 4), height: CGFloat(4 + index * 4))
                            .frame(width: 24, height: 24)
                            .background(
                                ink.size == size ? theme.accent.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(size.title)
                    .accessibilityLabel(size.title)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.textSecondary.opacity(0.15), lineWidth: 1))
    }
}
#endif
