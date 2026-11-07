import SwiftUI

/// Набор дизайн-токенов. Позже темы будут описываться JSON и распространяться через магазин,
/// пока есть встроенные: «Закат», «Бумага», «Монохром», «Кабинет», «Дзен» (выбор в Настройках).
public struct Theme: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Одна строка под названием в Настройках.
    public var caption: String
    /// Тёмная тема или светлая: от этого зависят системные цвета, меню и поля.
    public var isDark: Bool
    /// Начертание шрифта по всему приложению: обычный, с засечками, моноширинный.
    public var fontDesign: Font.Design
    /// Как устроено окно: где навигация и как до всего дотянуться.
    public var layout: Layout

    public enum Layout: String, Sendable, Equatable {
        /// Боковая панель с разделами, вкладки, кнопки в панели инструментов.
        case standard
        /// Без боковой панели: внизу всегда командная строка ⌘K, всё делается командами.
        case commandLine
        /// Без боковой панели: сверху строка разделов, как в газете («Бумага»).
        case sectionBar

        /// Боковая панель спрятана, навигация в своей строке.
        public var hidesSidebar: Bool { self != .standard }
    }
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
        caption: String = "",
        isDark: Bool = true,
        fontDesign: Font.Design = .default,
        layout: Layout = .standard,
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
        self.caption = caption
        self.isDark = isDark
        self.fontDesign = fontDesign
        self.layout = layout
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
    /// Тёмная тема с тёплыми закатными градиентами: сливовый фон, персиковое солнце, яркие карточки.
    public static let sunset = Theme(
        id: "sunset",
        name: "Закат",
        caption: "Тёмная, закатный градиент и стеклянные карточки",
        backgroundStops: [Color(hex: 0x3B2740), Color(hex: 0x2A1C33), Color(hex: 0x171019)],
        glow: Color(hex: 0xFF9E6B),
        accent: Color(hex: 0xFF8A5B),
        textPrimary: Color(hex: 0xFFF3EC),
        textSecondary: Color(hex: 0xFFF3EC).opacity(0.62),
        cardFill: Color(hex: 0x4A3150).opacity(0.55),
        cardStroke: Color.white.opacity(0.08),
        cardRadius: 22,
        menuFill: Color(hex: 0x2F2136).opacity(0.86),
        vividCards: [
            VividCard(colors: [Color(hex: 0xFFB36B), Color(hex: 0xF0705A)], foreground: Color(hex: 0x2B1520)),
            VividCard(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFFC14D)], foreground: Color(hex: 0x2B2010)),
            VividCard(colors: [Color(hex: 0xD3A8FF), Color(hex: 0xA77BF0)], foreground: Color(hex: 0x23163A)),
            VividCard(colors: [Color(hex: 0xC9F27F), Color(hex: 0x98DB5E)], foreground: Color(hex: 0x1B2A10)),
            VividCard(colors: [Color(hex: 0x8FD3FF), Color(hex: 0x5FAEF0)], foreground: Color(hex: 0x10213A)),
        ]
    )
}

extension Theme {
    /// Светлая, как хорошая книга: бумага, шрифт с засечками, красные чернила.
    public static let paper = Theme(
        id: "paper",
        name: "Бумага",
        caption: "Светлая газета: разделы строкой сверху, засечки, красные чернила",
        isDark: false,
        fontDesign: .serif,
        layout: .sectionBar,
        backgroundStops: [Color(hex: 0xF6F1E7), Color(hex: 0xF3ECDF), Color(hex: 0xEFE7D8)],
        glow: Color(hex: 0xE8C9A8),
        glowStrength: 0.25,
        accent: Color(hex: 0xB5402A),
        textPrimary: Color(hex: 0x22201C),
        textSecondary: Color(hex: 0x22201C).opacity(0.64),
        cardFill: Color(hex: 0xFFFDF8).opacity(0.85),
        cardStroke: Color(hex: 0x22201C).opacity(0.12),
        cardRadius: 6,
        shadowOpacity: 0.08,
        menuFill: Color(hex: 0xFFFDF8).opacity(0.96),
        vividCards: [
            VividCard(colors: [Color(hex: 0xF1D3C8), Color(hex: 0xE3B3A3)], foreground: Color(hex: 0x3A1A12)),
            VividCard(colors: [Color(hex: 0xEDE3B5), Color(hex: 0xDDCD8A)], foreground: Color(hex: 0x2E2808)),
            VividCard(colors: [Color(hex: 0xD5DEE8), Color(hex: 0xB9C7D8)], foreground: Color(hex: 0x1B2A3A)),
            VividCard(colors: [Color(hex: 0xDCE5CF), Color(hex: 0xC3D2AE)], foreground: Color(hex: 0x1F2A12)),
            VividCard(colors: [Color(hex: 0xE9D9BF), Color(hex: 0xDCC6A2)], foreground: Color(hex: 0x2B2116)),
        ]
    )

    /// Почти чёрная, плотная, моноширинный шрифт и один тёплый акцент.
    public static let mono = Theme(
        id: "mono",
        name: "Монохром",
        caption: "Всё с клавиатуры: без боковой панели, внизу строка ⌘K",
        isDark: true,
        fontDesign: .monospaced,
        layout: .commandLine,
        backgroundStops: [Color(hex: 0x141416), Color(hex: 0x0F0F10), Color(hex: 0x0B0B0C)],
        glow: Color(hex: 0xFFB86B),
        glowStrength: 0.08,
        accent: Color(hex: 0xFFB86B),
        textPrimary: Color(hex: 0xEDEDED),
        textSecondary: Color(hex: 0xEDEDED).opacity(0.6),
        cardFill: Color(hex: 0x1A1A1C).opacity(0.92),
        cardStroke: Color.white.opacity(0.09),
        cardRadius: 10,
        shadowOpacity: 0.4,
        menuFill: Color(hex: 0x161618).opacity(0.97),
        vividCards: [
            VividCard(colors: [Color(hex: 0xFFB86B), Color(hex: 0xF29A45)], foreground: Color(hex: 0x1A1206)),
            VividCard(colors: [Color(hex: 0x2A2A2D), Color(hex: 0x1F1F22)], foreground: Color(hex: 0xFFB86B)),
            VividCard(colors: [Color(hex: 0xEDEDED), Color(hex: 0xCFCFD4)], foreground: Color(hex: 0x111111)),
            VividCard(colors: [Color(hex: 0x3A3A3E), Color(hex: 0x2A2A2D)], foreground: Color(hex: 0xEDEDED)),
            VividCard(colors: [Color(hex: 0x2A231B), Color(hex: 0x1E1913)], foreground: Color(hex: 0xFFD3A0)),
        ]
    )

    /// Домашняя библиотека: тёмно-зелёный, латунь, пергамент.
    public static let study = Theme(
        id: "study",
        name: "Кабинет",
        caption: "Тёмно-зелёная библиотека, латунь и пергамент",
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

    /// Тихая: тёплый камень, шалфей, лёгкий шрифт с засечками, почти без рамок.
    public static let zen = Theme(
        id: "zen",
        name: "Дзен",
        caption: "Светлая и тихая: камень, шалфей, много воздуха",
        isDark: false,
        fontDesign: .serif,
        backgroundStops: [Color(hex: 0xF4F2ED), Color(hex: 0xF2F0EB), Color(hex: 0xEEEBE4)],
        glow: Color(hex: 0xB9C8B4),
        glowStrength: 0.22,
        accent: Color(hex: 0x5E6D5A),
        textPrimary: Color(hex: 0x2E2D2A),
        textSecondary: Color(hex: 0x2E2D2A).opacity(0.6),
        cardFill: Color(hex: 0xFBFAF7).opacity(0.8),
        cardStroke: Color(hex: 0x2E2D2A).opacity(0.06),
        cardRadius: 18,
        shadowOpacity: 0.06,
        menuFill: Color(hex: 0xFBFAF7).opacity(0.97),
        vividCards: [
            VividCard(colors: [Color(hex: 0xE6EBE3), Color(hex: 0xD5DED0)], foreground: Color(hex: 0x2E3A2B)),
            VividCard(colors: [Color(hex: 0xEFE6DA), Color(hex: 0xE2D5C2)], foreground: Color(hex: 0x3A2E1E)),
            VividCard(colors: [Color(hex: 0xE4E6EC), Color(hex: 0xD3D7E0)], foreground: Color(hex: 0x262B36)),
            VividCard(colors: [Color(hex: 0xF0E3E0), Color(hex: 0xE3CFCA)], foreground: Color(hex: 0x3A2421)),
            VividCard(colors: [Color(hex: 0xECEADF), Color(hex: 0xDDD9C8)], foreground: Color(hex: 0x2E2D2A)),
        ]
    )

    /// Темы в том порядке, в каком они стоят в Настройках.
    public static let all: [Theme] = [.sunset, .paper, .mono, .study, .zen]

    /// Ключ UserDefaults с id выбранной темы.
    public static let storageKey = "appearance.theme"

    /// Тема по id; неизвестный id (например, тема из старой версии) даёт «Закат».
    public static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .sunset
    }
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
