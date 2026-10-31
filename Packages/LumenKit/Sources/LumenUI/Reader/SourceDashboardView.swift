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
    /// Выделение, к которому пишут комментарий.
    @State private var editingNote: Highlight?
    @Environment(\.lumenTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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
                .padding(isCompact ? 16 : 24)
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
        #if os(iOS)
        // Полное название уже крупно в шапке, наверху хватит строки поменьше.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await observe() }
        .sheet(item: $editingNote) { highlight in
            HighlightNoteSheet(highlight: highlight) { note in
                Task {
                    await NoticeCenter.shared.attempt("Не удалось сохранить комментарий") {
                        try await database.setHighlightNote(highlight.id, note: note)
                    }
                }
            }
        }
    }

    // MARK: Шапка

    private func header(_ source: Source) -> some View {
        Group {
            if isCompact {
                // iPhone: обложка с названием сверху, кнопки во всю ширину под ними.
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 16) {
                        cover(source, width: 100, height: 140)
                        titleBlock(source, titleSize: 24)
                    }
                    HStack(spacing: 10) {
                        actionButtons(source)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 20) {
                    cover(source, width: 122, height: 170)
                    VStack(alignment: .leading, spacing: 8) {
                        titleBlock(source, titleSize: 30)
                        HStack(spacing: 10) {
                            actionButtons(source)
                        }
                        .fixedSize()
                        .padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func cover(_ source: Source, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            SourceCoverArt(source: source, attachments: database.attachments, width: width, height: height)
            ReadingProgressBar(progress: source.progress)
                .frame(width: width - 10)
                .opacity(source.progress > 0.005 ? 1 : 0)
        }
    }

    private func titleBlock(_ source: Source, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.format.label.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(theme.textSecondary)
            Text(source.displayTitle)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if let author = source.author, !author.isEmpty {
                Text(author)
                    .font(isCompact ? .subheadline : .title3)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(_ source: Source) -> some View {
        Button {
            LumenSounds.play(.navigate)
            onRead(nil)
        } label: {
            Label(source.progress > 0.005 ? "Продолжить" : "Читать", systemImage: "book")
        }
        .buttonStyle(DashboardPillButtonStyle(isProminent: true, fillsWidth: isCompact))
        Button {
            openNotes()
        } label: {
            Label(isCompact ? "Заметки" : "Заметки к книге", systemImage: "note.text")
        }
        .buttonStyle(DashboardPillButtonStyle(isProminent: false, fillsWidth: isCompact))
        .accessibilityLabel("Заметки к книге")
    }

    /// Узкий экран iPhone: шапка складывается в столбик.
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    // MARK: Числа

    private func statCards(_ source: Source) -> some View {
        let stats = stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            StatCard(
                title: "Прочитано",
                value: "\(Int((source.progress * 100).rounded()))%",
                caption: source.lastOpenedAt.map { "открывали \(relative($0))" },
                systemImage: "book",
                style: .vivid(1)
            )
            StatCard(
                title: "Время",
                value: ReadingStats.format(stats.totalSeconds, short: true),
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
                            if let note = highlight.note {
                                HighlightNoteLabel(note: note)
                            }
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
                .contextMenu {
                    Button {
                        editingNote = highlight
                    } label: {
                        Label(highlight.note == nil ? "Комментарий…" : "Изменить комментарий…", systemImage: "text.bubble")
                    }
                }
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
            lumenLog.error("Dashboard observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func openNotes() {
        Task {
            if let page = await NoticeCenter.shared.perform("Не удалось открыть заметки к книге", { try await database.notesPage(for: sourceId) }) {
                LumenSounds.play(.navigate)
                onOpenPage(page.id)
            }
        }
    }

    private func relative(_ date: Date) -> String {
        date.lumenRelative
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

/// Мягкая кнопка-пилюля в шапке книги: персиковая для «Продолжить», стеклянная для остальных.
/// Подпись всегда в одну строку.
private struct DashboardPillButtonStyle: ButtonStyle {
    var isProminent: Bool
    var fillsWidth: Bool
    @Environment(\.lumenTheme) private var theme

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(isProminent ? ReaderStyle.onPeach : theme.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background {
                if isProminent {
                    Capsule().fill(ReaderStyle.peachGradient)
                        .shadow(color: ReaderStyle.peachDeep.opacity(0.35), radius: 12, y: 6)
                } else {
                    Capsule().fill(.white.opacity(0.1))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
