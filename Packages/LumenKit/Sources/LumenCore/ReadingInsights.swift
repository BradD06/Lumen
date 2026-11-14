import Foundation

/// Сколько осталось читать книгу и когда её дочитают, если читать как сейчас.
public struct ReadingForecast: Hashable, Sendable {
    /// Доля книги за час чтения (0.08 это 8% в час).
    public var pacePerHour: Double?
    /// Сколько ещё читать, секунды. 0 у дочитанной книги, `nil`, пока данных мало.
    public var remainingSeconds: Double?
    /// Сколько в среднем читают эту книгу в день за последние две недели, секунды.
    public var dailySeconds: Double
    /// День, к которому дочитают при таком темпе и таком времени в день.
    public var finishDate: Date?

    /// Меньше 10 минут чтения или 1% книги не дают честного темпа.
    static let minimumSeconds: Double = 600
    static let minimumGain = 0.01
    static let windowDays = 14

    public init(progress: Double, sessions: [ReadingSession], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)

        // Темп по отрезкам, где записано, сколько прочитали; иначе по всей книге целиком.
        let measured = sessions.filter { $0.progressGain != nil && $0.seconds > 0 }
        let measuredSeconds = measured.reduce(0) { $0 + $1.seconds }
        let measuredGain = measured.reduce(0) { $0 + ($1.progressGain ?? 0) }
        let totalSeconds = sessions.reduce(0) { $0 + max($1.seconds, 0) }
        if measuredSeconds >= Self.minimumSeconds, measuredGain >= Self.minimumGain {
            pacePerHour = measuredGain * 3600 / measuredSeconds
        } else if totalSeconds >= Self.minimumSeconds, progress >= Self.minimumGain {
            pacePerHour = progress * 3600 / totalSeconds
        } else {
            pacePerHour = nil
        }

        let windowStart = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: today) ?? today
        let firstDay = sessions.map { calendar.startOfDay(for: $0.endedAt) }.min() ?? today
        let days = max((calendar.dateComponents([.day], from: max(windowStart, firstDay), to: today).day ?? 0) + 1, 1)
        let recent = sessions
            .filter { calendar.startOfDay(for: $0.endedAt) >= windowStart }
            .reduce(0) { $0 + max($1.seconds, 0) }
        dailySeconds = sessions.isEmpty ? 0 : recent / Double(days)

        if progress >= 0.995 {
            remainingSeconds = 0
            finishDate = nil
        } else if let pacePerHour, pacePerHour > 0 {
            let remaining = (1 - progress) / pacePerHour * 3600
            remainingSeconds = remaining
            if dailySeconds >= 60 {
                // Доли секунды от округления не должны добавлять целый день.
                let daysLeft = Int((remaining / dailySeconds - 0.000001).rounded(.up))
                finishDate = calendar.date(byAdding: .day, value: max(daysLeft - 1, 0), to: today)
            } else {
                finishDate = nil
            }
        } else {
            remainingSeconds = nil
            finishDate = nil
        }
    }
}

/// Чтение по всем книгам за неделю, месяц или год: столбики по дням или месяцам
/// с разбивкой по книгам и книги по времени.
public struct ReadingOverview: Hashable, Sendable {
    public enum Period: String, CaseIterable, Identifiable, Sendable {
        case week, month, year

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .week: "Неделя"
            case .month: "Месяц"
            case .year: "Год"
            }
        }
    }

    /// Один столбик: день (неделя и месяц) или месяц (год).
    public struct Bar: Hashable, Sendable, Identifiable {
        public var start: Date
        /// Время по книгам, больше сверху.
        public var books: [BookTime]
        public var isCurrent: Bool
        public var isFuture: Bool

        public var id: Date { start }
        public var seconds: Double { books.reduce(0) { $0 + $1.seconds } }
    }

    public struct BookTime: Hashable, Sendable, Identifiable {
        public var sourceId: UUID
        public var seconds: Double

        public var id: UUID { sourceId }
    }

    public var period: Period
    /// Начало периода (понедельник, 1-е число или 1 января) и начало следующего.
    public var start: Date
    public var end: Date
    public var bars: [Bar]
    /// Книги по времени за период, больше первыми.
    public var books: [BookTime]
    public var totalSeconds: Double
    /// Столько же за прошлый период, до того же дня.
    public var previousSeconds: Double

    public init(period: Period, sessions: [ReadingSession], now: Date = Date(), calendar: Calendar = .current) {
        var calendar = calendar
        // Неделя с понедельника, как в России.
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let component: Calendar.Component = switch period {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        let start = calendar.dateInterval(of: component, for: today)?.start ?? today
        let end = calendar.date(byAdding: component, value: 1, to: start) ?? today
        self.period = period
        self.start = start
        self.end = end

        let step: Calendar.Component = period == .year ? .month : .day
        var perBar: [Date: [UUID: Double]] = [:]
        var perBook: [UUID: Double] = [:]
        var previous: Double = 0
        let previousStart = calendar.date(byAdding: component, value: -1, to: start) ?? start
        // Прошлый период сравнивается до того же дня, чтобы во вторник не сравнивать с целой неделей.
        let elapsed = now.timeIntervalSince(start)
        let previousEnd = previousStart.addingTimeInterval(elapsed)
        for session in sessions where session.seconds > 0 {
            let moment = session.endedAt
            if moment >= start, moment < end {
                let bucket = calendar.dateInterval(of: step, for: moment)?.start ?? moment
                perBar[bucket, default: [:]][session.sourceId, default: 0] += session.seconds
                perBook[session.sourceId, default: 0] += session.seconds
            } else if moment >= previousStart, moment < previousEnd {
                previous += session.seconds
            }
        }

        var bars: [Bar] = []
        var cursor = start
        let currentBucket = calendar.dateInterval(of: step, for: today)?.start ?? today
        while cursor < end {
            let books = (perBar[cursor] ?? [:])
                .map { BookTime(sourceId: $0.key, seconds: $0.value) }
                .sorted { $0.seconds > $1.seconds }
            bars.append(Bar(start: cursor, books: books, isCurrent: cursor == currentBucket, isFuture: cursor > currentBucket))
            guard let next = calendar.date(byAdding: step, value: 1, to: cursor) else { break }
            cursor = next
        }
        self.bars = bars
        books = perBook.map { BookTime(sourceId: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        totalSeconds = perBook.values.reduce(0, +)
        previousSeconds = previous
    }
}
