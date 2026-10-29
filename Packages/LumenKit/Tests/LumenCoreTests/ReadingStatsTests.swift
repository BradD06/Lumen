import Foundation
import Testing
@testable import LumenCore

struct ReadingStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func session(_ day: Int, minutes: Double, hour: Int = 12) -> ReadingSession {
        ReadingSession(sourceId: UUID(), startedAt: date(day, hour), endedAt: date(day, hour), seconds: minutes * 60)
    }

    @Test func totalsAndToday() {
        let stats = ReadingStats(
            sessions: [session(27, minutes: 30), session(29, minutes: 10, hour: 9), session(29, minutes: 5, hour: 20)],
            now: date(29, 22),
            calendar: calendar
        )
        #expect(stats.totalSeconds == 45 * 60)
        #expect(stats.todaySeconds == 15 * 60)
        #expect(stats.daysRead == 2)
        #expect(stats.recentDays.count == ReadingStats.dayCount)
        #expect(stats.recentDays.last?.seconds == 15 * 60)
        #expect(stats.recentDays[ReadingStats.dayCount - 3].seconds == 30 * 60)
    }

    @Test func streakCountsConsecutiveDaysAndSurvivesUntilEndOfToday() {
        let sessions = [session(25, minutes: 5), session(27, minutes: 5), session(28, minutes: 5)]
        // Сегодня 29-е, ещё не читали: серия 27–28 не прервана.
        #expect(ReadingStats(sessions: sessions, now: date(29), calendar: calendar).streakDays == 2)
        // Прочитали и сегодня.
        #expect(ReadingStats(sessions: sessions + [session(29, minutes: 1)], now: date(29), calendar: calendar).streakDays == 3)
        // Пропустили вчера: серии нет.
        #expect(ReadingStats(sessions: sessions, now: date(30), calendar: calendar).streakDays == 0)
    }

    @Test func formatting() {
        #expect(ReadingStats.format(0) == "0 мин")
        #expect(ReadingStats.format(20) == "меньше минуты")
        #expect(ReadingStats.format(25 * 60) == "25 мин")
        #expect(ReadingStats.format(120 * 60) == "2 ч")
        #expect(ReadingStats.format(135 * 60 + 30) == "2 ч 15 мин")
    }
}
