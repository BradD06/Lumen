import SwiftUI

/// Набор дизайн-токенов. Вид у приложения один: «Кабинет», библиотека с книжными полками
/// за матовым стеклом. У него пять цветовых схем (`Theme.schemes`), выбор в Настройках.
public struct Theme: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Одна строка под названием схемы в Настройках.
    public var caption: String
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
    /// Второй, холодный свет в противоположном углу.
    public var glow2: Color
    /// Корешки книжного шкафа, который размыто виден за стеклом.
    public var wallColors: [Color]
    /// Насколько заметен шкаф за стеклом (0 = не виден).
    public var wallOpacity: Double
    public var accent: Color
    /// Текст на латунной заливке акцентом: на открытой комнате, на главной кнопке.
    public var onAccent: Color
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
        caption: String = "",
        isDark: Bool = true,
        fontDesign: Font.Design = .default,
        backgroundStops: [Color],
        glow: Color,
        glowStrength: Double = 0.45,
        glow2: Color? = nil,
        wallColors: [Color] = [],
        wallOpacity: Double = 0.3,
        accent: Color,
        onAccent: Color? = nil,
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
        self.caption = caption
        self.isDark = isDark
        self.fontDesign = fontDesign
        self.backgroundStops = backgroundStops
        self.glow = glow
        self.glowStrength = glowStrength
        self.glow2 = glow2 ?? accent
        self.wallColors = wallColors
        self.wallOpacity = wallOpacity
        self.accent = accent
        self.onAccent = onAccent ?? (isDark ? backgroundStops.last ?? .black : .white)
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

    /// Светлая кромка сверху у стекла: как блик лампы на краю.
    public var glassHighlight: Color { isDark ? Color.white.opacity(0.2) : Color.white.opacity(0.85) }

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: backgroundStops, startPoint: .top, endPoint: .bottom)
    }

    public func vividCard(_ index: Int) -> VividCard {
        vividCards[((index % vividCards.count) + vividCards.count) % vividCards.count]
    }
}

extension Theme {
    /// Пять минималистичных стеклянных палитр для одного оформления «Кабинет».
    public static let study = Theme(
        id: "study", name: "Изумрудное стекло", caption: "Хвойный сумрак и мягкая латунь",
        isDark: true, fontDesign: .default,
        backgroundStops: [Color(hex: 0x263B32), Color(hex: 0x17231D), Color(hex: 0x101713)],
        glow: Color(hex: 0xD8C08B), glowStrength: 0.28, glow2: Color(hex: 0x63927A),
        wallColors: [Color(hex: 0x6B806F), Color(hex: 0x856D4A), Color(hex: 0x466557), Color(hex: 0x77614F)],
        wallOpacity: 0.13, accent: Color(hex: 0xD6C18E), onAccent: Color(hex: 0x20281F),
        textPrimary: Color(hex: 0xF0F0E9), textSecondary: Color(hex: 0xD4D8D0).opacity(0.68),
        cardFill: Color(hex: 0xDDE9DF).opacity(0.075), cardStroke: Color.white.opacity(0.20),
        cardRadius: 20, shadowOpacity: 0.24, menuFill: Color(hex: 0x1A2821).opacity(0.97),
        vividCards: [
            VividCard(colors: [Color(hex: 0xE5E8DB), Color(hex: 0xC9D3C4)], foreground: Color(hex: 0x293229)),
            VividCard(colors: [Color(hex: 0xD6C18E), Color(hex: 0xB39B69)], foreground: Color(hex: 0x24271F)),
            VividCard(colors: [Color(hex: 0x526F60), Color(hex: 0x3B5749)], foreground: Color(hex: 0xF0F0E9)),
        ]
    )

    public static let linen = Theme(
        id: "linen", name: "Молочный лёд", caption: "Светлое стекло и тёплый графит",
        isDark: false, fontDesign: .default,
        backgroundStops: [Color(hex: 0xF3F1EC), Color(hex: 0xE6E5E0), Color(hex: 0xD9DCD8)],
        glow: Color(hex: 0xFFF8E8), glowStrength: 0.68, glow2: Color(hex: 0xBBCBC3),
        wallColors: [Color(hex: 0xAEBBB4), Color(hex: 0xC5BBA8), Color(hex: 0x9BAEAA)],
        wallOpacity: 0.10, accent: Color(hex: 0x76664F), onAccent: .white,
        textPrimary: Color(hex: 0x272A28), textSecondary: Color(hex: 0x555B58).opacity(0.76),
        cardFill: Color.white.opacity(0.36), cardStroke: Color.white.opacity(0.76),
        cardRadius: 20, shadowOpacity: 0.10, menuFill: Color(hex: 0xF8F7F2).opacity(0.98),
        vividCards: [
            VividCard(colors: [Color(hex: 0xFCFBF7), Color(hex: 0xE9E8E1)], foreground: Color(hex: 0x292B29)),
            VividCard(colors: [Color(hex: 0xD5D4CA), Color(hex: 0xBCBCAF)], foreground: Color(hex: 0x292B29)),
            VividCard(colors: [Color(hex: 0x9BAEAA), Color(hex: 0x809691)], foreground: Color(hex: 0x17201D)),
        ]
    )

    public static let midnight = Theme(
        id: "midnight", name: "Северный туман", caption: "Чернильная синева и ледяной блик",
        isDark: true, fontDesign: .default,
        backgroundStops: [Color(hex: 0x293B49), Color(hex: 0x17232D), Color(hex: 0x10171E)],
        glow: Color(hex: 0x9CC9D8), glowStrength: 0.30, glow2: Color(hex: 0x7889B8),
        wallColors: [Color(hex: 0x587487), Color(hex: 0x68728E), Color(hex: 0x486D78)],
        wallOpacity: 0.12, accent: Color(hex: 0xA9CED8), onAccent: Color(hex: 0x17232D),
        textPrimary: Color(hex: 0xEDF3F4), textSecondary: Color(hex: 0xC6D2D5).opacity(0.70),
        cardFill: Color(hex: 0xD9EDF3).opacity(0.075), cardStroke: Color(hex: 0xD7ECF2).opacity(0.22),
        cardRadius: 20, shadowOpacity: 0.28, menuFill: Color(hex: 0x1A2832).opacity(0.97),
        vividCards: [
            VividCard(colors: [Color(hex: 0xE5EFF0), Color(hex: 0xC5D9DE)], foreground: Color(hex: 0x202C32)),
            VividCard(colors: [Color(hex: 0x9FC7D2), Color(hex: 0x78A5B3)], foreground: Color(hex: 0x15242B)),
            VividCard(colors: [Color(hex: 0x526C7B), Color(hex: 0x3B5666)], foreground: Color(hex: 0xF0F4F4)),
        ]
    )

    public static let cherry = Theme(
        id: "cherry", name: "Розовый дым", caption: "Брусничный сумрак и пудровый свет",
        isDark: true, fontDesign: .default,
        backgroundStops: [Color(hex: 0x49343B), Color(hex: 0x2A2026), Color(hex: 0x191519)],
        glow: Color(hex: 0xE6A9A2), glowStrength: 0.30, glow2: Color(hex: 0xA76D7B),
        wallColors: [Color(hex: 0x805C65), Color(hex: 0x916C72), Color(hex: 0x675364)],
        wallOpacity: 0.12, accent: Color(hex: 0xE9BDB2), onAccent: Color(hex: 0x38272C),
        textPrimary: Color(hex: 0xF5EFED), textSecondary: Color(hex: 0xD8C9C8).opacity(0.70),
        cardFill: Color(hex: 0xF2D6D5).opacity(0.075), cardStroke: Color(hex: 0xF5DAD7).opacity(0.20),
        cardRadius: 20, shadowOpacity: 0.27, menuFill: Color(hex: 0x302329).opacity(0.97),
        vividCards: [
            VividCard(colors: [Color(hex: 0xF2E6E1), Color(hex: 0xE0CBC8)], foreground: Color(hex: 0x38292B)),
            VividCard(colors: [Color(hex: 0xDDA8A2), Color(hex: 0xBF8585)], foreground: Color(hex: 0x352326)),
            VividCard(colors: [Color(hex: 0x79535E), Color(hex: 0x60414C)], foreground: Color(hex: 0xF6ECEB)),
        ]
    )

    public static let dusk = Theme(
        id: "dusk", name: "Лавандовый вечер", caption: "Сливовый сумрак и мягкая лаванда",
        isDark: true, fontDesign: .default,
        backgroundStops: [Color(hex: 0x3D394D), Color(hex: 0x25232F), Color(hex: 0x17161E)],
        glow: Color(hex: 0xC6B2E4), glowStrength: 0.30, glow2: Color(hex: 0x8595BD),
        wallColors: [Color(hex: 0x76698D), Color(hex: 0x6D708E), Color(hex: 0x8B7187)],
        wallOpacity: 0.11, accent: Color(hex: 0xD0C0E7), onAccent: Color(hex: 0x282331),
        textPrimary: Color(hex: 0xF1EEF5), textSecondary: Color(hex: 0xD0C9D9).opacity(0.70),
        cardFill: Color(hex: 0xE4D8F1).opacity(0.075), cardStroke: Color(hex: 0xE7DAF2).opacity(0.20),
        cardRadius: 20, shadowOpacity: 0.28, menuFill: Color(hex: 0x292632).opacity(0.97),
        vividCards: [
            VividCard(colors: [Color(hex: 0xECE7F0), Color(hex: 0xD5CDE1)], foreground: Color(hex: 0x302B36)),
            VividCard(colors: [Color(hex: 0xC5B2DE), Color(hex: 0xA28CC2)], foreground: Color(hex: 0x282331)),
            VividCard(colors: [Color(hex: 0x666785), Color(hex: 0x4D506E)], foreground: Color(hex: 0xF0EFF5)),
        ]
    )

    /// Старые сохранённые схемы переводим на новую палитру по ближайшему настроению.
    public static let walnut = study

    /// Цветовые схемы в том порядке, в каком они стоят в Настройках. Первая основная.
    public static let schemes: [Theme] = [.study, .linen, .midnight, .cherry, .dusk]

    public static let storageKey = "appearance.scheme"

    /// Неизвестный или снятый с выбора идентификатор даёт основную схему.
    public static func named(_ id: String) -> Theme {
        schemes.first { $0.id == id } ?? .study
    }
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
