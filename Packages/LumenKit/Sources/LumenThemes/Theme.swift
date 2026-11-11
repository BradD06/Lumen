import SwiftUI

/// Набор дизайн-токенов. Тема у приложения одна: «Кабинет», тёмно-зелёная библиотека
/// с книжными полками и латунью. Позже темы смогут приходить из магазина.
public struct Theme: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Тёмная тема или светлая: от этого зависят системные цвета, меню и поля.
    public var isDark: Bool
    /// Начертание шрифта по всему приложению.
    public var fontDesign: Font.Design
    /// Фон сверху вниз.
    public var backgroundStops: [Color]
    /// Тёплое свечение «солнца» в углу фона.
    public var glow: Color
    /// Насколько ярко светит «солнце» в углу фона (0 = без свечения).
    public var glowStrength: Double
    public var accent: Color
    public var textPrimary: Color
    public var textSecondary: Color
    /// Заливка и обводка стеклянных карточек.
    public var cardFill: Color
    public var cardStroke: Color
    public var cardRadius: CGFloat
    /// Плотность тени под карточками.
    public var shadowOpacity: Double
    /// Непрозрачный фон всплывающих меню.
    public var menuFill: Color
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
        isDark: Bool = true,
        fontDesign: Font.Design = .default,
        backgroundStops: [Color],
        glow: Color,
        glowStrength: Double = 0.45,
        accent: Color,
        textPrimary: Color,
        textSecondary: Color,
        cardFill: Color,
        cardStroke: Color,
        cardRadius: CGFloat,
        shadowOpacity: Double = 0.25,
        menuFill: Color? = nil,
        vividCards: [VividCard]
    ) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.fontDesign = fontDesign
        self.backgroundStops = backgroundStops
        self.glow = glow
        self.glowStrength = glowStrength
        self.accent = accent
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.cardFill = cardFill
        self.cardStroke = cardStroke
        self.cardRadius = cardRadius
        self.shadowOpacity = shadowOpacity
        self.menuFill = menuFill ?? cardFill
        self.vividCards = vividCards
    }

    /// Цвет тонких бликов и подложек: белый на тёмной теме, чёрный на светлой.
    public var contrast: Color { isDark ? .white : .black }

    public var colorScheme: ColorScheme { isDark ? .dark : .light }

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: backgroundStops, startPoint: .top, endPoint: .bottom)
    }

    public func vividCard(_ index: Int) -> VividCard {
        vividCards[((index % vividCards.count) + vividCards.count) % vividCards.count]
    }
}

extension Theme {
    /// «Кабинет»: домашняя библиотека. Тёмно-зелёный, латунь, пергамент.
    public static let study = Theme(
        id: "study",
        name: "Кабинет",
        isDark: true,
        fontDesign: .serif,
        backgroundStops: [Color(hex: 0x1A3329), Color(hex: 0x12251E), Color(hex: 0x0C1A15)],
        glow: Color(hex: 0xC9A45C),
        glowStrength: 0.28,
        accent: Color(hex: 0xD9B66E),
        textPrimary: Color(hex: 0xEFE4CC),
        textSecondary: Color(hex: 0xEFE4CC).opacity(0.64),
        cardFill: Color(hex: 0x1F3A30).opacity(0.72),
        cardStroke: Color(hex: 0xC9A45C).opacity(0.2),
        cardRadius: 8,
        shadowOpacity: 0.35,
        menuFill: Color(hex: 0x173026).opacity(0.96),
        vividCards: [
            VividCard(colors: [Color(hex: 0xEFE4CC), Color(hex: 0xE2D2AE)], foreground: Color(hex: 0x2C2318)),
            VividCard(colors: [Color(hex: 0xE0C07E), Color(hex: 0xB08A42)], foreground: Color(hex: 0x1C2A22)),
            VividCard(colors: [Color(hex: 0x8E3A3A), Color(hex: 0x6E2626)], foreground: Color(hex: 0xF3DADA)),
            VividCard(colors: [Color(hex: 0x7A5238), Color(hex: 0x5A3A26)], foreground: Color(hex: 0xF0DDB8)),
            VividCard(colors: [Color(hex: 0x2F4F43), Color(hex: 0x22392F)], foreground: Color(hex: 0xE3CF9E)),
        ]
    )
}

extension EnvironmentValues {
    @Entry public var lumenTheme: Theme = .study
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
