import Foundation
@testable import LumenUI
import Testing

/// Таймер учёбы в режиме фокуса.
@MainActor
struct UsabilityTests {
    @Test func studyTimerShowsMinutesAndSecondsLeft() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(FocusModeState.remaining(until: now.addingTimeInterval(25 * 60), now: now) == "25:00")
        #expect(FocusModeState.remaining(until: now.addingTimeInterval(61.2), now: now) == "01:02")
        #expect(FocusModeState.remaining(until: now.addingTimeInterval(-5), now: now) == "00:00", "Истёкший таймер не уходит в минус")
    }
}
