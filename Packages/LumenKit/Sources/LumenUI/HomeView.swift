import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// «Сегодня», главный экран: поле для быстрой мысли и три карточки дня
/// (продолжить чтение, задачи на сегодня, разобрать входящие), ниже недавнее.
struct HomeView: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void
    /// Открыть книгу в читалке.
    var onOpenSource: (UUID) -> Void
    var onNewNote: () -> Void
    var onShowInbox: () -> Void
    /// Книг ещё нет: карточка чтения ведёт в библиотеку, где их добавляют.
    var onShowLibrary: () -> Void

    @State private var snapshot = HomeSnapshot.empty
    @State private var reading = HomeReadingSnapshot.empty
    @State private var isTriaging = false
    @Environment(\.appActions) private var appActions
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isZen {
                    zenHeader
                } else {
                    header
                }
                if isStudy {
                    // «Кабинет»: сверху полка с книгами, ниже то, что лежит на столе.
                    BookShelf(database: database, onOpen: onOpenSource) {
                        appActions.create(.book)
                    }
                    deskLabel
                }
                CaptureField { text, asTask in appActions.capture(text, asTask) }
                if isZen {
                    zenLines
                } else {
                    cards
                    if !snapshot.recent.isEmpty {
                        recent
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ThemedBackground())
        .navigationTitle("Сегодня")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isTriaging) {
            InboxTriageView(database: database, onOpen: { id in
                isTriaging = false
                onOpen(id)
            })
        }
        .task { await observePages() }
        .task { await observeReading() }
        // Книга, вынутая с полки «Кабинета», встаёт посередине экрана.
        .bookShowcaseHost(database: database, onOpenBook: onOpenSource)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textSecondary)
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.top, 8)
    }

    private var isStudy: Bool { theme.layout == .rooms }
    /// «Дзен»: вместо карточек тихие строки без рамок, только то, чем заняться сейчас.
    private var isZen: Bool { theme.layout == .orb }

    private var zenHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.zenMoment(.now))
                .font(.caption.weight(.medium))
                .tracking(2)
                .foregroundStyle(theme.textSecondary)
            Text("Что сейчас?")
                .font(.system(size: 40, weight: .light, design: .serif))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.top, 40)
    }

    private var zenLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let source = reading.current {
                zenLine("Продолжить: \(source.displayTitle)", detail: "\(Int((source.progress * 100).rounded()))%") {
                    onOpenSource(source.id)
                }
            } else {
                zenLine("Добавить книгу и читать рядом с заметками", action: onShowLibrary)
            }
            zenLine("Дела на сегодня") { appActions.open(.tasks) }
            if snapshot.inboxCount > 0 {
                zenLine(Self.waitingThoughts(snapshot.inboxCount), action: onShowInbox)
            }
            zenLine("Минута тишины перед чтением") { appActions.breathe() }
        }
        .padding(.top, 8)
        .frame(maxWidth: 620, alignment: .leading)
    }

    private func zenLine(_ title: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 12)
                Text("→")
                    .foregroundStyle(theme.accent)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.contrast.opacity(0.08)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// «СУББОТА · ВЕЧЕР».
    nonisolated static func zenMoment(_ date: Date, calendar: Calendar = .current) -> String {
        let weekday = date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "ru_RU")))
        let part: String
        switch calendar.component(.hour, from: date) {
        case 5..<12: part = "утро"
        case 12..<18: part = "день"
        case 18..<23: part = "вечер"
        default: part = "ночь"
        }
        return "\(weekday) · \(part)".uppercased()
    }

    /// «1 мысль ждёт во входящих», «3 мысли ждут во входящих».
    nonisolated static func waitingThoughts(_ count: Int) -> String {
        let verb = count % 10 == 1 && count % 100 != 11 ? "ждёт" : "ждут"
        return "\(count) \(thoughts(count)) \(verb) во входящих"
    }

    /// «мысль», «мысли», «мыслей».
    nonisolated static func thoughts(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if (11...14).contains(lastTwo) { return "мыслей" }
        switch last {
        case 1: return "мысль"
        case 2, 3, 4: return "мысли"
        default: return "мыслей"
        }
    }

    private var deskLabel: some View {
        Text("На столе")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(theme.accent.opacity(0.85))
            .padding(.bottom, -10)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        case 18..<23: "Добрый вечер"
        default: "Доброй ночи"
        }
    }

    /// Три главные карточки дня. На узком экране встают друг под другом.
    private var cards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)], spacing: 16) {
            if let source = reading.current {
                Button {
                    onOpenSource(source.id)
                } label: {
                    ContinueReadingCard(source: source, attachments: database.attachments, caption: readingCaption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-continue")
            } else {
                Button(action: onShowLibrary) {
                    ActionCard(
                        title: "Заметки по книге",
                        subtitle: "Добавьте книгу или файл в библиотеку и пишите заметки рядом",
                        systemImage: "book.pages",
                        style: .vivid(0)
                    )
                }
                .buttonStyle(.plain)
            }

            TodayTasksCard(database: database, onOpen: onOpen) {
                appActions.open(.tasks)
            }

            InboxCard(count: snapshot.inboxCount, onOpen: onShowInbox, onTriage: { isTriaging = true }, onNewNote: onNewNote)
        }
    }

    private var readingCaption: String {
        let today = reading.stats.todaySeconds
        let streak = reading.stats.streakDays
        var parts: [String] = []
        if today > 0 { parts.append("сегодня \(ReadingStats.format(today, short: true))") }
        if streak > 1 { parts.append("\(streak) \(Self.days(streak)) подряд") }
        return parts.joined(separator: " · ")
    }

    /// «день», «дня», «дней» для числа.
    static func days(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if (11...14).contains(lastTwo) { return "дней" }
        switch last {
        case 1: return "день"
        case 2, 3, 4: return "дня"
        default: return "дней"
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Недавние")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button("Вся библиотека ›", action: onShowLibrary)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accent)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(snapshot.recent) { preview in
                    Button {
                        onOpen(preview.page.id)
                    } label: {
                        PagePreviewCard(preview: preview)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func observePages() async {
        let observation = ValueObservation.tracking { db in try HomeSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation { snapshot = value }
            }
        } catch {
            lumenLog.error("Home observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func observeReading() async {
        let observation = ValueObservation.tracking { db in try HomeReadingSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation { reading = value }
            }
        } catch {
            lumenLog.error("Home reading observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// «Задачи на сегодня»: то, что осталось на сегодня, с галочками прямо в карточке
/// и полем, чтобы добавить ещё одну. Отмеченные остаются зачёркнутыми, пока экран открыт.
private struct TodayTasksCard: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void
    var onShowAll: () -> Void

    @State private var snapshot = DataTableSnapshot.empty
    @State private var doneHere: [UUID] = []
    @State private var newTitle = ""
    @FocusState private var isAdding: Bool
    @Environment(\.lumenTheme) private var theme

    private static let limit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Задачи на сегодня")
                    .font(.headline)
                Spacer()
                Button(counter, action: onShowAll)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                    .help("Открыть все задачи")
            }
            if rows.isEmpty {
                Text("На сегодня ничего. Добавьте первую задачу.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, 6)
            }
            ForEach(rows.prefix(Self.limit)) { row in
                taskRow(row)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.textSecondary)
                TextField("Добавить задачу", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($isAdding)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityIdentifier("home-add-task")
            }
            .padding(.top, 4)
        }
        .foregroundStyle(theme.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .lumenCard()
        .task { await observe() }
    }

    private func taskRow(_ row: DataRow) -> some View {
        let done = isDone(row)
        return HStack(spacing: 10) {
            Button {
                toggle(row)
            } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(done ? theme.accent : theme.textSecondary)
                    .frame(minWidth: 30, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Вернуть в работу" : "Отметить выполненной")
            Button {
                onOpen(row.id)
            } label: {
                Text(row.title.isEmpty ? "Без названия" : row.title)
                    .font(.subheadline)
                    .strikethrough(done)
                    .foregroundStyle(done ? theme.textSecondary : theme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let due = dueLabel(row) {
                Text(due)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(theme.accent.opacity(0.2), in: Capsule())
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private var counter: String {
        let all = rows
        let done = all.filter(isDone).count
        return all.isEmpty ? "Все задачи ›" : "\(done) из \(all.count) ›"
    }

    /// Задачи представления «Сегодня» и отмеченные здесь, чтобы они не исчезали сразу после галочки.
    private var rows: [DataRow] {
        guard let table = snapshot.table, let view = todayView(table) else { return [] }
        let today = DataQuery.rows(snapshot.rows, in: table, view: view)
        let todayIds = Set(today.map(\.id))
        let done = doneHere.compactMap { id in snapshot.rows.first { $0.id == id } }.filter { !todayIds.contains($0.id) }
        return today + done
    }

    private func todayView(_ table: DataTable) -> DataView? {
        table.views.first { $0.name == "Сегодня" } ?? table.views.first
    }

    private func statusProperty(_ table: DataTable) -> PropertyDefinition? {
        table.firstProperty(of: [.status])
    }

    private func isDone(_ row: DataRow) -> Bool {
        guard let table = snapshot.table, let status = statusProperty(table) else { return false }
        return status.option(row.value(status.id)?.optionIds.first)?.isDone == true
    }

    /// Срок задачи, если он не сегодня: «вчера», «2 нояб.».
    private func dueLabel(_ row: DataRow) -> String? {
        guard let table = snapshot.table, let view = todayView(table),
              let due = row.value(view.dateProperty ?? UUID())?.dayDate else { return nil }
        let today = DayDate.today()
        if due == today { return nil }
        if due == today.adding(days: -1) { return "вчера" }
        return due < today ? "просрочено" : nil
    }

    private func toggle(_ row: DataRow) {
        guard let table = snapshot.table, let status = statusProperty(table) else { return }
        let wasDone = isDone(row)
        let target = wasDone
            ? status.options.first { !$0.isDone }
            : status.options.first { $0.isDone }
        guard let target else { return }
        LumenSounds.play(wasDone ? .tap : .toggle)
        if !wasDone, !doneHere.contains(row.id) { doneHere.append(row.id) }
        let database = database
        Task {
            await NoticeCenter.shared.attempt("Не удалось отметить задачу") {
                try await database.setValue(.option(target.id), property: status.id, row: row.id)
            }
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTitle = ""
        isAdding = true
        let database = database
        Task {
            if await NoticeCenter.shared.attempt("Не удалось добавить задачу", {
                _ = try await Creator.addTodayTask(title: title, in: database)
            }) {
                LumenSounds.play(.create)
            }
        }
    }

    private func observe() async {
        guard let table = try? await database.tasksDataTable() else { return }
        let pageId = table.pageId
        let observation = ValueObservation.tracking { db in try DataTableSnapshot.fetch(db, pageId: pageId) }
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation(.snappy) { snapshot = value }
            }
        } catch {
            lumenLog.error("Today tasks observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// «Входящие»: сколько ждут разбора и кнопка разобрать их по одной.
private struct InboxCard: View {
    let count: Int
    var onOpen: () -> Void
    var onTriage: () -> Void
    var onNewNote: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Входящие")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .opacity(0.75)
            Text("\(count)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .contentTransition(.numericText())
            Text(count == 0 ? "всё разобрано" : "\(Self.notes(count)) ждут разбора")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if count > 0 {
                    Button("Разобрать по одной", action: onTriage)
                        .buttonStyle(DarkPillButtonStyle(foreground: theme.vividCard(2).colors.first ?? .white))
                        .accessibilityIdentifier("home-triage")
                } else {
                    Button("Записать мысль", action: onNewNote)
                        .buttonStyle(DarkPillButtonStyle(foreground: theme.vividCard(2).colors.first ?? .white))
                }
                Button("Открыть", action: onOpen)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .lumenCard(.vivid(2))
    }

    /// «заметка», «заметки», «заметок».
    static func notes(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if (11...14).contains(lastTwo) { return "заметок" }
        switch last {
        case 1: return "заметка"
        case 2, 3, 4: return "заметки"
        default: return "заметок"
        }
    }
}

/// Тёмная кнопка-таблетка на яркой карточке: «Читать дальше», «Разобрать по одной».
struct DarkPillButtonStyle: ButtonStyle {
    var foreground: Color = .white

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(Color.black.opacity(configuration.isPressed ? 0.55 : 0.72), in: Capsule())
            .contentShape(Capsule())
    }
}

/// «Продолжить чтение»: обложка последней книги, сколько прочитано, нажатие открывает её на том же месте.
private struct ContinueReadingCard: View {
    let source: Source
    let attachments: AttachmentStore
    var caption: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SourceCoverArt(source: source, attachments: attachments, width: 82, height: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text(source.lastOpenedAt == nil ? "Начать читать" : "Продолжить")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .opacity(0.75)
                Text(source.displayTitle)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    ReadingProgressBar(progress: source.progress)
                    Text("\(Int((source.progress * 100).rounded()))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .opacity(0.75)
                }
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer(minLength: 8)
                Text("Читать дальше")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .lumenCard(.vivid(0))
    }
}

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let style: CardStyle

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .lumenCard(style)
    }
}

/// Карточка страницы с началом текста.
struct PagePreviewCard: View {
    let preview: PagePreview
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageLabel(page: preview.page)
                .font(.headline)
            Text(preview.excerpt.isEmpty ? "Пустая заметка" : preview.excerpt)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            Text(preview.page.updatedAt.lumenRelative)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .lumenCard()
    }
}
