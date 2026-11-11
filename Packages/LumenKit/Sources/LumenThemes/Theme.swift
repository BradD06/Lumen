import SwiftUI

/// Набор дизайн-токенов. Вид у приложения один: «Кабинет», библиотека с книжными полками
/// за матовым стеклом. У него шесть цветовых схем (`Theme.schemes`), выбор в Настройках.
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
    /// «Изумруд», основная схема: тёмно-зелёная библиотека, латунь, пергамент.
    /// id остался `study`: так тема называлась, когда была одной.
    public static let study = Theme(
        id: "study",
        name: "Изумруд",
        caption: "Тёмно-зелёная библиотека и латунь",
        isDark: true,
        fontDesign: .serif,
        backgroundStops: [Color(hex: 0x1E3D31), Color(hex: 0x12271F), Color(hex: 0x0A1612)],
        glow: Color(hex: 0xE2B868),
        glowStrength: 0.4,
        glow2: Color(hex: 0x46966E),
        wallColors: [Color(hex: 0x6B2A2A), Color(hex: 0x2F5A48), Color(hex: 0x8A6A34), Color(hex: 0x233F5E), Color(hex: 0x5A3A26)],
        accent: Color(hex: 0xD9B66E),
        onAccent: Color(hex: 0x1C2A22),
        textPrimary: Color(hex: 0xF1E7D0),
        textSecondary: Color(hex: 0xF1E7D0).opacity(0.66),
        cardFill: Color(hex: 0x224235).opacity(0.42),
        cardStroke: Color(hex: 0xE9D2A0).opacity(0.17),
        cardRadius: 18,
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

    /// «Полночь»: ночная синева и серебро.
    public static let midnight = Theme(
        id: "midnight",
        name: "Полночь",
        caption: "Ночная синева и серебро, свет луны",
        isDark: true,
        fontDesign: .serif,
        backgroundStops: [Color(hex: 0x1E2A47), Color(hex: 0x121A30), Color(hex: 0x080C18)],
        glow: Color(hex: 0x8CAFEB),
        glowStrength: 0.36,
        glow2: Color(hex: 0x5A50AA),
        wallColors: [Color(hex: 0x2C3E6B), Color(hex: 0x5A4A7A), Color(hex: 0x3C6A80), Color(hex: 0x7A6A4A), Color(hex: 0x263050)],
        accent: Color(hex: 0xB9CCF0),
        onAccent: Color(hex: 0x121A30),
        textPrimary: Color(hex: 0xE9EEF8),
        textSecondary: Color(hex: 0xE9EEF8).opacity(0.66),
        cardFill: Color(hex: 0x28375F).opacity(0.4),
        cardStroke: Color(hex: 0xBED2F5).opacity(0.17),
        cardRadius: 18,
        shadowOpacity: 0.4,
        menuFill: Color(hex: 0x141D36).opacity(0.96),
        vividCards: [
            VividCard(colors: [Color(hex: 0xE9EEF8), Color(hex: 0xD3DCEC)], foreground: Color(hex: 0x1A2238)),
            VividCard(colors: [Color(hex: 0xB9CCF0), Color(hex: 0x8FA8D8)], foreground: Color(hex: 0x121A30)),
            VividCard(colors: [Color(hex: 0x8E6FC9), Color(hex: 0x6A50A8)], foreground: Color(hex: 0xF0EAFB)),
            VividCard(colors: [Color(hex: 0x5F8FB0), Color(hex: 0x3F6F90)], foreground: Color(hex: 0xEAF4FA)),
            VividCard(colors: [Color(hex: 0x2D3B5E), Color(hex: 0x22304E)], foreground: Color(hex: 0xC9D6EA)),
        ]
    )

    /// «Вишня»: бордовый бархат и розовое золото.
    public static let cherry = Theme(
        id: "cherry",
        name: "Вишня",
        caption: "Бордовый бархат и розовое золото",
        isDark: true,
        fontDesign: .serif,
        backgroundStops: [Color(hex: 0x45202A), Color(hex: 0x2A1218), Color(hex: 0x14080B)],
        glow: Color(hex: 0xF0967A),
        glowStrength: 0.4,
        glow2: Color(hex: 0xAA3C5A),
        wallColors: [Color(hex: 0x7A2E3A), Color(hex: 0x3E2A4A), Color(hex: 0x9A6A4A), Color(hex: 0x5A2230), Color(hex: 0x2E3A4A)],
        accent: Color(hex: 0xE9AE90),
        onAccent: Color(hex: 0x2A1218),
        textPrimary: Color(hex: 0xF7E8E2),
        textSecondary: Color(hex: 0xF7E8E2).opacity(0.68),
        cardFill: Color(hex: 0x50222E).opacity(0.42),
        cardStroke: Color(hex: 0xF0BEAA).opacity(0.17),
        cardRadius: 18,
        shadowOpacity: 0.4,
        menuFill: Color(hex: 0x30141C).opacity(0.96),
        vividCards: [
            VividCard(colors: [Color(hex: 0xF7E8E2), Color(hex: 0xECD3C8)], foreground: Color(hex: 0x3A1A20)),
            VividCard(colors: [Color(hex: 0xE9AE90), Color(hex: 0xC98468)], foreground: Color(hex: 0x2A1218)),
            VividCard(colors: [Color(hex: 0xB04A5A), Color(hex: 0x8A3040)], foreground: Color(hex: 0xFBE3E8)),
            VividCard(colors: [Color(hex: 0x7A5238), Color(hex: 0x5A3A26)], foreground: Color(hex: 0xF0DDB8)),
            VividCard(colors: [Color(hex: 0x4A2A3A), Color(hex: 0x3A1E2C)], foreground: Color(hex: 0xF0C8B8)),
        ]
    )

    /// «Орех»: тёплое дерево и янтарная лампа.
    public static let walnut = Theme(
        id: "walnut",
        name: "Орех",
        caption: "Тёплое дерево и янтарная лампа",
        isDark: true,
        fontDesign: .serif,
        backgroundStops: [Color(hex: 0x3E2C1F), Color(hex: 0x251A12), Color(hex: 0x120C08)],
        glow: Color(hex: 0xF5AA50),
        glowStrength: 0.44,
        glow2: Color(hex: 0xB45A28),
        wallColors: [Color(hex: 0x6E3A22), Color(hex: 0x2F4A3A), Color(hex: 0x8A5A2A), Color(hex: 0x3A2E4A), Color(hex: 0xA07A3A)],
        accent: Color(hex: 0xEDB25E),
        onAccent: Color(hex: 0x251A12),
        textPrimary: Color(hex: 0xF5E8D4),
        textSecondary: Color(hex: 0xF5E8D4).opacity(0.68),
        cardFill: Color(hex: 0x4E3826).opacity(0.42),
        cardStroke: Color(hex: 0xF0C88C).opacity(0.18),
        cardRadius: 18,
        shadowOpacity: 0.4,
        menuFill: Color(hex: 0x2E2016).opacity(0.96),
        vividCards: [
            VividCard(colors: [Color(hex: 0xF5E8D4), Color(hex: 0xE6D2B2)], foreground: Color(hex: 0x2E2216)),
            VividCard(colors: [Color(hex: 0xEDB25E), Color(hex: 0xC88C3A)], foreground: Color(hex: 0x251A12)),
            VividCard(colors: [Color(hex: 0x8E3A2A), Color(hex: 0x6E2A1E)], foreground: Color(hex: 0xF6DCD2)),
            VividCard(colors: [Color(hex: 0x3F5A44), Color(hex: 0x2F4A36)], foreground: Color(hex: 0xE8E0C4)),
            VividCard(colors: [Color(hex: 0x5A4030), Color(hex: 0x46301F)], foreground: Color(hex: 0xF0DDB8)),
        ]
    )

    /// «Сумерки»: сливовый вечер и лиловый отсвет.
    public static let dusk = Theme(
        id: "dusk",
        name: "Сумерки",
        caption: "Сливовый вечер и лиловый отсвет",
        isDark: true,
        fontDesign: .serif,
        backgroundStops: [Color(hex: 0x33284A), Color(hex: 0x1F182F), Color(hex: 0x0F0B18)],
        glow: Color(hex: 0xC8A0F0),
        glowStrength: 0.36,
        glow2: Color(hex: 0xF08CAA),
        wallColors: [Color(hex: 0x4A3A7A), Color(hex: 0x7A3A5A), Color(hex: 0x3A5A7A), Color(hex: 0x8A6AA0), Color(hex: 0x2E2A4A)],
        accent: Color(hex: 0xCDB2F2),
        onAccent: Color(hex: 0x1F182F),
        textPrimary: Color(hex: 0xF0E9F9),
        textSecondary: Color(hex: 0xF0E9F9).opacity(0.66),
        cardFill: Color(hex: 0x3E305C).opacity(0.42),
        cardStroke: Color(hex: 0xD7C3F5).opacity(0.17),
        cardRadius: 18,
        shadowOpacity: 0.4,
        menuFill: Color(hex: 0x251C3A).opacity(0.96),
        vividCards: [
            VividCard(colors: [Color(hex: 0xF0E9F9), Color(hex: 0xDCD0EE)], foreground: Color(hex: 0x241A36)),
            VividCard(colors: [Color(hex: 0xCDB2F2), Color(hex: 0xA88AD8)], foreground: Color(hex: 0x1F182F)),
            VividCard(colors: [Color(hex: 0xD9809A), Color(hex: 0xB85E7A)], foreground: Color(hex: 0xFFF0F4)),
            VividCard(colors: [Color(hex: 0x6A8AC0), Color(hex: 0x4E6EA0)], foreground: Color(hex: 0xEEF2FA)),
            VividCard(colors: [Color(hex: 0x4A3A6A), Color(hex: 0x3A2C56)], foreground: Color(hex: 0xE2D4F6)),
        ]
    )

    /// «Лён»: светлая, молочное стекло на льне и бронза.
    public static let linen = Theme(
        id: "linen",
        name: "Лён",
        caption: "Светлая: молочное стекло на льне и бронза",
        isDark: false,
        fontDesign: .serif,
        backgroundStops: [Color(hex: 0xF2ECE2), Color(hex: 0xE7DECF), Color(hex: 0xD9CDBA)],
        glow: Color(hex: 0xFFC882),
        glowStrength: 0.5,
        glow2: Color(hex: 0x96B496),
        wallColors: [Color(hex: 0xB98A6A), Color(hex: 0x7E9A84), Color(hex: 0xC9A86A), Color(hex: 0x8A9AB4), Color(hex: 0xA86A5A)],
        wallOpacity: 0.28,
        accent: Color(hex: 0x8C5A2C),
        onAccent: Color(hex: 0xFFF8EE),
        textPrimary: Color(hex: 0x2A221A),
        textSecondary: Color(hex: 0x2A221A).opacity(0.66),
        cardFill: Color(hex: 0xFFFCF6).opacity(0.5),
        cardStroke: Color(hex: 0x785A32).opacity(0.16),
        cardRadius: 18,
        shadowOpacity: 0.12,
        menuFill: Color(hex: 0xFFFCF6).opacity(0.97),
        vividCards: [
            VividCard(colors: [Color(hex: 0xFFFCF6), Color(hex: 0xF2E8D8)], foreground: Color(hex: 0x2A221A)),
            VividCard(colors: [Color(hex: 0xD9B07A), Color(hex: 0xB88A50)], foreground: Color(hex: 0x2A1A0C)),
            VividCard(colors: [Color(hex: 0xB8645A), Color(hex: 0x9A4A40)], foreground: Color(hex: 0xFFF2EE)),
            VividCard(colors: [Color(hex: 0x7E9A84), Color(hex: 0x5E7A64)], foreground: Color(hex: 0xF4FAF4)),
            VividCard(colors: [Color(hex: 0x8A9AB4), Color(hex: 0x6A7A94)], foreground: Color(hex: 0xF6F8FC)),
        ]
    )

    /// Цветовые схемы в том порядке, в каком они стоят в Настройках. Первая основная.
    public static let schemes: [Theme] = [.study, .midnight, .cherry, .walnut, .dusk, .linen]

    /// Ключ UserDefaults с id выбранной схемы.
    public static let storageKey = "appearance.scheme"

    /// Схема по id; неизвестный id даёт основную, «Изумруд».
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
