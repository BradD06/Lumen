import SwiftUI

extension Theme {
    /// Тема, окрашенная в цвет обложки открытой заметки: ровный фон окна и акцент берутся
    /// из обложки, листы, стекло и текст остаются от темы. В тёмной теме фон становится
    /// глубоким оттенком обложки, в светлой бледным.
    public func tinted(by cover: Color) -> Theme {
        var theme = self
        if isDark {
            let background = cover.mix(with: .black, by: 0.86)
            theme.backgroundStops = [background, background]
            theme.accent = cover.mix(with: .white, by: 0.45)
            theme.accentSoft = cover.mix(with: .black, by: 0.72)
            theme.onAccent = cover.mix(with: .black, by: 0.85)
        } else {
            let background = cover.mix(with: .white, by: 0.9)
            theme.backgroundStops = [background, background]
            theme.accent = cover.mix(with: .black, by: 0.4)
            theme.accentSoft = cover.mix(with: .white, by: 0.85)
            theme.onAccent = .white
        }
        theme.glow = cover.mix(with: .white, by: 0.35)
        theme.glow2 = cover
        return theme
    }
}
