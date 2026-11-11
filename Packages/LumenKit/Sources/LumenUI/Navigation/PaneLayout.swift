import LumenCore
import LumenThemes
import SwiftUI

/// Два окна и ручка между ними: рядом или друг под другом, в прямом или обратном порядке.
/// Дети всегда идут в одном порядке (первое окно, ручка, второе окно), а расставляет их раскладка.
/// Поэтому при смене расположения окна не создаются заново: книга не перезагружается,
/// а курсор в заметке остаётся на месте.
struct TwoPaneLayout: Layout {
    var axis: PaneArrangement.Axis
    var isSwapped = false
    /// Доля второго окна от места без ручки.
    var secondFraction: CGFloat
    var gap: CGFloat
    /// Меньше этого окно не сжимается, пока места хватает на оба.
    var minLength: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Второго окна нет (заметки скрыты): первое занимает всё место.
        guard subviews.count >= 3 else {
            for subview in subviews {
                subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
            }
            return
        }
        let lengths = Self.lengths(
            total: axis == .stacked ? bounds.height : bounds.width,
            fraction: secondFraction,
            gap: gap,
            minLength: minLength
        )
        let ordered: [(LayoutSubview, CGFloat)] = isSwapped
            ? [(subviews[2], lengths.second), (subviews[1], gap), (subviews[0], lengths.first)]
            : [(subviews[0], lengths.first), (subviews[1], gap), (subviews[2], lengths.second)]
        var offset: CGFloat = 0
        for (subview, length) in ordered {
            if axis == .stacked {
                subview.place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY + offset),
                    proposal: ProposedViewSize(width: bounds.width, height: length)
                )
            } else {
                subview.place(
                    at: CGPoint(x: bounds.minX + offset, y: bounds.minY),
                    proposal: ProposedViewSize(width: length, height: bounds.height)
                )
            }
            offset += length
        }
        // Всё, что сверх трёх (не должно быть), не показываем поверх окон.
        for subview in subviews.dropFirst(3) {
            subview.place(at: bounds.origin, proposal: .zero)
        }
    }

    /// Длины первого и второго окна: второе по своей доле, но оба не меньше `minLength`.
    static func lengths(total: CGFloat, fraction: CGFloat, gap: CGFloat, minLength: CGFloat) -> (first: CGFloat, second: CGFloat) {
        let available = max(total - gap, 0)
        let minimum = min(minLength, available / 2)
        let second = min(max((available * fraction).rounded(), minimum), available - minimum)
        return (available - second, second)
    }
}

/// «Окна»: рядом, друг под другом и поменять местами. Стоит в панели окна,
/// у читалки (книга и заметки) и у разделённого экрана (две панели).
struct PaneArrangementControls: View {
    let axis: PaneArrangement.Axis
    /// Как называть то, что стоит в окнах, в подсказках: «книгу и заметки», «панели».
    var subject = "окна"
    var onAxis: (PaneArrangement.Axis) -> Void
    var onSwap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("Окна", selection: Binding(get: { axis }, set: { onAxis($0) })) {
                Label("Рядом", systemImage: "rectangle.split.2x1")
                    .tag(PaneArrangement.Axis.sideBySide)
                Label("Друг под другом", systemImage: "rectangle.split.1x2")
                    .tag(PaneArrangement.Axis.stacked)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .fixedSize()
            .help("Как поставить \(subject): рядом или друг под другом")
            Button(action: onSwap) {
                Label(
                    "Поменять местами",
                    systemImage: axis == .stacked ? "arrow.up.arrow.down" : "arrow.left.arrow.right"
                )
            }
            .help("Поменять \(subject) местами")
        }
        .accessibilityLabel("Окна")
    }
}

/// Ручка между двумя окнами: тянется мышью или пальцем, двойной щелчок возвращает доли по умолчанию.
struct PaneDivider: View {
    let axis: PaneArrangement.Axis
    let isActive: Bool
    var label = "Граница окон"
    var onHover: (Bool) -> Void = { _ in }

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let isStacked = axis == .stacked
        Capsule()
            .fill(theme.textSecondary.opacity(isActive ? 0.6 : 0.22))
            .frame(width: isStacked ? 44 : 4, height: isStacked ? 4 : 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                onHover(hovering)
                #if os(macOS)
                if hovering {
                    (isStacked ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                } else {
                    NSCursor.pop()
                }
                #endif
            }
            .accessibilityLabel(label)
    }
}
