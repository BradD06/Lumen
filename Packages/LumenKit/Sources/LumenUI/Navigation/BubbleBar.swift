import LumenThemes
import SwiftUI

/// Размеры капсулы с кружком: открытый раздел выпрыгивает кружком над капсулой,
/// под кружком в капсуле вырез. Общие для острова на Mac и iPad и капсулы iPhone.
enum BubbleMetrics {
    /// Диаметр кружка.
    static let bubble: CGFloat = 46
    /// Зазор между кружком и краем выреза.
    static let gap: CGFloat = 7
    /// Центр кружка ниже верхнего края капсулы: кружок сидит в ней, а не висит над ней.
    static let centerY: CGFloat = 6
    /// Скруглённые плечики, которыми вырез переходит в верхний край.
    static let shoulder: CGFloat = 12
    /// Насколько кружок выступает над капсулой: столько места оставлять сверху.
    static let lift: CGFloat = bubble / 2 - centerY
}

/// Капсула с круглым вырезом под кружком. `notch` от 0 (ровная капсула) до 1 (вырез целиком):
/// так вырез плавно появляется, когда раздел открывается, и уходит, когда открыта книга или страница.
/// `notchX` и `notch` анимируются вместе, поэтому вырез едет за кружком.
struct NotchedCapsule: InsettableShape {
    var notchX: CGFloat
    var notch: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(notchX, notch) }
        set {
            notchX = newValue.first
            notch = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let body = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let capsule = Path(roundedRect: body, cornerRadius: body.height / 2)
        guard notch > 0.01 else { return capsule }

        let radius = BubbleMetrics.bubble / 2 + BubbleMetrics.gap + insetAmount
        // Пока вырез появляется, его круг поднимается из-за верхнего края.
        let centerY = rect.minY + BubbleMetrics.centerY - (1 - notch) * (radius + BubbleMetrics.centerY + 2)
        let top = body.minY
        let x = rect.minX + notchX
        let depth = centerY - top
        guard depth > -radius else { return capsule }

        let circle = Path(ellipseIn: CGRect(x: x - radius, y: centerY - radius, width: radius * 2, height: radius * 2))
        let y1 = max(top + 5, centerY + 2)
        guard y1 - centerY < radius else { return capsule.subtracting(circle) }

        // Где круг пересекает верхний край, и откуда к нему идут плечики.
        let edge = (radius * radius - depth * depth).squareRoot()
        let side = (radius * radius - (y1 - centerY) * (y1 - centerY)).squareRoot()
        let shoulder = BubbleMetrics.shoulder * notch
        var cut = Path()
        cut.move(to: CGPoint(x: x - edge - shoulder, y: top - 60))
        cut.addLine(to: CGPoint(x: x - edge - shoulder, y: top))
        cut.addQuadCurve(to: CGPoint(x: x - side, y: y1), control: CGPoint(x: x - edge, y: top))
        cut.addLine(to: CGPoint(x: x + side, y: y1))
        cut.addQuadCurve(to: CGPoint(x: x + edge + shoulder, y: top), control: CGPoint(x: x + edge, y: top))
        cut.addLine(to: CGPoint(x: x + edge + shoulder, y: top - 60))
        cut.closeSubpath()
        return capsule.subtracting(cut.union(circle))
    }

    func inset(by amount: CGFloat) -> NotchedCapsule {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// Стеклянная капсула с вырезом и кружком открытого раздела над ним.
/// `bubbleX` считается от левого края капсулы; `nil` = ни один раздел не открыт, капсула ровная.
struct BubbleBar<Content: View>: View {
    let height: CGFloat
    let bubbleX: CGFloat?
    let bubbleImage: String
    var bubbleCount = 0
    @ViewBuilder var content: Content

    /// Где кружок был в последний раз: когда раздел снова открывается, вырез растёт на месте, а не едет от края.
    @State private var lastX: CGFloat = 0

    var body: some View {
        let x = bubbleX ?? lastX
        content
            .frame(height: height)
            .lumenGlass(NotchedCapsule(notchX: x, notch: bubbleX == nil ? 0 : 1))
            .overlay(alignment: .topLeading) {
                if bubbleX != nil {
                    SelectionBubble(systemImage: bubbleImage, count: bubbleCount)
                        .offset(x: x - BubbleMetrics.bubble / 2, y: BubbleMetrics.centerY - BubbleMetrics.bubble / 2)
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
            }
            .onChange(of: bubbleX, initial: true) { _, new in
                if let new { lastX = new }
            }
    }
}

/// Кружок открытого раздела: значок раздела на акценте, число неразобранных переезжает сюда же.
private struct SelectionBubble: View {
    let systemImage: String
    let count: Int
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(theme.onAccent)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: BubbleMetrics.bubble, height: BubbleMetrics.bubble)
            .background {
                Circle()
                    .fill(theme.accent)
                    .shadow(color: .black.opacity(theme.shadowOpacity * 1.2), radius: 8, y: 5)
            }
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    CountBadge(count: count, onAccent: true)
                        .offset(x: 3, y: -2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Значок с подписью под ним. У открытого раздела значок уезжает в кружок, подпись остаётся и темнеет.
struct BubbleBarLabel: View {
    let title: String
    let systemImage: String
    var isOn = false
    var count = 0
    /// Цвет кнопки, которая не раздел («Создать» акцентом).
    var tint: Color?
    let width: CGFloat?
    let height: CGFloat
    var iconSize: CGFloat = 19
    var fontSize: CGFloat = 11

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: tint == nil ? .regular : .semibold))
                .frame(height: 24)
                .opacity(isOn ? 0 : 1)
                .scaleEffect(isOn ? 0.7 : 1)
                .offset(y: isOn ? -14 : 0)
                .overlay(alignment: .topTrailing) {
                    if count > 0 && !isOn {
                        CountBadge(count: count)
                            .offset(x: 10, y: -4)
                    }
                }
            Text(title)
                .font(.system(size: fontSize, weight: isOn ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOn ? theme.textPrimary : (tint ?? theme.textSecondary))
        }
        .foregroundStyle(tint ?? theme.textSecondary)
        .padding(.top, 12)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height, alignment: .top)
        .contentShape(Rectangle())
    }
}
