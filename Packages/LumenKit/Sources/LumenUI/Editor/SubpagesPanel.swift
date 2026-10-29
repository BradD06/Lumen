import LumenCore
import LumenThemes
import SwiftUI

/// Панель справа со списком подстраниц открытой страницы и кнопкой для новой.
struct SubpagesPanel: View {
    let subpages: [Page]
    var onOpen: (UUID) -> Void
    var onAdd: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Подстраницы")
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    if !subpages.isEmpty {
                        Text("\(subpages.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(theme.cardFill, in: Capsule())
                    }
                }
                .padding(.bottom, 4)

                if subpages.isEmpty {
                    Text("Подстраниц пока нет")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                }

                ForEach(subpages) { page in
                    Button {
                        onOpen(page.id)
                    } label: {
                        SubpageCard(page: page)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onAdd) {
                    Label("Новая подстраница", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.textSecondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
        .background(theme.backgroundGradient.opacity(0.6))
    }
}

/// Строка подстраницы: цветная тетрадка или иконка, название и когда менялась.
private struct SubpageCard: View {
    let page: Page

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            glyph
            VStack(alignment: .leading, spacing: 2) {
                Text(page.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(page.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: shape)
        .background(theme.cardFill, in: shape)
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
            lineWidth: 1
        ))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 5)
        .contentShape(shape)
    }

    /// Та же тетрадка, что на холсте библиотеки, только маленькая.
    @ViewBuilder
    private var glyph: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 5, topTrailingRadius: 5,
            style: .continuous
        )
        ZStack {
            shape.fill(LinearGradient(
                colors: theme.vividCard(Int(page.id.uuid.0)).colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            if let icon = page.icon, !icon.isEmpty {
                Text(icon).font(.system(size: 15))
            }
        }
        .frame(width: 26, height: 34)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}
