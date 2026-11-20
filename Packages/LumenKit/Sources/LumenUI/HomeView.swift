import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// «Стол», главный экран. Сверху приветствие и поле для быстрой мысли, ниже заметка, которую
/// писали последней (лист на её обложке), рядом задачи на сегодня и книга, которую читаешь.
/// Ниже папки с «Входящими», полка с недавними книгами и недавние заметки.
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
    /// Широкое окно: заметка и задачи в ряд, поле для мысли справа от приветствия.
    @State private var isWide = true
    @Environment(\.appActions) private var appActions
    @Environment(\.lumenTheme) private var theme
    @Setting(ScreenOptions.homeReadingKey) private var showsReading = true
    @Setting(ScreenOptions.homeTasksKey) private var showsTasks = true
    @Setting(ScreenOptions.homeInboxKey) private var showsInbox = true
    @Setting(ScreenOptions.homeRecentKey) private var showsRecent = true

    private static let deskHeight: CGFloat = 370
    /// Ширина колонки «Стола». Полка берёт ту же, чтобы экраны были одного размера.
    static let contentMaxWidth: CGFloat = 1180

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                top
                SyncSetupCard()
                desk
                folders
                shelf
                if showsRecent, !snapshot.recent.isEmpty {
                    recent
                }
            }
            .padding(.horizontal, isWide ? 28 : 16)
            .padding(.vertical, 20)
            .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 760 } action: { isWide = $0 }
        }
        .keyHintClip()
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
        // Книга, вынутая с полки, встаёт посередине экрана.
        .bookShowcaseHost(database: database, onOpenBook: onOpenSource)
    }

    // MARK: - Приветствие

    private var top: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .bottom, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        return layout {
            header
            if isWide {
                Spacer(minLength: 16)
            }
            CaptureField(placeholder: "Записать мысль во «Входящие»…") { text, asTask in
                appActions.capture(text, asTask)
            }
            .frame(maxWidth: isWide ? 420 : .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textSecondary)
            Text(greeting)
                .font(.system(size: isWide ? 30 : 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.textPrimary)
            SyncBadge()
                .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        case 18..<23: "Добрый вечер"
        default: "Доброй ночи"
        }
    }

    // MARK: - На столе

    /// Заметка на обложке и колонка справа: задачи и книга. На узком экране друг под другом.
    private var desk: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 22))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        let hasSide = showsTasks || showsReading
        return layout {
            deskNote
                .frame(height: isWide ? Self.deskHeight : 320)
            if hasSide {
                VStack(spacing: 14) {
                    if showsTasks {
                        TodayTasksCard(database: database, onOpen: onOpen, onShowAll: {
                            appActions.open(.tasks)
                        }, limit: isWide && showsReading ? 4 : 5)
                    }
                    if showsReading {
                        readingCard
                    }
                }
                .frame(width: isWide ? 330 : nil)
                .frame(maxWidth: isWide ? nil : .infinity)
                .frame(height: isWide ? Self.deskHeight : nil)
            }
        }
    }

    @ViewBuilder
    private var deskNote: some View {
        if let note = snapshot.desk {
            DeskNoteCard(note: note, attachments: database.attachments, isCompact: !isWide) {
                onOpen(note.id)
            }
        } else {
            EmptyDeskCard(onNewNote: onNewNote)
        }
    }

    @ViewBuilder
    private var readingCard: some View {
        if let source = reading.current {
            ReadingNowCard(
                source: source,
                attachments: database.attachments,
                stats: reading.stats,
                onOpenBook: { onOpenSource(source.id) },
                onShowReading: { appActions.open(.reading) }
            )
        } else {
            Button(action: onShowLibrary) {
                HStack(spacing: 14) {
                    Image(systemName: "books.vertical")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                        .frame(width: 44, height: 64)
                        .background(theme.contrast.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Полка")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Text("Добавьте книгу и пишите заметки рядом")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .lumenCard()
            }
            .buttonStyle(.plain)
            .keyHint("Полка", perform: onShowLibrary)
        }
    }

    // MARK: - Папки

    @ViewBuilder
    private var folders: some View {
        if showsInbox || !snapshot.folders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Папки", link: "Вся библиотека ›", action: onShowLibrary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 14)], spacing: 14) {
                    if showsInbox {
                        inboxTile
                    }
                    ForEach(snapshot.folders) { item in
                        DeskFolderTile(
                            title: item.folder.displayName,
                            caption: Self.notesCaption(item.itemCount),
                            card: theme.folderCard(item.folder.color),
                            emoji: item.folder.icon,
                            systemImage: "folder"
                        ) {
                            appActions.open(.library(item.folder.id))
                        }
                    }
                    if snapshot.folders.count < HomeSnapshot.folderLimit {
                        newFolderTile
                    }
                }
            }
        }
    }

    private var inboxTile: some View {
        let count = snapshot.inboxCount
        return DeskFolderTile(
            title: "Входящие",
            caption: count == 0 ? "всё разобрано" : "\(count) \(ReadingText.plural(count, one: "новая", few: "новые", many: "новых"))",
            card: theme.folderCard(2),
            emoji: nil,
            systemImage: "tray"
        ) {
            onShowInbox()
        }
        .overlay(alignment: .topLeading) {
            if count > 0 {
                Button("Разобрать") { isTriaging = true }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 26)
                    .lumenGlass(Capsule())
                    .padding(10)
                    .help("Разобрать входящие по одной")
                    .keyHint("Разобрать по одной") { isTriaging = true }
                    .accessibilityIdentifier("home-triage")
            }
        }
    }

    private var newFolderTile: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            appActions.create(.folder)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                Text("Новая папка")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: DeskFolderTile.height)
            .overlay(shape.strokeBorder(theme.contrast.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .keyHint("Новая папка") { appActions.create(.folder) }
    }

    /// «12 заметок», «пусто».
    static func notesCaption(_ count: Int) -> String {
        count == 0 ? "пусто" : "\(count) \(ReadingText.plural(count, one: "заметка", few: "заметки", many: "заметок"))"
    }

    // MARK: - Полка и недавнее

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Полка", link: "Все книги ›", action: onShowLibrary)
            BookShelf(database: database, onOpen: onOpenSource, mode: .recent, showsLamp: true) {
                appActions.create(.book)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Недавние", link: "Вся библиотека ›", action: onShowLibrary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(snapshot.recent) { preview in
                    Button {
                        onOpen(preview.page.id)
                    } label: {
                        PagePreviewCard(preview: preview)
                    }
                    .buttonStyle(.plain)
                    .keyHint(preview.page.displayTitle) { onOpen(preview.page.id) }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, link: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button(link, action: action)
                .buttonStyle(.plain)
                .keyHint(link, perform: action)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.accent)
        }
    }

    /// «день», «дня», «дней» для числа.
    static func days(_ count: Int) -> String {
        ReadingText.days(count)
    }

    private func observePages() async {
        let observation = ValueObservation.tracking { db in try HomeSnapshot.fetch(db) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation(LumenMotion.standard) { snapshot = value }
            }
        } catch {
            lumenLog.error("Home observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func observeReading() async {
        let observation = ValueObservation.tracking { db in try HomeReadingSnapshot.fetch(db) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation(LumenMotion.standard) { reading = value }
            }
        } catch {
            lumenLog.error("Home reading observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Заметка на столе

/// Заметка, которую писали последней: её обложка, а на нижнем крае обложки лежит лист
/// с путём, названием и началом текста. Как открытая заметка, только меньше.
private struct DeskNoteCard: View {
    let note: DeskNote
    let attachments: AttachmentStore
    var isCompact: Bool
    var onOpen: () -> Void

    @Environment(\.lumenTheme) private var theme

    private var bandHeight: CGFloat { isCompact ? 170 : 230 }
    private var sheetTop: CGFloat { isCompact ? 104 : 150 }
    private var sheetInset: CGFloat { isCompact ? 14 : 40 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        Button(action: onOpen) {
            ZStack(alignment: .topLeading) {
                band
                    .frame(maxWidth: .infinity)
                    .frame(height: bandHeight)
                    .clipped()
                badge
                    .padding(.leading, 20)
                    .padding(.top, 16)
                sheet
                    .padding(.horizontal, sheetInset)
                    .padding(.top, sheetTop)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.contrast.opacity(0.04))
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.cardStroke, lineWidth: 1))
            .background {
                ShapeShadow(shape: shape, opacity: theme.shadowOpacity, radius: 26, y: 16)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .keyHint(note.page.displayTitle, perform: onOpen)
        .help("Открыть заметку")
        .accessibilityLabel("Продолжить писать: \(note.page.displayTitle)")
        .accessibilityIdentifier("home-desk-note")
    }

    /// Обложка заметки с её ракурсом. Без обложки: мягкий свет цвета темы.
    @ViewBuilder
    private var band: some View {
        if let cover = note.page.pageCover {
            PageCoverView(cover: cover, attachments: attachments, crop: note.page.pageCoverCrop, height: bandHeight)
        } else {
            LinearGradient(
                colors: [theme.glow.opacity(0.45), theme.glow2.opacity(0.25), theme.glow2.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var badge: some View {
        Text("Продолжить писать · \(Self.when(note.page.updatedAt))")
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .lumenGlass(Capsule())
    }

    private var sheet: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            Text(pathLine)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Text(note.page.displayTitle)
                .font(.system(size: isCompact ? 22 : 28, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: isCompact ? 15 : 16, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(theme.textPrimary.opacity(0.8))
                    .lineLimit(isCompact ? 3 : 4)
            }
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption)
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, isCompact ? 20 : 30)
        .padding(.top, isCompact ? 18 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // Лист непрозрачный: обложка лежит под ним и не просвечивает краем сквозь стекло.
            shape.fill(theme.menuFill)
                .overlay(shape.fill(theme.cardFill))
                .overlay(shape.fill(theme.contrast.opacity(0.035)))
                .overlay(shape.strokeBorder(theme.cardStroke, lineWidth: 1))
                .shadow(color: .black.opacity(theme.shadowOpacity * 0.8), radius: 20, y: -6)
        }
    }

    /// «Учёба / Статистика · 2 листа».
    private var pathLine: String {
        var parts = note.path.filter { $0 != .library }.map(\.title)
        if parts.isEmpty { parts = ["Библиотека"] }
        var line = parts.joined(separator: " / ")
        if note.sheetCount > 1 {
            line += " · \(note.sheetCount) \(ReadingText.plural(note.sheetCount, one: "лист", few: "листа", many: "листов"))"
        }
        return line
    }

    /// Начало текста без названия, если поиск хранит его первой строкой.
    private var excerpt: String {
        let text = note.preview.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = note.page.displayTitle
        guard text.hasPrefix(title) else { return text }
        return String(text.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chips: [String] {
        let count = note.excerptCount
        guard count > 0 else { return [] }
        return ["\(count) \(ReadingText.plural(count, one: "выдержка", few: "выдержки", many: "выдержек")) из книг"]
    }

    /// «08:12» сегодня, иначе «вчера», «3 дня назад».
    static func when(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute().locale(ReadingText.locale))
        }
        return date.lumenRelative
    }
}

/// Заметок ещё нет: место для первой.
private struct EmptyDeskCard: View {
    var onNewNote: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("На столе пока пусто")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Здесь будет лежать заметка, которую вы пишете: на своей обложке, с началом текста. Откроете её отсюда одним нажатием.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            Button("Новая заметка", action: onNewNote)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(theme.accent, in: Capsule())
                .keyHint("Новая заметка", perform: onNewNote)
                .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background {
            LinearGradient(
                colors: [theme.glow.opacity(0.3), theme.glow2.opacity(0.12), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
    }
}

// MARK: - Книга и папки

/// Книга, которую читаешь: обложка, сколько прочитано. Кольцо справа: минуты чтения сегодня
/// против цели, оно открывает экран «Чтение».
private struct ReadingNowCard: View {
    let source: Source
    let attachments: AttachmentStore
    let stats: ReadingStats
    var onOpenBook: () -> Void
    var onShowReading: () -> Void

    @Setting(ReadingGoal.key) private var goalMinutes = ReadingGoal.defaultMinutes
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenBook) {
                HStack(spacing: 14) {
                    SourceCoverArt(source: source, attachments: attachments, width: 44, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.lastOpenedAt == nil ? "С полки · начать" : "С полки · читаю")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Text(source.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            ReadingProgressBar(progress: source.progress)
                            Text(ReadingText.percent(source.progress))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyHint(source.displayTitle, perform: onOpenBook)
            .accessibilityIdentifier("home-continue")

            Button(action: onShowReading) {
                ReadingGoalRing(fraction: fraction, size: 42, lineWidth: 4) {
                    if goalMinutes > 0, fraction >= 1 {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                    } else {
                        Text("\(minutes)")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                    }
                }
                .foregroundStyle(theme.textPrimary)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyHint("Чтение", perform: onShowReading)
            .help(goalMinutes > 0 ? "Сегодня \(minutes) из \(goalMinutes) мин. Всё чтение" : "Сегодня \(minutes) мин. Всё чтение")
            .accessibilityLabel("Чтение сегодня: \(minutes) мин")
            .accessibilityIdentifier("home-reading")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lumenCard()
    }

    private var minutes: Int { Int(stats.todaySeconds / 60) }

    private var fraction: Double {
        let goal = Double(goalMinutes * 60)
        return goal > 0 ? stats.todaySeconds / goal : 0
    }
}

/// Папка на «Столе»: её цвет обложкой, внизу на обложке лежит стеклянный листок с названием.
private struct DeskFolderTile: View {
    static let height: CGFloat = 128

    let title: String
    let caption: String
    let card: Theme.VividCard
    /// Свой значок папки (эмодзи). Без него: системный значок.
    var emoji: String?
    var systemImage: String
    var action: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                emblem
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(14)
                label
            }
            .frame(height: Self.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.cardStroke, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .keyHint(title, perform: action)
        .accessibilityLabel("\(title), \(caption)")
    }

    @ViewBuilder
    private var emblem: some View {
        if let emoji {
            Text(emoji)
                .font(.system(size: 34))
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(card.foreground.opacity(0.45))
        }
    }

    private var label: some View {
        let sheet = UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            sheet.fill(theme.cardFill)
                .overlay(sheet.strokeBorder(theme.cardStroke, lineWidth: 1))
        }
        .padding(.horizontal, 12)
    }
}

/// «Задачи на сегодня»: то, что осталось на сегодня, с галочками прямо в карточке
/// и полем, чтобы добавить ещё одну. Отмеченные остаются зачёркнутыми, пока экран открыт.
private struct TodayTasksCard: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void
    var onShowAll: () -> Void
    /// Сколько задач видно. Рядом с заметкой на широком экране места меньше.
    var limit = 5

    @State private var snapshot = DataTableSnapshot.empty
    @State private var doneHere: [UUID] = []
    @State private var newTitle = ""
    @FocusState private var isAdding: Bool
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Задачи на сегодня")
                    .font(.headline)
                Spacer()
                Button(counter, action: onShowAll)
                    .buttonStyle(.plain)
                    .keyHint("Все задачи", perform: onShowAll)
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
            ForEach(rows.prefix(limit)) { row in
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
            .keyHint("Добавить задачу") { isAdding = true }
            .padding(.top, 4)
        }
        .foregroundStyle(theme.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
        .lumenCard()
        .task { await observe() }
    }

    private func taskRow(_ row: DataRow) -> some View {
        let done = isDone(row)
        return HStack(spacing: 10) {
            Button {
                toggle(row)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? theme.accent : theme.textSecondary)
                    .frame(minWidth: 30, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyHint(done ? "Вернуть в работу" : "Отметить выполненной") { toggle(row) }
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
            .keyHint(row.title.isEmpty ? "Без названия" : row.title) { onOpen(row.id) }
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
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation(LumenMotion.standard) { snapshot = value }
            }
        } catch {
            lumenLog.error("Today tasks observation failed: \(String(describing: error), privacy: .public)")
        }
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
