import SwiftUI

/// Набор дизайн-токенов. Позже темы будут описываться JSON и распространяться через магазин,
/// пока есть одна встроенная тема «Закат».
public struct Theme: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Фон сверху вниз.
    public var backgroundStops: [Color]
    /// Тёплое свечение «солнца» в углу фона.
    public var glow: Color
    public var accent: Color
    public var textPrimary: Color
    public var textSecondary: Color
    /// Заливка и обводка стеклянных карточек.
    public var cardFill: Color
    public var cardStroke: Color
    public var cardRadius: CGFloat
    /// Яркие карточки-виджеты (как «Прогресс» и «Время» в референсе 03).
    public var vividCards: [VividCard]

    public struct VividCard: Sendable, Equatable {
        public var colors: [Color]
        /// Цвет текста на карточке.
        public var foreground: Color

        public init(colors: [Color], foreground: Color) {
            self.colors = colors
            self.foreground = foreground
        }
    }

    public init(
        id: String,
        name: String,
        backgroundStops: [Color],
        glow: Color,
        accent: Color,
        textPrimary: Color,
        textSecondary: Color,
        cardFill: Color,
        cardStroke: Color,
        cardRadius: CGFloat,
        vividCards: [VividCard]
    ) {
        self.id = id
        self.name = name
        self.backgroundStops = backgroundStops
        self.glow = glow
        self.accent = accent
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.cardFill = cardFill
        self.cardStroke = cardStroke
        self.cardRadius = cardRadius
        self.vividCards = vividCards
    }

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: backgroundStops, startPoint: .top, endPoint: .bottom)
    }

    public func vividCard(_ index: Int) -> VividCard {
        vividCards[((index % vividCards.count) + vividCards.count) % vividCards.count]
    }
}

extension Theme {
    /// Тёмная тема с тёплыми закатными градиентами: сливовый фон, персиковое солнце, яркие карточки.
    public static let sunset = Theme(
        id: "sunset",
        name: "Закат",
        backgroundStops: [Color(hex: 0x3B2740), Color(hex: 0x2A1C33), Color(hex: 0x171019)],
        glow: Color(hex: 0xFF9E6B),
        accent: Color(hex: 0xFF8A5B),
        textPrimary: Color(hex: 0xFFF3EC),
        textSecondary: Color(hex: 0xFFF3EC).opacity(0.62),
        cardFill: Color(hex: 0x4A3150).opacity(0.55),
        cardStroke: Color.white.opacity(0.08),
        cardRadius: 22,
        vividCards: [
            VividCard(colors: [Color(hex: 0xFFB36B), Color(hex: 0xF0705A)], foreground: Color(hex: 0x2B1520)),
            VividCard(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFFC14D)], foreground: Color(hex: 0x2B2010)),
            VividCard(colors: [Color(hex: 0xD3A8FF), Color(hex: 0xA77BF0)], foreground: Color(hex: 0x23163A)),
            VividCard(colors: [Color(hex: 0xC9F27F), Color(hex: 0x98DB5E)], foreground: Color(hex: 0x1B2A10)),
            VividCard(colors: [Color(hex: 0x8FD3FF), Color(hex: 0x5FAEF0)], foreground: Color(hex: 0x10213A)),
        ]
    )
}

extension EnvironmentValues {
    @Entry public var lumenTheme: Theme = .sunset
}

extension Color {
    /// Цвет из шестнадцатеричного RGB, например `0xFF8A5B`.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
