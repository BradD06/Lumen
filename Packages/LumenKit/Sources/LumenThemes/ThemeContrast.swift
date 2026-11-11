import SwiftUI

/// Контраст цветов по WCAG: тёмная папка на тёмном фоне иначе пропадает.
public enum ThemeContrast {
    /// Не меньше этого отношения цвет предмета отличается от фона темы.
    public static let minimumRatio = 1.8

    /// Относительная яркость цвета, 0…1.
    public static func luminance(_ color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        func linear(_ channel: Float) -> Double {
            let value = Double(min(max(channel, 0), 1))
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(resolved.red) + 0.7152 * linear(resolved.green) + 0.0722 * linear(resolved.blue)
    }

    /// Отношение контраста двух цветов, 1…21.
    public static func ratio(_ first: Color, _ second: Color) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Цвет, который виден на фоне: если он слишком близок к фону, его понемногу
    /// смешивают с контрастным цветом темы (светлым в тёмной теме, тёмным в светлой).
    public static func legible(_ color: Color, on background: Color, toward contrast: Color, minimum: Double = minimumRatio) -> Color {
        guard ratio(color, background) < minimum else { return color }
        for step in 1...8 {
            let mixed = color.mix(with: contrast, by: Double(step) * 0.1)
            if ratio(mixed, background) >= minimum { return mixed }
        }
        return color.mix(with: contrast, by: 0.8)
    }
}

extension Theme {
    /// Цвета папки: как у яркой карточки, но всегда заметные на фоне темы.
    public func folderCard(_ index: Int) -> VividCard {
        let card = vividCard(index)
        return VividCard(colors: card.colors.map(legibleOnBackground), foreground: card.foreground)
    }

    /// Цвет предмета, заметный на фоне темы. На светлом фоне хватает меньшего контраста:
    /// там предметы отделяет тень.
    public func legibleOnBackground(_ color: Color) -> Color {
        guard let background = backgroundStops.first else { return color }
        let minimum = ThemeContrast.luminance(background) > 0.5 ? 1.3 : ThemeContrast.minimumRatio
        return ThemeContrast.legible(color, on: background, toward: textPrimary, minimum: minimum)
    }
}
