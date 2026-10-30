import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Дашборд книги: обложка, сколько прочитано, время чтения, серия дней,
/// все заметки и выделения по ней.
struct SourceDashboardView: View {
    let database: AppDatabase
    let sourceId: UUID
    var onRead: (UUID?) -> Void
    var onOpenPage: (UUID) -> Void

    @State private var snapshot = SourceDashboardSnapshot.empty
    @State private var hasLoaded = false
    @Environment(\.lumenTheme) private var theme

    private var stats: ReadingStats { ReadingStats(sessions: snapshot.sessions) }

    var body: some View {
        ScrollView {
            if let source = snapshot.source, !source.isTrashed {
                VStack(alignment: .leading, spacing: 18) {
                    header(source)
                    statCards(source)
                    activityCard
                    notesCard(source)
                    highlightsCard
                }
                .padding(24)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            } else if hasLoaded {
                ContentUnavailableView(
                    "Книги нет",
                    systemImage: "book.closed",
                    description: Text("Её удалили или переместили в корзину.")
                )
                .padding(.top, 80)
            }
        }
        .background(ThemedBackground())
        .navigationTitle(snapshot.source?.displayTitle ?? "")
        .task { await observe() }
    }

    // MARK: Шапка

    private func header(_ source: Source) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(spacing: 8) {
                SourceCoverArt(source: source, attachments: database.attachments, width: 122, height: 170)
                ReadingProgressBar(progress: source.progress)
                    .frame(width: 112)
                    .opacity(source.progress > 0.005 ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(source.format.label.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(theme.textSecondary)
                Text(source.displayTitle)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(3)
                if let author = source.author, !author.isEmpty {
                    Text(author)
                        .font(.title3)
                        .foregroundStyle(theme.textSecondary)
                }
                HStack(spacing: 10) {
                    Button {
                        LumenSounds.play(.navigate)
                        onRead(nil)
                    } label: {
                        Label(source.progress > 0.005 ? "Продолжить" : "Читать", systemImage: "book")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    Button {
                        openNotes()
                    } label: {
                        Label("Заметки к книге", systemImage: "note.text")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Числа

    private func statCards(_ source: Source) -> some View {
        let stats = stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
            StatCard(
                title: "Прочитано",
                value: "\(Int((source.progress * 100).rounded()))%",
                caption: source.lastOpenedAt.map { "открывали \(relative($0))" },
                systemImage: "book",
                style: .vivid(1)
            )
            StatCard(
                title: "Время",
                value: ReadingStats.format(stats.totalSeconds),
                caption: "сегодня \(ReadingStats.format(stats.todaySeconds))",
                systemImage: "clock",
                style: .vivid(0)
            )
            StatCard(
                title: "Серия",
                value: "\(stats.streakDays)",
                caption: "\(Self.days(stats.streakDays)) подряд · всего \(stats.daysRead) \(Self.days(stats.daysRead))",
                systemImage: "flame",
                style: .vivid(2)
            )
            StatCard(
                title: "Выделения",
                value: "\(snapshot.highlights.count)",
                caption: "выписки на \(notesPageCount) \(notesPageCount == 1 ? "странице" : "страницах")",
                systemImage: "highlighter"
            )
        }
    }

    private var notesPageCount: Int {
        snapshot.excerptPages.count + (snapshot.notesPage == nil ? 0 : 1)
    }

    /// Столбики по дням за две недели: высота это минуты чтения.
    private var activityCard: some View {
        let days = stats.recentDays
        let maximum = max(days.map(\.seconds).max() ?? 0, 60)
        return VStack(alignment: .leading, spacing: 12) {
            cardTitle("Последние две недели", systemImage: "chart.bar")
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.seconds > 0 ? theme.accent : theme.textSecondary.opacity(0.18))
                            .frame(height: max(4, 90 * day.seconds / maximum))
                            .help("\(day.date.formatted(.dateTime.day().month())): \(ReadingStats.format(day.seconds))")
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.caption2)
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? theme.textPrimary : theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112, alignment: .bottom)
        }
        .lumenCard()
    }

    // MARK: Заметки и выделения

    private func notesCard(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            cardTitle("Заметки", systemImage: "note.text")
            Button(action: openNotes) {
                pageRow(icon: "📖", title: "Заметки к книге", caption: snapshot.notesPage.map { "изменено \(relative($0.updatedAt))" })
            }
            .buttonStyle(.plain)
            ForEach(snapshot.excerptPages) { entry in
                Button {
                    LumenSounds.play(.navigate)
                    onOpenPage(entry.page.id)
                } label: {
                    pageRow(
                        icon: entry.page.icon ?? "📄",
                        title: entry.page.displayTitle,
                        caption: "\(entry.excerptCount) \(Self.excerpts(entry.excerptCount))"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .lumenCard()
    }

    @ViewBuilder
    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Выделения", systemImage: "highlighter")
            if snapshot.highlights.isEmpty {
                Text("Выделите текст в книге: его можно покрасить или сразу отправить в заметки.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(snapshot.highlights) { highlight in
                Button {
                    LumenSounds.play(.navigate)
                    onRead(highlight.id)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Capsule()
                            .fill(Color(hex: highlight.color.hex))
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(highlight.text)
                                .font(.system(.callout, design: .serif))
                                .lineLimit(4)
                                .foregroundStyle(theme.textPrimary)
                            Text(highlight.label)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Открыть в книге")
            }
        }
        .lumenCard()
    }

    private func cardTitle(_ title: String, systemImage: String) -> some View {
        Label(title.uppercased(), systemImage: systemImage)
            .font(.caption.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(theme.textSecondary)
    }

    private func pageRow(icon: String, title: String, caption: String?) -> some View {
        HStack(spacing: 10) {
            Text(icon).frame(width: 26)
            Text(title)
                .lineLimit(1)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: Данные

    private func observe() async {
        let sourceId = sourceId
        let observation = ValueObservation.tracking { db in try SourceDashboardSnapshot.fetch(db, sourceId: sourceId) }
        do {
            for try await value in observation.values(in: database.reader) {
                snapshot = value
                hasLoaded = true
            }
        } catch {
            print("Dashboard observation failed: \(error)")
        }
    }

    private func openNotes() {
        Task {
            if let page = try? await database.notesPage(for: sourceId) {
                LumenSounds.play(.navigate)
                onOpenPage(page.id)
            }
        }
    }

    private func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    static func days(_ count: Int) -> String {
        plural(count, one: "день", few: "дня", many: "дней")
    }

    static func excerpts(_ count: Int) -> String {
        plural(count, one: "выписка", few: "выписки", many: "выписок")
    }

    /// Русское множественное число: 1 день, 3 дня, 5 дней, 21 день.
    static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        let tens = count % 100
        let units = count % 10
        if (11...14).contains(tens) { return many }
        if units == 1 { return one }
        if (2...4).contains(units) { return few }
        return many
    }
}
