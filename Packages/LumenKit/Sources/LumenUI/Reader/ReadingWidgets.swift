import LumenCore
import LumenThemes
import SwiftUI

/// Цель на день: сколько минут читать. 0 значит без цели. Одна на все книги.
enum ReadingGoal {
    static let key = "reading.dailyGoalMinutes"
    static let defaultMinutes = 30
    static let choices = [0, 15, 30, 45, 60]

    static func title(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Без цели"
        case 60: "1 ч"
        default: "\(minutes) мин"
        }
    }
}

/// Тексты про чтение: дни, даты, прогноз.
enum ReadingText {
    static let locale = Locale(identifier: "ru_RU")

    static func days(_ count: Int) -> String {
        plural(count, one: "день", few: "дня", many: "дней")
    }

    static func books(_ count: Int) -> String {
        plural(count, one: "книга", few: "книги", many: "книг")
    }

    /// Русское множественное число: 1 книга, 3 книги, 5 книг, 21 книга.
    /// Своё, а не у экрана книги: у вида оно привязано к главному потоку.
    static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        let tens = count % 100
        let units = count % 10
        if (11...14).contains(tens) { return many }
        if units == 1 { return one }
        if (2...4).contains(units) { return few }
        return many
    }

    /// «сегодня», «завтра», «25 ноября», в другом году «3 февраля 2027».
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "сегодня" }
        if calendar.isDateInTomorrow(date) { return "завтра" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
            return date.formatted(.dateTime.day().month(.wide).locale(locale))
        }
        return date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    /// «Сегодня», «Вчера», «чт, 12 нояб.».
    static func sessionDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().locale(locale))
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// «ещё 12 мин до цели», «цель выполнена».
    static func goalCaption(today: Double, goalMinutes: Int) -> String {
        guard goalMinutes > 0 else { return "цель на день не задана" }
        let left = Double(goalMinutes * 60) - today
        if left <= 0 { return "цель \(ReadingGoal.title(goalMinutes)) выполнена" }
        return "ещё \(ReadingStats.format(left, short: true)) до цели"
    }
}

/// Кольцо цели на день. Выполненная цель закрывает кольцо и ставит галочку.
struct ReadingGoalRing<Center: View>: View {
    let fraction: Double
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7
    @ViewBuilder var center: () -> Center

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.textPrimary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.accent.opacity(0.45), radius: 4)
            center()
        }
        .frame(width: size, height: size)
        .animation(LumenMotion.gentle, value: fraction)
    }
}

/// Карточка с крупным числом: «Время с книгой», «Осталось», «Серия».
/// `isAccent` подкрашивает её латунью, чтобы главное число бросалось в глаза.
struct ReadingFactCard: View {
    let title: String
    let value: String
    var caption: String?
    var isAccent = false

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(theme.accent)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .readingCard(isAccent: isAccent)
    }
}

extension View {
    /// Стеклянная карточка «Кабинета»; с `isAccent` в латунном стекле.
    @ViewBuilder
    func readingCard(isAccent: Bool = false, padding: CGFloat = 16) -> some View {
        if isAccent {
            modifier(AccentCardModifier(padding: padding))
        } else {
            lumenCard(padding: padding)
        }
    }
}

private struct AccentCardModifier: ViewModifier {
    let padding: CGFloat
    @Environment(\.lumenTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(theme.textPrimary)
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(LinearGradient(
                        colors: [theme.accent.opacity(0.30), theme.accent.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )))
                    .shadow(color: .black.opacity(theme.shadowOpacity), radius: 16, y: 8)
            }
            .overlay(shape.strokeBorder(theme.accent.opacity(0.45), lineWidth: 1))
    }
}

/// Подпись карточки: «ДНИ С КНИГОЙ · 3 МЕСЯЦА».
struct ReadingCardTitle: View {
    let title: String
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(theme.textSecondary)
    }
}

/// Календарь дней чтения: столбец на неделю (с понедельника), клетка тем ярче, чем дольше читали.
struct ReadingHeatmap: View {
    let secondsByDay: [Date: Double]
    var weeks = 13
    var cell: CGFloat = 16
    var spacing: CGFloat = 4

    @Environment(\.lumenTheme) private var theme

    struct Day: Identifiable {
        var date: Date
        var seconds: Double
        var isFuture: Bool
        var isToday: Bool

        var id: Date { date }
    }

    private static let weekdays = ["пн", "", "ср", "", "пт", "", "вс"]

    var body: some View {
        let columns = Self.columns(weeks: weeks, secondsByDay: secondsByDay)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: spacing) {
                weekdayLabels
                VStack(alignment: .leading, spacing: 4) {
                    monthLabels(columns)
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(columns.indices, id: \.self) { index in
                            VStack(spacing: spacing) {
                                ForEach(columns[index]) { day in
                                    cellView(day)
                                }
                            }
                        }
                    }
                }
            }
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Дней с чтением: \(columns.joined().filter { $0.seconds > 0 }.count)")
    }

    private var weekdayLabels: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Color.clear.frame(height: 12)
            ForEach(Self.weekdays.indices, id: \.self) { index in
                Text(Self.weekdays[index])
                    .font(.system(size: max(8, min(cell * 0.6, 10))))
                    .foregroundStyle(theme.textSecondary)
                    .frame(height: cell)
            }
        }
    }

    /// Название месяца над неделей, в которой он начинается.
    private func monthLabels(_ columns: [[Day]]) -> some View {
        HStack(spacing: spacing) {
            ForEach(columns.indices, id: \.self) { index in
                let first = columns[index].first?.date ?? .now
                let previous = index > 0 ? columns[index - 1].first?.date : nil
                let isNewMonth = previous.map { Calendar.current.component(.month, from: $0) != Calendar.current.component(.month, from: first) } ?? true
                Color.clear
                    .frame(width: cell, height: 12)
                    .overlay(alignment: .leading) {
                        if isNewMonth, index < columns.count - 1 || columns.count == 1 {
                            Text(first.formatted(.dateTime.month(.abbreviated).locale(ReadingText.locale)))
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize()
                        }
                    }
            }
        }
    }

    private func cellView(_ day: Day) -> some View {
        RoundedRectangle(cornerRadius: max(2, cell / 4), style: .continuous)
            .fill(day.isFuture ? Color.clear : fill(day.seconds))
            .frame(width: cell, height: cell)
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: max(2, cell / 4), style: .continuous)
                        .strokeBorder(theme.textPrimary.opacity(0.8), lineWidth: 1)
                }
            }
            .help(day.isFuture ? "" : "\(day.date.formatted(.dateTime.day().month(.wide).locale(ReadingText.locale))): \(day.seconds > 0 ? ReadingStats.format(day.seconds) : "не читали")")
    }

    private var legend: some View {
        HStack(spacing: 5) {
            Text("меньше")
            ForEach([0.0, 10, 20, 45, 90], id: \.self) { minutes in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill(minutes * 60))
                    .frame(width: 11, height: 11)
            }
            Text("больше")
        }
        .font(.caption2)
        .foregroundStyle(theme.textSecondary)
    }

    /// До 15 минут, до получаса, до часа и больше часа.
    private func fill(_ seconds: Double) -> Color {
        switch seconds {
        case ..<1: theme.textPrimary.opacity(0.08)
        case ..<(15 * 60): theme.accent.opacity(0.30)
        case ..<(30 * 60): theme.accent.opacity(0.55)
        case ..<(60 * 60): theme.accent.opacity(0.80)
        default: theme.accent
        }
    }

    static func columns(weeks: Int, secondsByDay: [Date: Double], now: Date = .now) -> [[Day]] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        guard let first = calendar.date(byAdding: .weekOfYear, value: -(max(weeks, 1) - 1), to: thisWeek) else { return [] }
        return (0..<max(weeks, 1)).map { week in
            (0..<7).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: first) else { return nil }
                let day = calendar.startOfDay(for: date)
                return Day(date: day, seconds: secondsByDay[day] ?? 0, isFuture: day > today, isToday: day == today)
            }
        }
    }
}

/// Кнопка «Назад» в шапке экрана, как у папок в библиотеке. На iPhone её нет: там своя стрелка в панели.
struct ScreenBackButton: View {
    var title = "Назад"
    var action: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Capsule().fill(theme.cardFill))
                .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyHint(title, perform: action)
        .help("\(title) (⌘[)")
        .accessibilityIdentifier("screen-back")
    }
}
