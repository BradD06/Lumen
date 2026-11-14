import Foundation
import Testing
@testable import LumenCore

struct ReadingInsightsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    /// Ноябрь 2026: 14-е это суббота, 9-е понедельник.
    private func date(_ day: Int, _ hour: Int = 12, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func session(
        _ day: Int,
        minutes: Double,
        book: UUID = UUID(),
        month: Int = 11,
        from start: Double? = nil,
        to end: Double? = nil
    ) -> ReadingSession {
        ReadingSession(
            sourceId: book,
            startedAt: date(day, month: month),
            endedAt: date(day, month: month),
            seconds: minutes * 60,
            startProgress: start,
            endProgress: end
        )
    }

    @Test func longestStreakAndSecondsInRange() {
        let sessions = [1, 2, 3, 5, 6, 13, 14].map { session($0, minutes: 10) }
        let stats = ReadingStats(sessions: sessions, now: date(14, 20), calendar: calendar)
        #expect(stats.streakDays == 2)
        #expect(stats.longestStreakDays == 3)
        let start = calendar.startOfDay(for: date(5))
        let end = calendar.startOfDay(for: date(13))
        #expect(stats.seconds(from: start, through: end) == 30 * 60)
    }

    @Test func forecastUsesMeasuredPaceAndDailyTime() {
        let book = UUID()
        // За час прочитали четверть книги, всего половину: осталось 2 часа.
        let sessions = [
            session(13, minutes: 30, book: book, from: 0.25, to: 0.375),
            session(14, minutes: 30, book: book, from: 0.375, to: 0.5),
        ]
        let forecast = ReadingForecast(progress: 0.5, sessions: sessions, now: date(14, 20), calendar: calendar)
        #expect(forecast.pacePerHour == 0.25)
        #expect(forecast.remainingSeconds == 2 * 3600)
        // Читали два дня по 30 минут: 30 минут в день, 4 дня до конца, считая сегодня.
        #expect(forecast.dailySeconds == 30 * 60)
        #expect(forecast.finishDate == calendar.startOfDay(for: date(17)))
    }

    @Test func forecastFallsBackToWholeBookAndNeedsEnoughReading() {
        let book = UUID()
        let old = [session(10, minutes: 120, book: book)]
        let forecast = ReadingForecast(progress: 0.5, sessions: old, now: date(14), calendar: calendar)
        #expect(forecast.pacePerHour == 0.25)
        #expect(forecast.remainingSeconds == 2 * 3600)

        let tooLittle = ReadingForecast(progress: 0.5, sessions: [session(14, minutes: 3, book: book)], now: date(14), calendar: calendar)
        #expect(tooLittle.pacePerHour == nil)
        #expect(tooLittle.remainingSeconds == nil)
        #expect(tooLittle.finishDate == nil)

        let done = ReadingForecast(progress: 1, sessions: old, now: date(14), calendar: calendar)
        #expect(done.remainingSeconds == 0)
    }

    @Test func goingBackDoesNotCountAsReading() {
        #expect(session(14, minutes: 10, from: 0.5, to: 0.4).progressGain == 0)
        #expect(session(14, minutes: 10).progressGain == nil)
    }

    @Test func weekOverviewSplitsDaysByBook() throws {
        let first = UUID()
        let second = UUID()
        let sessions = [
            session(9, minutes: 20, book: first),
            session(9, minutes: 10, book: second),
            session(14, minutes: 35, book: first),
            // Прошлая неделя до той же субботы и после неё.
            session(3, minutes: 15, book: second),
            session(8, minutes: 50, book: second),
        ]
        let overview = ReadingOverview(period: .week, sessions: sessions, now: date(14, 20), calendar: calendar)
        #expect(overview.bars.count == 7)
        #expect(overview.start == calendar.startOfDay(for: date(9)))
        let monday = try #require(overview.bars.first)
        #expect(monday.seconds == 30 * 60)
        #expect(monday.books.map(\.sourceId) == [first, second])
        let today = overview.bars[5]
        #expect(today.isCurrent)
        #expect(overview.bars[6].isFuture)
        #expect(overview.totalSeconds == 65 * 60)
        #expect(overview.books.map(\.sourceId) == [first, second])
        // Воскресенье 8-го уже после «той же субботы» прошлой недели.
        #expect(overview.previousSeconds == 15 * 60)
    }

    @Test func yearOverviewHasMonthBars() {
        let overview = ReadingOverview(
            period: .year,
            sessions: [session(14, minutes: 10, month: 2), session(14, minutes: 20)],
            now: date(14),
            calendar: calendar
        )
        #expect(overview.bars.count == 12)
        #expect(overview.bars[1].seconds == 10 * 60)
        #expect(overview.bars[10].seconds == 20 * 60)
        #expect(overview.bars[10].isCurrent)
        #expect(overview.bars[11].isFuture)
    }
}
