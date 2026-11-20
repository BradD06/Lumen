import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// «Чтение»: время по всем книгам. Сегодня и цель на день, неделя, месяц или год
/// столбиками по книгам, серия дней, год чтения клетками и книги по времени.
struct ReadingOverviewView: View {
    let database: AppDatabase
    /// Открыть панель книги.
    var onOpenSource: (UUID) -> Void
    /// Вернуться туда, откуда пришли. `nil` на iPhone: там стрелка в панели навигации.
    var onBack: (() -> Void)?

    @State private var snapshot = ReadingOverviewSnapshot.empty
    @State private var period: ReadingOverview.Period = .week
    @Setting(ReadingGoal.key) private var goalMinutes = ReadingGoal.defaultMinutes
    @Environment(\.lumenTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var stats: ReadingStats { ReadingStats(sessions: snapshot.sessions) }
    private var overview: ReadingOverview { ReadingOverview(period: period, sessions: snapshot.sessions) }

    var body: some View {
        let stats = stats
        let overview = overview
        let sources = Dictionary(snapshot.sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let colors = bookColors(overview)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let onBack {
                    ScreenBackButton(action: onBack)
                }
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14, alignment: .top)], spacing: 14) {
                    todayCard(stats)
                    ReadingFactCard(title: periodTotalTitle, value: ReadingStats.format(overview.totalSeconds, short: true), caption: comparison(overview))
                    ReadingFactCard(
                        title: "Серия",
                        value: "\(stats.streakDays) \(ReadingText.days(stats.streakDays))",
                        caption: stats.longestStreakDays > stats.streakDays
                            ? "рекорд \(stats.longestStreakDays) \(ReadingText.days(stats.longestStreakDays))"
                            : (stats.streakDays > 1 ? "это твой рекорд" : "читай каждый день, и серия вырастет")
                    )
                    ReadingFactCard(title: "Дочитано в \(String(Calendar.current.component(.year, from: .now)))", value: finishedValue, caption: readingNowCaption)
                }
                barsCard(overview, sources: sources, colors: colors)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14, alignment: .top)], spacing: 14) {
                    yearCard(stats)
                    booksCard(overview, sources: sources, colors: colors)
                }
            }
            .padding(isCompact ? 16 : 24)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .keyHintClip()
        .background(ThemedBackground())
        .navigationTitle("Чтение")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await observe() }
        .accessibilityIdentifier("readingOverview")
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    // MARK: Шапка

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) {
                title
                Spacer(minLength: 12)
                periodPicker
            }
            VStack(alignment: .leading, spacing: 12) {
                title
                periodPicker
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Все книги")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textSecondary)
            Text("Чтение")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(ReadingOverview.Period.allCases) { item in
                Button {
                    withAnimation(LumenMotion.standard) { period = item }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(period == item ? theme.onAccent : theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background {
                            if period == item {
                                Capsule().fill(theme.accent)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyHint(item.title) { period = item }
                .accessibilityAddTraits(period == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(theme.cardFill))
        .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
    }

    // MARK: Числа

    private func todayCard(_ stats: ReadingStats) -> some View {
        let goal = Double(goalMinutes * 60)
        let fraction = goal > 0 ? stats.todaySeconds / goal : 0
        return HStack(spacing: 14) {
            ReadingGoalRing(fraction: goalMinutes > 0 ? fraction : 0, size: 72, lineWidth: 8) {
                if goalMinutes > 0, fraction >= 1 {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                } else {
                    Text("\(Int(stats.todaySeconds / 60))")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Сегодня")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(theme.accent)
                Text(ReadingStats.format(stats.todaySeconds, short: true))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(ReadingText.goalCaption(today: stats.todaySeconds, goalMinutes: goalMinutes))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .readingCard(isAccent: true)
    }

    private var periodTotalTitle: String {
        switch period {
        case .week: "За неделю"
        case .month: "За месяц"
        case .year: "За год"
        }
    }

    private func comparison(_ overview: ReadingOverview) -> String {
        let previousName = switch period {
        case .week: "на прошлой"
        case .month: "в прошлом месяце"
        case .year: "в прошлом году"
        }
        let difference = overview.totalSeconds - overview.previousSeconds
        if overview.previousSeconds < 60, overview.totalSeconds < 60 { return "пока без чтения" }
        if abs(difference) < 60 { return "столько же, сколько \(previousName)" }
        let amount = ReadingStats.format(abs(difference), short: true)
        return difference > 0 ? "на \(amount) больше, чем \(previousName)" : "на \(amount) меньше, чем \(previousName)"
    }

    /// Дочитанные в этом году: прогресс дошёл до конца, а читали или открывали их в этом году.
    private var finishedThisYear: [Source] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: .now)
        var lastRead: [UUID: Date] = [:]
        for session in snapshot.sessions {
            lastRead[session.sourceId] = max(lastRead[session.sourceId] ?? .distantPast, session.endedAt)
        }
        return snapshot.sources.filter { source in
            guard source.progress >= 0.995 else { return false }
            guard let date = lastRead[source.id] ?? source.lastOpenedAt else { return false }
            return calendar.component(.year, from: date) == year
        }
    }

    private var finishedValue: String {
        let count = finishedThisYear.count
        return "\(count) \(ReadingText.books(count))"
    }

    private var readingNowCaption: String {
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recent = Set(snapshot.sessions.filter { $0.endedAt >= monthAgo }.map(\.sourceId))
        let count = snapshot.sources.filter { recent.contains($0.id) && $0.progress < 0.995 }.count
        return count == 0 ? "сейчас ничего не читаешь" : "и \(count) \(ReadingText.books(count)) читаешь сейчас"
    }

    // MARK: Столбики

    /// Три книги, которые читали дольше всех за период, получают свои цвета; остальные вместе.
    private func bookColors(_ overview: ReadingOverview) -> [UUID: Color] {
        let palette = [theme.accent, theme.success, theme.textTertiary]
        var colors: [UUID: Color] = [:]
        for (index, book) in overview.books.prefix(palette.count).enumerated() {
            colors[book.sourceId] = palette[index]
        }
        return colors
    }

    private var otherColor: Color { theme.textPrimary.opacity(0.35) }

    private func barsCard(_ overview: ReadingOverview, sources: [UUID: Source], colors: [UUID: Color]) -> some View {
        let chartHeight: CGFloat = 150
        let goal = period == .year ? 0 : Double(goalMinutes * 60)
        let tallest = overview.bars.map(\.seconds).max() ?? 0
        let scale = max(tallest, goal * 1.15, 15 * 60)
        let showsValues = period == .week
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                ReadingCardTitle(title: barsTitle)
                Spacer(minLength: 12)
                legend(overview, sources: sources, colors: colors)
            }
            ZStack(alignment: .bottomLeading) {
                if goal > 0 {
                    let y = chartHeight * goal / scale
                    GoalLine()
                        .stroke(theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(height: 1)
                        .offset(y: -y)
                    Text("цель \(ReadingGoal.title(goalMinutes))")
                        .font(.caption2)
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: -y - 12)
                }
                HStack(alignment: .bottom, spacing: period == .month ? 3 : 8) {
                    ForEach(overview.bars) { bar in
                        barColumn(bar, height: chartHeight, scale: scale, colors: colors, showsValue: showsValues)
                    }
                }
            }
            .frame(height: chartHeight + (showsValues ? 18 : 0), alignment: .bottom)
            HStack(spacing: period == .month ? 3 : 8) {
                ForEach(overview.bars) { bar in
                    Text(barLabel(bar))
                        .font(.caption2.weight(bar.isCurrent ? .bold : .regular))
                        .foregroundStyle(bar.isCurrent ? theme.textPrimary : theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .lumenCard(padding: 18)
    }

    private var barsTitle: String {
        switch period {
        case .week: "Эта неделя · по книгам"
        case .month: "Этот месяц · по книгам"
        case .year: "Этот год · по книгам"
        }
    }

    private func barColumn(_ bar: ReadingOverview.Bar, height: CGFloat, scale: Double, colors: [UUID: Color], showsValue: Bool) -> some View {
        // Свои цвета у трёх главных книг, остальные одним куском сверху.
        var segments: [BarSegment] = []
        var other: Double = 0
        for book in bar.books {
            if let color = colors[book.sourceId] {
                segments.append(BarSegment(id: book.sourceId.uuidString, color: color, seconds: book.seconds))
            } else {
                other += book.seconds
            }
        }
        if other > 0 { segments.insert(BarSegment(id: "other", color: otherColor, seconds: other), at: 0) }
        let total = bar.seconds
        return VStack(spacing: 4) {
            if showsValue {
                Text(total > 0 ? ReadingStats.format(total, short: true) : "—")
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            VStack(spacing: 0) {
                if total == 0 {
                    Rectangle().fill(theme.textPrimary.opacity(bar.isFuture ? 0.04 : 0.1)).frame(height: 4)
                } else {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(height: max(1, height * segment.seconds / scale))
                    }
                }
            }
            .frame(maxWidth: period == .month ? CGFloat.infinity : 46)
            .clipShape(RoundedRectangle(cornerRadius: period == .month ? 3 : 7, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .help(total > 0 ? "\(barHelpDate(bar)): \(ReadingStats.format(total))" : barHelpDate(bar))
        .animation(LumenMotion.standard, value: total)
    }

    private func barLabel(_ bar: ReadingOverview.Bar) -> String {
        let calendar = Calendar.current
        switch period {
        case .week:
            return bar.isCurrent ? "Сегодня" : bar.start.formatted(.dateTime.weekday(.abbreviated).locale(ReadingText.locale)).capitalized
        case .month:
            let day = calendar.component(.day, from: bar.start)
            return day == 1 || day % 5 == 0 ? "\(day)" : ""
        case .year:
            return bar.start.formatted(.dateTime.month(.abbreviated).locale(ReadingText.locale))
        }
    }

    private func barHelpDate(_ bar: ReadingOverview.Bar) -> String {
        switch period {
        case .week, .month: bar.start.formatted(.dateTime.day().month(.wide).locale(ReadingText.locale))
        case .year: bar.start.formatted(.dateTime.month(.wide).locale(ReadingText.locale))
        }
    }

    @ViewBuilder
    private func legend(_ overview: ReadingOverview, sources: [UUID: Source], colors: [UUID: Color]) -> some View {
        let top = overview.books.filter { colors[$0.sourceId] != nil }
        if !top.isEmpty, !isCompact {
            HStack(spacing: 12) {
                ForEach(top) { book in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(colors[book.sourceId] ?? otherColor).frame(width: 10, height: 10)
                        Text(sources[book.sourceId]?.displayTitle ?? "Книга")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 160, alignment: .leading)
                    }
                }
                if overview.books.count > top.count {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(otherColor).frame(width: 10, height: 10)
                        Text("другие")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: Год и книги

    private func yearCard(_ stats: ReadingStats) -> some View {
        let yearAgo = Calendar.current.date(byAdding: .day, value: -364, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let days = stats.secondsByDay.filter { $0.key >= yearAgo && $0.value > 0 }.count
        return VStack(alignment: .leading, spacing: 14) {
            ReadingCardTitle(title: "Год чтения · \(days) \(ReadingText.days(days)) с книгой")
            ScrollView(.horizontal, showsIndicators: false) {
                ReadingHeatmap(secondsByDay: stats.secondsByDay, weeks: 53, cell: 9, spacing: 2)
            }
            .defaultScrollAnchor(.trailing)
            Rectangle().fill(theme.textPrimary.opacity(0.08)).frame(height: 1)
            ReadingCardTitle(title: "Цель на день")
            goalPicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lumenCard(padding: 18)
    }

    private var goalPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { goalButtons }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) { goalButtons }
        }
    }

    private var goalButtons: some View {
        ForEach(ReadingGoal.choices, id: \.self) { minutes in
            let isOn = goalMinutes == minutes
            Button {
                withAnimation(LumenMotion.quick) { goalMinutes = minutes }
                LumenSounds.play(.navigate)
            } label: {
                Text(ReadingGoal.title(minutes))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? theme.onAccent : theme.textPrimary)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 34)
                    .background(Capsule().fill(isOn ? theme.accent : theme.cardFill))
                    .overlay(Capsule().strokeBorder(isOn ? Color.clear : theme.cardStroke, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyHint("Цель: \(ReadingGoal.title(minutes))") { goalMinutes = minutes }
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }

    private func booksCard(_ overview: ReadingOverview, sources: [UUID: Source], colors: [UUID: Color]) -> some View {
        let books = overview.books.compactMap { book in sources[book.sourceId].map { BookRow(book: book, source: $0) } }.prefix(8)
        return VStack(alignment: .leading, spacing: 0) {
            ReadingCardTitle(title: "Книги по времени")
                .padding(.bottom, 8)
            if books.isEmpty {
                Text(period == .week ? "На этой неделе книг ещё не открывали." : "За этот период книг не открывали.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(Array(books)) { row in
                let book = row.book
                let source = row.source
                Button {
                    LumenSounds.play(.navigate)
                    onOpenSource(source.id)
                } label: {
                    HStack(spacing: 12) {
                        SourceCoverArt(source: source, attachments: database.attachments, width: 28, height: 40)
                            .overlay(alignment: .leading) {
                                if let color = colors[source.id] {
                                    Rectangle().fill(color).frame(width: 3)
                                }
                            }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(source.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            ReadingProgressBar(progress: source.progress)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ReadingStats.format(book.seconds, short: true))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(theme.textPrimary)
                            Text(source.progress >= 0.995 ? "дочитана" : ReadingText.percent(source.progress))
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .fixedSize()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyHint(source.displayTitle) { onOpenSource(source.id) }
                .help("Открыть панель книги")
                .overlay(alignment: .top) {
                    Rectangle().fill(theme.textPrimary.opacity(0.08)).frame(height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lumenCard(padding: 18)
    }

    // MARK: Данные

    private func observe() async {
        let observation = ValueObservation.tracking { db in try ReadingOverviewSnapshot.fetch(db) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation(LumenMotion.standard) { snapshot = value }
            }
        } catch {
            lumenLog.error("Reading overview observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

private struct BarSegment: Identifiable {
    var id: String
    var color: Color
    var seconds: Double
}

private struct BookRow: Identifiable {
    var book: ReadingOverview.BookTime
    var source: Source

    var id: UUID { source.id }
}

/// Пунктир цели поперёк графика.
private struct GoalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
