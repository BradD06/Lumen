import SwiftUI

/// Набор дизайн-токенов. Вид у приложения один: «Остров», ровный фон, листы и стеклянный
/// остров с разделами внизу. Две темы, светлая и тёмная (`Theme.schemes`), см. `AppearanceMode`.
public struct Theme: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Одна строка под названием темы в Настройках.
    public var caption: String
    /// Тёмная тема или светлая: от этого зависят системные цвета, меню и поля.
    public var isDark: Bool
    /// Начертание шрифта по всему приложению.
    public var fontDesign: Font.Design
    /// Фон окна сверху вниз. У «Острова» он ровный: обе точки одного цвета.
    public var backgroundStops: [Color]
    /// Мягкий цвет для подложек без картинки (заметка без обложки, «Читаю сейчас»).
    public var glow: Color
    /// Насколько ярко подложка светит в углу фона окна (0 = фон ровный).
    public var glowStrength: Double
    /// Второй мягкий цвет подложек.
    public var glow2: Color
    /// Акцент: «+», выбранное, ссылки, отметки.
    public var accent: Color
    /// Текст и значки на заливке акцентом.
    public var onAccent: Color
    public var textPrimary: Color
    public var textSecondary: Color
    /// Третий, самый тихий текст: даты, подсказки, путь сверху.
    public var textTertiary: Color
    /// Лёгкая подложка кнопок и плашек поверх фона или листа.
    public var cardFill: Color
    /// Тонкая обводка стекла и карточек.
    public var cardStroke: Color
    public var cardRadius: CGFloat
    /// Плотность тени под карточками.
    public var shadowOpacity: Double
    /// Непрозрачный фон всплывающих меню.
    public var menuFill: Color
    /// Лист: заметка, карточка-виджет, панель книги.
    public var sheet: Color
    /// Подложка выбранного на стекле и плашек на листе: раздел в острове, переключатели.
    public var surface2: Color
    /// Тонкие линии: разделители, дорожки прогресса.
    public var line: Color
    /// Бледный акцент: фон выбранной кнопки панели оформления, выделенный текст.
    public var accentSoft: Color
    /// Тёмная (в тёмной теме светлая) заливка главной кнопки плеера.
    public var ink: Color
    public var onInk: Color
    /// Цвет стекла поверх размытия: остров, панели у выделения.
    public var glassFill: Color
    /// Выделение маркером в тексте.
    public var highlight: Color
    /// «Сохранено», готово, без ошибок.
    public var success: Color
    /// Яркие карточки: папки, цветные плашки.
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
        glowStrength: Double = 0,
        glow2: Color? = nil,
        accent: Color,
        onAccent: Color? = nil,
        textPrimary: Color,
        textSecondary: Color,
        cardFill: Color,
        cardStroke: Color,
        cardRadius: CGFloat,
        shadowOpacity: Double = 0.25,
        menuFill: Color? = nil,
        vividCards: [VividCard],
        sheet: Color,
        surface2: Color,
        line: Color,
        textTertiary: Color,
        accentSoft: Color,
        ink: Color,
        onInk: Color,
        glassFill: Color,
        highlight: Color,
        success: Color
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
        self.accent = accent
        self.onAccent = onAccent ?? (isDark ? backgroundStops.last ?? .black : .white)
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.cardFill = cardFill
        self.cardStroke = cardStroke
        self.cardRadius = cardRadius
        self.shadowOpacity = shadowOpacity
        self.menuFill = menuFill ?? sheet
        self.vividCards = vividCards
        self.sheet = sheet
        self.surface2 = surface2
        self.line = line
        self.textTertiary = textTertiary
        self.accentSoft = accentSoft
        self.ink = ink
        self.onInk = onInk
        self.glassFill = glassFill
        self.highlight = highlight
        self.success = success
    }

    /// Цвет тонких бликов и подложек: белый на тёмной теме, чёрный на светлой.
    public var contrast: Color { isDark ? .white : .black }

    public var colorScheme: ColorScheme { isDark ? .dark : .light }

    /// Светлая кромка блика: на корешках и планке полки.
    public var glassHighlight: Color { isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.9) }

    /// Фон окна одним цветом.
    public var background: Color { backgroundStops.first ?? (isDark ? .black : .white) }

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: backgroundStops, startPoint: .top, endPoint: .bottom)
    }

    public func vividCard(_ index: Int) -> VividCard {
        vividCards[((index % vividCards.count) + vividCards.count) % vividCards.count]
    }
}

extension Theme {
    /// «Остров», светлая тема: ровный светлый фон, белые листы, один сиреневый акцент.
    public static let light = Theme(
        id: "light", name: "Светлая", caption: "Ровный светлый фон и белые листы",
        isDark: false, fontDesign: .default,
        backgroundStops: [Color(hex: 0xF4F4F2), Color(hex: 0xF4F4F2)],
        glow: Color(hex: 0xC9C8FF), glowStrength: 0, glow2: Color(hex: 0xE6E6FF),
        accent: Color(hex: 0x5B5BF0), onAccent: .white,
        textPrimary: Color(hex: 0x17171A), textSecondary: Color(hex: 0x6E6E78),
        cardFill: Color.black.opacity(0.045), cardStroke: Color.black.opacity(0.07),
        cardRadius: 14, shadowOpacity: 0.10, menuFill: Color.white.opacity(0.98),
        vividCards: [
            VividCard(colors: [Color(hex: 0xC9C8FF), Color(hex: 0xB9B8FA)], foreground: Color(hex: 0x22225A)),
            VividCard(colors: [Color(hex: 0xF7CF7A), Color(hex: 0xEFC164)], foreground: Color(hex: 0x3D2E0A)),
            VividCard(colors: [Color(hex: 0xA9DFC1), Color(hex: 0x93D3B0)], foreground: Color(hex: 0x173B28)),
        ],
        sheet: .white, surface2: Color(hex: 0xF2F2F0), line: Color(hex: 0xECECEF),
        textTertiary: Color(hex: 0xA6A6AF), accentSoft: Color(hex: 0xEEEEFF),
        ink: Color(hex: 0x17171A), onInk: .white,
        glassFill: Color.white.opacity(0.74), highlight: Color(hex: 0xFFEBA6), success: Color(hex: 0x2E9E6A)
    )

    /// «Остров», тёмная тема: почти чёрный фон, графитовые листы, светлый сиреневый акцент.
    public static let dark = Theme(
        id: "dark", name: "Тёмная", caption: "Почти чёрный фон и графитовые листы",
        isDark: true, fontDesign: .default,
        backgroundStops: [Color(hex: 0x0E0E10), Color(hex: 0x0E0E10)],
        glow: Color(hex: 0x8482FF), glowStrength: 0, glow2: Color(hex: 0x24233F),
        accent: Color(hex: 0x8482FF), onAccent: .white,
        textPrimary: Color(hex: 0xF2F2F5), textSecondary: Color(hex: 0x9B9BA5),
        cardFill: Color.white.opacity(0.06), cardStroke: Color.white.opacity(0.08),
        cardRadius: 14, shadowOpacity: 0.45, menuFill: Color(hex: 0x1C1C20).opacity(0.98),
        vividCards: [
            VividCard(colors: [Color(hex: 0x3B3A78), Color(hex: 0x2F2E66)], foreground: Color(hex: 0xE6E6FF)),
            VividCard(colors: [Color(hex: 0x6B5420), Color(hex: 0x57441A)], foreground: Color(hex: 0xFFE9B0)),
            VividCard(colors: [Color(hex: 0x22553F), Color(hex: 0x1B4332)], foreground: Color(hex: 0xCFEBDB)),
        ],
        sheet: Color(hex: 0x18181B), surface2: Color(hex: 0x222226), line: Color(hex: 0x26262B),
        textTertiary: Color(hex: 0x5E5E67), accentSoft: Color(hex: 0x24233F),
        ink: Color(hex: 0xF2F2F5), onInk: Color(hex: 0x0E0E10),
        glassFill: Color(red: 38 / 255, green: 38 / 255, blue: 43 / 255).opacity(0.72),
        highlight: Color(hex: 0xFFCE50).opacity(0.26), success: Color(hex: 0x3CC983)
    )

    /// Две темы «Острова»: светлая и тёмная. Какую показывать, решает `AppearanceMode`.
    public static let schemes: [Theme] = [.light, .dark]
}

/// Настройки → «Оформление»: как в системе, всегда светлая или всегда тёмная.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public static let storageKey = "appearance.mode"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Как в системе"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    /// Какую схему окна просить у системы. `nil`: как в системе.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Тема при этой настройке, когда система сейчас светлая или тёмная.
    public func theme(system: ColorScheme) -> Theme {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: system == .dark ? .dark : .light
        }
    }
}

extension EnvironmentValues {
    @Entry public var lumenTheme: Theme = .light
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
