import LumenThemes
import SwiftUI

/// Как выглядят панели разделённого экрана: скругление, просвет между ними и отступ от краёв окна.
enum PaneStyle {
    static let radius: CGFloat = 24
    static let gap: CGFloat = 14
    static let inset: CGFloat = 10
    static let minWidth: CGFloat = 320
}

/// Две панели рядом с просветом между ними. Просвет тянется мышью или пальцем,
/// так меняется ширина панелей. Двойной щелчок по нему делит экран поровну.
struct PaneSplit<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.lumenTheme) private var theme
    @State private var fraction: CGFloat = 0.5
    @State private var dragStart: CGFloat?
    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            let available = max(geometry.size.width - PaneStyle.gap, 0)
            let leadingWidth = width(of: fraction, in: available)
            HStack(spacing: 0) {
                leading.frame(width: leadingWidth)
                handle(available: available, leadingWidth: leadingWidth)
                trailing.frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: PaneStyle.minWidth * 2 + PaneStyle.gap)
    }

    /// Ширина левой панели: обе панели не уже минимальной, пока окно это позволяет.
    private func width(of fraction: CGFloat, in available: CGFloat) -> CGFloat {
        let minWidth = min(PaneStyle.minWidth, available / 2)
        return min(max(available * fraction, minWidth), available - minWidth).rounded()
    }

    private func handle(available: CGFloat, leadingWidth: CGFloat) -> some View {
        Capsule()
            .fill(theme.textSecondary.opacity(isHovered || dragStart != nil ? 0.6 : 0.18))
            .frame(width: 4, height: 44)
            .frame(width: PaneStyle.gap)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
                #if os(macOS)
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                #endif
            }
            .gesture(
                // Сдвиг считается в координатах окна: ручка едет вместе с мышью,
                // и в её собственных координатах панели дёргались бы.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? leadingWidth
                        if dragStart == nil { dragStart = start }
                        let newWidth = width(of: (start + value.translation.width) / max(available, 1), in: available)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { fraction = newWidth / max(available, 1) }
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { fraction = 0.5 }
            }
            .help("Потяните, чтобы поменять ширину панелей. Двойной щелчок делит поровну")
            .accessibilityElement()
            .accessibilityLabel("Граница панелей")
            .accessibilityValue("\(Int((fraction * 100).rounded())) процентов слева")
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = direction == .increment ? 0.05 : -0.05
                fraction = width(of: fraction + step, in: available) / max(available, 1)
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
            }
            .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
    }
}

extension View {
    func paneCard(isFocused: Bool) -> some View {
        modifier(PaneCard(isFocused: isFocused))
    }
}
