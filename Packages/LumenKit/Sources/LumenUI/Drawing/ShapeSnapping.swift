import CoreGraphics
import Foundation
import LumenCore
import LumenThemes
import PencilKit
import SwiftUI

/// Режим «Фигуры»: каждый штрих, в котором узнаётся линия, круг или многоугольник, становится ровным.
/// Без режима ровной фигура становится, если в конце штриха задержать перо (`ShapeRecognizer.holdToSnap`).
/// Один режим на всё приложение, он помнится между запусками.
@MainActor
@Observable
final class ShapeSnap {
    static let shared = ShapeSnap()

    var isOn: Bool {
        didSet { UserDefaults.standard.set(isOn, forKey: Self.key) }
    }

    private static let key = "drawing.shapes"

    init() {
        isOn = UserDefaults.standard.bool(forKey: Self.key)
    }
}

/// Штрихи PencilKit и ровные фигуры: тот же цвет и толщина, но линии ровные.
enum ShapeStrokes {
    /// Точки штриха в координатах рисунка.
    static func points(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.map { $0.location.applying(stroke.transform) }
    }

    /// Сколько секунд перо простояло в конце штриха до `end`.
    static func holdDuration(of stroke: PKStroke, endedAt end: Date) -> TimeInterval {
        let path = stroke.path
        return ShapeRecognizer.holdDuration(
            points: path.map(\.location),
            times: path.map(\.timeOffset),
            end: end.timeIntervalSince(path.creationDate)
        )
    }

    /// Ровная фигура вместо штриха или `nil`, если фигуры в нём нет.
    static func snapped(_ stroke: PKStroke) -> PKStroke? {
        guard let shape = ShapeRecognizer.recognize(points(of: stroke)) else { return nil }
        return makeStroke(shape, like: stroke)
    }

    /// Штрих по контуру фигуры с чернилами и средней толщиной исходного штриха.
    static func makeStroke(_ shape: RecognizedShape, like stroke: PKStroke) -> PKStroke {
        let original = Array(stroke.path)
        let sizes = original.map(\.size).sorted { $0.width < $1.width }
        let size = sizes.isEmpty ? CGSize(width: 4, height: 4) : sizes[sizes.count / 2]
        let opacity = original.isEmpty ? 1 : original.map(\.opacity).reduce(0, +) / CGFloat(original.count)
        let sample = original.first
        let outline = ShapeRecognizer.outline(of: shape, spacing: max(2, size.width / 2))
        let duration = original.last?.timeOffset ?? 0
        let step = outline.count > 1 ? max(duration, 0.2) / Double(outline.count - 1) : 0
        let points = outline.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * step,
                size: size,
                opacity: opacity,
                force: sample?.force ?? 1,
                azimuth: sample?.azimuth ?? 0,
                altitude: sample?.altitude ?? .pi / 2
            )
        }
        return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate))
    }

    /// Только что нарисованный последний штрих, ставший ровной фигурой: в режиме «Фигуры»
    /// или если перо задержали в конце. `previousCount` штрихов было до него.
    @MainActor
    static func snappingNewStroke(in drawing: PKDrawing, previousCount: Int, now: Date = Date()) -> PKDrawing? {
        guard drawing.strokes.count == previousCount + 1, let last = drawing.strokes.last else { return nil }
        // Старый штрих (вернули отменой, вставили) не трогаем: только что дописанный.
        let ended = now.timeIntervalSince(last.path.creationDate) - (last.path.last?.timeOffset ?? 0)
        guard ended < 10 else { return nil }
        guard ShapeSnap.shared.isOn || holdDuration(of: last, endedAt: now) >= ShapeRecognizer.holdToSnap,
              let snapped = snapped(last) else { return nil }
        var result = drawing
        result.strokes[result.strokes.count - 1] = snapped
        return result
    }
}

/// Кнопка режима «Фигуры» рядом с пером.
struct ShapeSnapToggle: View {
    private var snap: ShapeSnap { .shared }
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button {
            snap.isOn.toggle()
        } label: {
            Image(systemName: "square.on.circle")
                .font(.body.weight(.medium))
                .frame(width: 30, height: 28)
                .background(
                    snap.isOn ? theme.accent.opacity(0.25) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .foregroundStyle(snap.isOn ? theme.accent : theme.textPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(snap.isOn
            ? "Фигуры включены: каждая линия, круг и многоугольник становятся ровными"
            : "Ровные фигуры: каждый штрих станет ровной линией, кругом или многоугольником. Или задержите перо в конце штриха")
        .accessibilityLabel("Ровные фигуры")
        .accessibilityValue(snap.isOn ? "Включены" : "Выключены")
    }
}
