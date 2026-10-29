import LumenThemes
import SwiftUI

/// Карта документа у правого края: по полоске на заголовок, длина по уровню.
/// Полоска заголовка, который сейчас на экране, подсвечена. При наведении (на iPhone и iPad
/// по касанию) карта раскрывается в карточку с названиями. Щелчок прокручивает к заголовку.
struct PageOutlineView: View {
    let items: [OutlineItem]
    let currentId: UUID?
    var onSelect: (OutlineItem) -> Void

    @State private var isExpanded = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if isExpanded {
                expanded
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            } else {
                strip
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.25), value: isExpanded)
        #if os(macOS)
        .onHover { isExpanded = $0 }
        #endif
    }

    /// Полоски заголовков.
    private var strip: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ForEach(items) { item in
                Capsule()
                    .fill(item.id == currentId ? theme.accent : theme.textSecondary.opacity(0.45))
                    .frame(width: barWidth(item.level), height: 3)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        #if os(iOS)
        .onTapGesture { isExpanded = true }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Карта документа: заголовков \(items.count)")
        .accessibilityAction(named: "Показать заголовки") { isExpanded = true }
    }

    /// Карточка с названиями заголовков.
    private var expanded: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                        #if os(iOS)
                        isExpanded = false
                        #endif
                    } label: {
                        HStack(spacing: 8) {
                            Capsule()
                                .fill(item.id == currentId ? theme.accent : theme.textSecondary.opacity(0.45))
                                .frame(width: barWidth(item.level) / 2, height: 3)
                            Text(item.title)
                                .font(item.level == 1 ? .callout.weight(.semibold) : .callout)
                                .foregroundStyle(item.id == currentId ? theme.accent : theme.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.leading, CGFloat(item.level - 1) * 12)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 240)
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: shape)
        .background(theme.cardFill, in: shape)
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
            lineWidth: 1
        ))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
        #if os(iOS)
        .overlay(alignment: .topTrailing) {
            Button {
                isExpanded = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        #endif
    }

    private func barWidth(_ level: Int) -> CGFloat {
        switch level {
        case 1: 22
        case 2: 15
        default: 9
        }
    }
}
