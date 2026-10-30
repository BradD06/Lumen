import Foundation

/// Отрезок чтения одного источника: сколько секунд читали между открытием и закрытием книги.
/// Время считается только пока человек что-то делает в книге, без простоев.
public struct ReadingSession: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sourceId: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var seconds: Double

    public init(id: UUID = UUID(), sourceId: UUID, startedAt: Date, endedAt: Date, seconds: Double) {
        self.id = id
        self.sourceId = sourceId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.seconds = seconds
    }
}

/// Сводка по чтению для дашборда книги: всего, сегодня, серия дней и последние две недели.
public struct ReadingStats: Hashable, Sendable {
    public struct Day: Hashable, Sendable, Identifiable {
        /// Начало дня.
        public var date: Date
        public var seconds: Double

        public var id: Date { date }
    }

    public var totalSeconds: Double
    public var todaySeconds: Double
    /// Сколько дней подряд читали, включая сегодня. Если сегодня ещё не читали, серия
    /// не прерывается до конца дня и считается со вчерашнего.
    public var streakDays: Int
    /// Дни, в которые вообще читали.
    public var daysRead: Int
    /// Последние `dayCount` дней, старые слева, сегодня последним.
    public var recentDays: [Day]

    public static let dayCount = 14
    public static let empty = ReadingStats(sessions: [])

    public init(sessions: [ReadingSession], now: Date = Date(), calendar: Calendar = .current) {
        var byDay: [Date: Double] = [:]
        for session in sessions where session.seconds > 0 {
            byDay[calendar.startOfDay(for: session.endedAt), default: 0] += session.seconds
        }
        let today = calendar.startOfDay(for: now)
        totalSeconds = byDay.values.reduce(0, +)
        todaySeconds = byDay[today] ?? 0
        daysRead = byDay.count

        var streak = 0
        var day = byDay[today] != nil ? today : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while byDay[day] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        streakDays = streak

        recentDays = (0..<Self.dayCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { Day(date: $0, seconds: byDay[$0] ?? 0) }
        }
    }

    /// «2 ч 15 мин», «25 мин», «меньше минуты».
    /// `short` для крупных чисел на карточках: «<1 мин» вместо «меньше минуты».
    public static func format(_ seconds: Double, short: Bool = false) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return seconds > 0 ? (short ? "<1 мин" : "меньше минуты") : "0 мин" }
        let hours = minutes / 60
        if hours == 0 { return "\(minutes) мин" }
        let rest = minutes % 60
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
    }
}
