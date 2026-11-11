import SwiftUI

/// Фон кабинета: градиент схемы, за «стеклом» размыто виден книжный шкаф,
/// в углу тёплая лампа, в противоположном углу второй, холодный свет.
public struct ThemedBackground: View {
    @Environment(\.lumenTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            theme.backgroundGradient
            if theme.wallOpacity > 0, !theme.wallColors.isEmpty {
                BookcaseWall(colors: theme.wallColors, plank: theme.accent)
                    .blur(radius: 14)
                    .opacity(theme.wallOpacity)
            }
            RadialGradient(
                colors: [theme.glow.opacity(theme.glowStrength), theme.glow.opacity(0)],
                center: UnitPoint(x: 0.88, y: 0.0),
                startRadius: 0,
                endRadius: 620
            )
            RadialGradient(
                colors: [theme.glow2.opacity(theme.glowStrength * 0.55), theme.glow2.opacity(0)],
                center: UnitPoint(x: 0.04, y: 1.0),
                startRadius: 0,
                endRadius: 560
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

/// Ряды корешков и полок для фона. Рисуется один раз и размывается,
/// поэтому детали не нужны: только цвет, высота и ритм.
struct BookcaseWall: View {
    let colors: [Color]
    let plank: Color

    var body: some View {
        Canvas { context, size in
            let rowHeight: CGFloat = 200
            var top: CGFloat = 30
            var row = 0
            while top < size.height {
                let shelfY = top + rowHeight - 18
                var x: CGFloat = 16
                var index = row * 7
                while x < size.width {
                    let width = 14 + CGFloat((index * 37) % 17)
                    let height = 112 + CGFloat((index * 53) % 52)
                    let rect = CGRect(x: x, y: shelfY - height, width: width, height: height)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 2),
                        with: .color(colors[index % colors.count])
                    )
                    x += width + 3
                    // Иногда на полке пустое место, как в настоящем шкафу.
                    if index % 13 == 12 { x += 30 }
                    index += 1
                }
                context.fill(
                    Path(CGRect(x: 0, y: shelfY, width: size.width, height: 10)),
                    with: .color(plank.opacity(0.45))
                )
                top += rowHeight
                row += 1
            }
        }
    }
}

extension View {
    /// Матовое стекло любой формы: размытие, лёгкий цвет схемы и светлая кромка сверху.
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
                shape.fill(prominent ? .regularMaterial : .ultraThinMaterial)
                    .overlay(shape.fill(theme.cardFill))
            }
            .overlay(shape.strokeBorder(theme.glassEdge, lineWidth: 1))
            .shadow(color: .black.opacity(theme.shadowOpacity * 0.8), radius: 14, y: 6)
    }
}

extension Theme {
    /// Обводка стекла: светлее сверху, где на кромку падает свет лампы.
    public var glassEdge: LinearGradient {
        LinearGradient(
            colors: [glassHighlight, cardStroke, cardStroke.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
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
            .overlay(shape.strokeBorder(theme.glassEdge, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(theme.shadowOpacity), radius: 16, y: 8)
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
