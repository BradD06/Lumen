import SwiftUI

extension Theme {
    /// Схема, окрашенная в цвет обложки открытой заметки: фон окна, свет в углу и акцент
    /// берутся из обложки, стекло, тени и текст остаются от схемы. На тёмной схеме фон
    /// становится глубоким оттенком обложки, на светлой бледным.
    public func tinted(by cover: Color) -> Theme {
        var theme = self
        if isDark {
            theme.backgroundStops = [
                cover.mix(with: .black, by: 0.62),
                cover.mix(with: .black, by: 0.76),
                cover.mix(with: .black, by: 0.85),
            ]
            theme.accent = cover.mix(with: .white, by: 0.55)
            theme.onAccent = cover.mix(with: .black, by: 0.82)
            theme.menuFill = cover.mix(with: .black, by: 0.78).opacity(0.97)
        } else {
            theme.backgroundStops = [
                cover.mix(with: .white, by: 0.82),
                cover.mix(with: .white, by: 0.88),
                cover.mix(with: .white, by: 0.92),
            ]
            theme.accent = cover.mix(with: .black, by: 0.45)
            theme.onAccent = .white
            theme.menuFill = cover.mix(with: .white, by: 0.94).opacity(0.98)
        }
        theme.glow = cover.mix(with: .white, by: 0.35)
        theme.glow2 = cover
        return theme
    }
}
