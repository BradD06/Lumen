import SwiftUI

/// Фон окна «Острова»: ровный цвет темы, без картинок и пятен.
public struct ThemedBackground: View {
    @Environment(\.lumenTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            theme.backgroundGradient
            if theme.glowStrength > 0 {
                RadialGradient(
                    colors: [theme.glow.opacity(theme.glowStrength), theme.glow.opacity(0)],
                    center: UnitPoint(x: 0.88, y: 0.0),
                    startRadius: 0,
                    endRadius: 620
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

extension View {
    /// Матовое стекло любой формы: размытие, цвет стекла темы и тонкая обводка.
    public func lumenGlass<S: InsettableShape>(_ shape: S, prominent: Bool = false) -> some View {
        modifier(GlassModifier(shape: shape, prominent: prominent))
    }
}

private struct GlassModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.lumenTheme) private var theme
    let shape: S
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .background {
                // Тень отбрасывает само стекло, а не всё, что на нём: так её не надо пересчитывать,
                // когда меняется текст или значки, и у букв нет своей тени.
                shape.fill(prominent ? .regularMaterial : .ultraThinMaterial)
                    .overlay(shape.fill(theme.glassFill))
                    .shadow(color: .black.opacity(theme.shadowOpacity * 1.6), radius: 15, y: 8)
            }
            .overlay(shape.strokeBorder(theme.glassEdge, lineWidth: 1))
    }
}

extension Theme {
    /// Обводка стекла и карточек: тонкая и ровная.
    public var glassEdge: LinearGradient {
        LinearGradient(colors: [cardStroke, cardStroke], startPoint: .top, endPoint: .bottom)
    }
}

public enum CardStyle: Sendable, Equatable {
    /// Лист: непрозрачная карточка цвета листа с мягкой тенью.
    case glass
    /// Яркая карточка из палитры темы.
    case vivid(Int)
}

private struct LumenCardModifier: ViewModifier {
    @Environment(\.lumenTheme) private var theme
    let style: CardStyle
    let padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(foreground)
            // Обрезается только содержимое: тень у фона карточки ниже, и обрезка её бы съела.
            .clipShape(shape)
            .background {
                cardBackground(shape)
                    .shadow(color: .black.opacity(theme.shadowOpacity * 0.5), radius: 1, y: 1)
                    .shadow(color: .black.opacity(theme.shadowOpacity), radius: 18, y: 10)
            }
            .overlay(shape.strokeBorder(theme.glassEdge, lineWidth: 1))
    }

    @ViewBuilder
    private func cardBackground(_ shape: RoundedRectangle) -> some View {
        switch style {
        case .glass:
            shape.fill(theme.sheet)
        case .vivid(let index):
            shape.fill(
                LinearGradient(
                    colors: theme.vividCard(index).colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var foreground: Color {
        switch style {
        case .glass: theme.textPrimary
        case .vivid(let index): theme.vividCard(index).foreground
        }
    }
}

extension View {
    /// Оформляет содержимое как карточку-виджет.
    public func lumenCard(_ style: CardStyle = .glass, padding: CGFloat = 16) -> some View {
        modifier(LumenCardModifier(style: style, padding: padding))
    }
}

/// Карточка с крупным числом и подписью: «Входящие 3», «Страница 354 из 759».
public struct StatCard: View {
    let title: String
    let value: String
    let caption: String?
    let systemImage: String
    let style: CardStyle

    public init(title: String, value: String, caption: String? = nil, systemImage: String, style: CardStyle = .glass) {
        self.title = title
        self.value = value
        self.caption = caption
        self.systemImage = systemImage
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                Spacer()
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.8)
            }
            Text(value)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .opacity(0.75)
                    .lineLimit(2)
            }
        }
        .lumenCard(style)
    }
}

#Preview("Карточки") {
    VStack(spacing: 14) {
        HStack(spacing: 14) {
            StatCard(title: "Прогресс", value: "354", caption: "из 759 страниц", systemImage: "book", style: .vivid(1))
            StatCard(title: "Время", value: "6:24", caption: "сегодня", systemImage: "clock", style: .vivid(0))
        }
        StatCard(title: "Входящие", value: "3", caption: "ждут разбора", systemImage: "tray")
    }
    .padding()
    .background(ThemedBackground())
}
