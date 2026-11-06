import LumenThemes
import SwiftUI
import Testing

struct ThemeTests {
    @Test func settingsOfferFiveThemesInOrder() {
        #expect(Theme.all.map(\.name) == ["Закат", "Бумага", "Монохром", "Кабинет", "Дзен"])
        #expect(Set(Theme.all.map(\.id)).count == Theme.all.count, "id тем не повторяются")
    }

    @Test func unknownIdFallsBackToSunset() {
        #expect(Theme.named("paper") == .paper)
        #expect(Theme.named("нет такой") == .sunset)
        #expect(Theme.named("") == .sunset)
    }

    @Test(arguments: Theme.all)
    func everyThemeIsComplete(_ theme: Theme) {
        #expect(!theme.caption.isEmpty)
        #expect(theme.backgroundStops.count >= 2)
        #expect(theme.vividCards.count >= 5, "цвета папок берутся по номеру из яркой палитры")
        #expect((0...1).contains(theme.glowStrength))
        #expect(theme.colorScheme == (theme.isDark ? .dark : .light))
    }

    @Test func lightThemesAreLight() {
        #expect(Theme.paper.colorScheme == .light)
        #expect(Theme.zen.colorScheme == .light)
        #expect(Theme.sunset.colorScheme == .dark)
        #expect(Theme.mono.fontDesign == .monospaced)
    }
}
