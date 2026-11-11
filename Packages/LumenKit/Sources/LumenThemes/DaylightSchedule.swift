import Foundation

/// «Свет по времени суток»: днём одна схема, вечером другая, ночью третья.
/// Это отдельная настройка, по умолчанию выключена: пользователь включает её сам.
public struct DaylightSchedule: Sendable, Equatable {
    public enum Period: String, Sendable, CaseIterable {
        case day, evening, night

        public var title: String {
            switch self {
            case .day: "Днём"
            case .evening: "Вечером"
            case .night: "Ночью"
            }
        }

        /// Часы начала: день с 7:00, вечер с 19:00, ночь с 23:00.
        public var startHour: Int {
            switch self {
            case .day: 7
            case .evening: 19
            case .night: 23
            }
        }

        /// Какая часть суток идёт в этот час (0...23).
        public static func at(hour: Int) -> Period {
            if hour >= Period.night.startHour || hour < Period.day.startHour { return .night }
            if hour >= Period.evening.startHour { return .evening }
            return .day
        }
    }

    public static let enabledKey = "appearance.daylight"
    public static let dayKey = "appearance.daylight.day"
    public static let eveningKey = "appearance.daylight.evening"
    public static let nightKey = "appearance.daylight.night"

    public var dayID: String
    public var eveningID: String
    public var nightID: String

    public init(dayID: String = Theme.linen.id, eveningID: String = Theme.study.id, nightID: String = Theme.midnight.id) {
        self.dayID = dayID
        self.eveningID = eveningID
        self.nightID = nightID
    }

    public func schemeID(for period: Period) -> String {
        switch period {
        case .day: dayID
        case .evening: eveningID
        case .night: nightID
        }
    }

    /// Схема на данный момент.
    public func theme(at date: Date, calendar: Calendar = .current) -> Theme {
        Theme.named(schemeID(for: .at(hour: calendar.component(.hour, from: date))))
    }

    /// Когда сменится часть суток: к этому моменту тему надо пересчитать.
    public static func nextChange(after date: Date, calendar: Calendar = .current) -> Date {
        let hours = Period.allCases.map(\.startHour)
        let candidates = hours.compactMap { hour in
            calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0, second: 0), matchingPolicy: .nextTime)
        }
        return candidates.min() ?? date.addingTimeInterval(3600)
    }
}
