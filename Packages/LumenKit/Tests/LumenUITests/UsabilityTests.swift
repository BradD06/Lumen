import Foundation
import LumenThemes
@testable import LumenUI
import Testing

/// Таймер учёбы в режиме фокуса и смена темы из ⌘K.
@MainActor
struct UsabilityTests {
    @Test func studyTimerShowsMinutesAndSecondsLeft() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(FocusModeState.remaining(until: now.addingTimeInterval(25 * 60), now: now) == "25:00")
        #expect(FocusModeState.remaining(until: now.addingTimeInterval(61.2), now: now) == "01:02")
        #expect(FocusModeState.remaining(until: now.addingTimeInterval(-5), now: now) == "00:00", "Истёкший таймер не уходит в минус")
    }

    @Test func paletteSwitchesThemeAndSkipsTheCurrentOne() throws {
        let suite = "lumen.tests.palette-themes"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Theme.paper.id, forKey: Theme.storageKey)

        let commands = PaletteCommand.themes(defaults: defaults)
        #expect(commands.count == Theme.all.count - 1)
        #expect(!commands.contains { $0.title == "Тема: \(Theme.paper.name)" }, "Текущую тему не предлагаем")

        let mono = try #require(commands.first { $0.title == "Тема: \(Theme.mono.name)" })
        #expect(mono.matches("тема"))
        #expect(mono.matches("оформление монохром"))
        mono.run()
        #expect(defaults.string(forKey: Theme.storageKey) == Theme.mono.id)
    }
}
