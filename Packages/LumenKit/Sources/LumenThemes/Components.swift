import SwiftUI

/// Фон рабочего пространства: градиент темы и мягкое закатное свечение.
public struct ThemedBackground: View {
    @Environment(\.lumenTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            theme.backgroundGradient
            RadialGradient(
                colors: [theme.glow.opacity(0.45), theme.glow.opacity(0)],
                center: UnitPoint(x: 0.85, y: 0.0),
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [theme.accent.opacity(0.18), theme.accent.opacity(0)],
                center: UnitPoint(x: 0.05, y: 1.0),
                startRadius: 0,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

public enum CardStyle: Sendable, Equatable {
    /// Полупрозрачная карточка на фоне темы.
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
            .background {
                switch style {
                case .glass:
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(theme.cardFill))
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
            .overlay(shape.strokeBorder(theme.cardStroke, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
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
    .preferredColorScheme(.dark)
}
