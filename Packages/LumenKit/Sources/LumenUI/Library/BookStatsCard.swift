import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Окно над книгой, взятой с полки «Кабинета»: сколько прочитано, сколько времени
/// с ней провели, когда открывали последний раз, выделения и заметки, где есть выписки.
struct BookStatsCard: View {
    let database: AppDatabase
    let sourceId: UUID
    var onOpenBook: () -> Void
    var onOpenPage: (UUID) -> Void
    var onOpenDashboard: () -> Void
    /// Полупрозрачная панель рядом с крупной обложкой, а не отдельное окошко.
    var isPanel = false
    /// «Сменить обложку» под кнопками: в окне книги, вынутой с полки.
    var showsCoverButton = false

    @State private var snapshot = SourceDashboardSnapshot.empty
    @Environment(\.lumenTheme) private var theme

    private var stats: ReadingStats { ReadingStats(sessions: snapshot.sessions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let source = snapshot.source {
                header(source)
                divider
                facts(source)
                divider
                notes
                buttons
                if showsCoverButton {
                    BookCoverButton(book: source)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(isPanel ? 22 : 16)
        .frame(width: isPanel ? 340 : 310, alignment: .leading)
        .background {
            if isPanel {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill((theme.backgroundStops.first ?? .clear).opacity(0.55)))
                    .overlay(shape.strokeBorder(theme.contrast.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            } else {
                theme.backgroundStops.first ?? .clear
            }
        }
        .environment(\.colorScheme, theme.colorScheme)
        .task { await observe() }
        .accessibilityIdentifier("bookStatsCard")
    }

    private func header(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.displayTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
            if let author = source.author, !author.isEmpty {
                Text(author)
                    .font(.callout.italic())
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                ReadingProgressBar(progress: source.progress)
                Text("\(Int((source.progress * 100).rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.accent)
            }
            .padding(.top, 2)
        }
    }

    private func facts(_ source: Source) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                fact("Время чтения", ReadingStats.format(stats.totalSeconds))
                fact("Сегодня", ReadingStats.format(stats.todaySeconds))
            }
            GridRow {
                fact("Последний раз", BookStatsText.lastRead(source.lastOpenedAt))
                fact("Дней с книгой", "\(stats.daysRead)")
            }
            GridRow {
                fact("Выделений", "\(snapshot.highlights.count)")
                fact("Добавлена", source.createdAt.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(theme.accent.opacity(0.85))
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
        }
    }

    /// Заметки к книге и страницы с выписками из неё. Нажатие открывает страницу.
    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Заметки")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(theme.accent.opacity(0.85))
            if snapshot.notesPage == nil, snapshot.excerptPages.isEmpty {
                Text("Пока нет. Выделите текст в книге и нажмите «В заметки».")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let page = snapshot.notesPage {
                noteRow(page, detail: "заметки к книге", systemImage: "note.text")
            }
            ForEach(snapshot.excerptPages.prefix(3)) { item in
                noteRow(item.page, detail: BookStatsText.excerpts(item.excerptCount), systemImage: "quote.opening")
            }
            if snapshot.excerptPages.count > 3 {
                Text("и ещё \(snapshot.excerptPages.count - 3)")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func noteRow(_ page: Page, detail: String, systemImage: String) -> some View {
        Button {
            onOpenPage(page.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.accent)
                    .frame(width: 18)
                Text(page.displayTitle)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            .font(.callout)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(theme.contrast.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyHint(page.displayTitle) { onOpenPage(page.id) }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: onOpenBook) {
                Text(snapshot.source?.lastOpenedAt == nil ? "Начать читать" : "Читать дальше")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .keyHint("Читать", perform: onOpenBook)
            Button(action: onOpenDashboard) {
                Text("О книге")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.accent.opacity(0.6)))
            }
            .keyHint("О книге", perform: onOpenDashboard)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.accent.opacity(0.3))
            .frame(height: 1)
    }

    private func observe() async {
        let id = sourceId
        let observation = ValueObservation.tracking { db in try SourceDashboardSnapshot.fetch(db, sourceId: id) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) {
                snapshot = value
            }
        } catch {
            lumenLog.error("Book stats observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Подписи окна статистики.
enum BookStatsText {
    /// «сегодня, 22:10», «вчера, 09:05», «5 ноября», «ещё не открывали».
    static func lastRead(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "ещё не открывали" }
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "ru_RU")))
        if calendar.isDate(date, inSameDayAs: now) { return "сегодня, \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "вчера, \(time)"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style: Date.FormatStyle = sameYear
            ? .dateTime.day().month(.wide)
            : .dateTime.day().month(.wide).year()
        return date.formatted(style.locale(Locale(identifier: "ru_RU")))
    }

    /// «1 выписка», «3 выписки», «12 выписок».
    static func excerpts(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        let word: String
        if (11...14).contains(lastTwo) {
            word = "выписок"
        } else {
            switch last {
            case 1: word = "выписка"
            case 2, 3, 4: word = "выписки"
            default: word = "выписок"
            }
        }
        return "\(count) \(word)"
    }
}
