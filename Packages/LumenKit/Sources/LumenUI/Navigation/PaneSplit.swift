import LumenCore
import LumenThemes
import SwiftUI

/// Как выглядят панели разделённого экрана: скругление, просвет между ними и отступ от краёв окна.
enum PaneStyle {
    static let radius: CGFloat = 24
    static let gap: CGFloat = 14
    static let inset: CGFloat = 10
    static let minWidth: CGFloat = 320
    /// Друг под другом панель не ниже этого, пока окно позволяет.
    static let minHeight: CGFloat = 200
}

/// Две панели с просветом между ними: рядом или друг под другом. Просвет тянется мышью
/// или пальцем, так меняется размер панелей. Двойной щелчок по нему делит экран поровну.
struct PaneSplit<Leading: View, Trailing: View>: View {
    var axis: PaneArrangement.Axis = .sideBySide
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    /// Доля второй панели: своя для «рядом» и «друг под другом».
    @State private var fractions: [PaneArrangement.Axis: CGFloat] = [:]
    @State private var dragStart: CGFloat?
    @State private var isHovered = false

    private var fraction: CGFloat { fractions[axis] ?? 0.5 }

    var body: some View {
        GeometryReader { geometry in
            let length = axis == .stacked ? geometry.size.height : geometry.size.width
            TwoPaneLayout(
                axis: axis,
                secondFraction: fraction,
                gap: PaneStyle.gap,
                minLength: minLength
            ) {
                leading
                handle(length: length)
                trailing
            }
        }
        .frame(minWidth: axis == .stacked ? PaneStyle.minWidth : PaneStyle.minWidth * 2 + PaneStyle.gap)
    }

    private var minLength: CGFloat {
        axis == .stacked ? PaneStyle.minHeight : PaneStyle.minWidth
    }

    private func handle(length: CGFloat) -> some View {
        let available = max(length - PaneStyle.gap, 1)
        return PaneDivider(axis: axis, isActive: isHovered || dragStart != nil, label: "Граница панелей") { hovering in
            withAnimation(LumenMotion.quick) { isHovered = hovering }
        }
        .gesture(
            // Сдвиг считается в координатах окна: ручка едет вместе с мышью,
            // и в её собственных координатах панели дёргались бы.
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStart ?? fraction
                    if dragStart == nil { dragStart = start }
                    let delta = axis == .stacked ? value.translation.height : value.translation.width
                    let lengths = TwoPaneLayout.lengths(
                        total: length,
                        fraction: start - delta / available,
                        gap: PaneStyle.gap,
                        minLength: minLength
                    )
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { fractions[axis] = lengths.second / available }
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture(count: 2) {
            withAnimation(LumenMotion.standard) { fractions[axis] = 0.5 }
        }
        .help(axis == .stacked
            ? "Потяните, чтобы поменять высоту панелей. Двойной щелчок делит поровну"
            : "Потяните, чтобы поменять ширину панелей. Двойной щелчок делит поровну")
        .accessibilityElement()
        .accessibilityLabel("Граница панелей")
        .accessibilityValue("\(Int(((1 - fraction) * 100).rounded())) процентов у первой панели")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = direction == .increment ? -0.05 : 0.05
            fractions[axis] = min(max(fraction + step, 0.15), 0.85)
        }
    }
}

/// Панель разделённого экрана как отдельная скруглённая карточка.
/// Активная панель обведена цветом темы, чтобы было видно, куда откроется выбранное в сайдбаре.
struct PaneCard: ViewModifier {
    let isFocused: Bool

    @Environment(\.lumenTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaneStyle.radius, style: .continuous)
        content
            .background(shape.fill(theme.cardFill.opacity(0.35)))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isFocused ? theme.accent.opacity(0.45) : theme.cardStroke, lineWidth: 1)
                    .animation(LumenMotion.quick, value: isFocused)
            }
            .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
    }
}

extension View {
    func paneCard(isFocused: Bool) -> some View {
        modifier(PaneCard(isFocused: isFocused))
    }
}
