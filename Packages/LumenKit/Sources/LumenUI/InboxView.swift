import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// «Входящие»: быстрые заметки, которые ещё не разложены по разделам.
/// Свайп влево удаляет заметку, вправо раскладывает по папке. То же есть в меню по правой кнопке.
struct InboxView: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void
    var onNewNote: () -> Void

    @State private var notes: [PagePreview] = []
    /// Заметка, для которой открыто окно «Разложить по папке».
    @State private var filing: PagePreview?
    @State private var isTriaging = false

    var body: some View {
        List {
            ForEach(notes) { note in
                Button {
                    onOpen(note.page.id)
                } label: {
                    PagePreviewCard(preview: note)
                }
                .buttonStyle(.plain)
                .keyHint(note.page.displayTitle, secondary: { filing = note }) { onOpen(note.page.id) }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .contextMenu { menu(for: note) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        trash(note)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        filing = note
                    } label: {
                        Label("В папку", systemImage: "folder")
                    }
                    .tint(.indigo)
                }
            }
        }
        .keyHintClip()
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView {
                    Label("Во входящих пусто", systemImage: "tray")
                } description: {
                    Text(Self.emptyHint)
                } actions: {
                    Button("Новая заметка", action: onNewNote)
                        .buttonStyle(.borderedProminent)
                        .keyHint("Новая заметка", perform: onNewNote)
                }
            }
        }
        .background(ThemedBackground())
        .navigationTitle("Входящие")
        .toolbar {
            if !notes.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isTriaging = true
                    } label: {
                        Label("Разобрать по одной", systemImage: "rectangle.stack")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Показывать заметки по одной и решать, куда каждую")
                }
            }
        }
        .sheet(isPresented: $isTriaging) {
            InboxTriageView(database: database) { id in
                isTriaging = false
                onOpen(id)
            }
        }
        .sheet(item: $filing) { note in
            MoveToFolderSheet(database: database, item: .page(note.page.id), currentFolderId: nil, isFromInbox: true) {
                filing = nil
            }
        }
        .task { await observe() }
    }

    #if os(macOS)
    private static let emptyHint = "Сюда попадают быстрые заметки. Нажмите ⌘N или кнопку ниже."
    #else
    private static let emptyHint = "Сюда попадают быстрые заметки. Нажмите кнопку ниже, чтобы записать мысль."
    #endif

    @ViewBuilder
    private func menu(for note: PagePreview) -> some View {
        Button {
            filing = note
        } label: {
            Label("Разложить по папке…", systemImage: "folder")
        }
        Button {
            Task {
                await NoticeCenter.shared.attempt("Не удалось перенести заметку") {
                    try await database.movePage(note.page.id, toFolder: nil)
                }
            }
        } label: {
            Label("В библиотеку", systemImage: "books.vertical")
        }
        Divider()
        Button(role: .destructive) {
            trash(note)
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }

    private func trash(_ note: PagePreview) {
        NoticeCenter.shared.moveToTrash(.page(note.page.id), in: database)
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try InboxQuery.fetch(db) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation(LumenMotion.standard) { notes = value }
            }
        } catch {
            lumenLog.error("Inbox observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Разбор «Входящих» по одной заметке: карточка, три подходящие папки и кнопки
/// «В задачи», «Оставить», «Удалить». Свайп влево удаляет, вправо кладёт в первую папку.
struct InboxTriageView: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void

    @State private var notes: [PagePreview] = []
    @State private var folders: [Folder] = []
    /// Заметки, которые решили оставить во «Входящих»: в этом разборе их больше не показываем.
    @State private var skipped: Set<UUID> = []
    /// Сколько заметок было в начале и сколько уже разобрано: для «1 из 3».
    @State private var total = 0
    @State private var handled = 0
    @State private var isLoaded = false
    @State private var drag: CGSize = .zero
    @State private var choosingFolderFor: PagePreview?
    /// Последний шаг разбора: его можно отменить кнопкой «Вернуть» или ⌘Z.
    @State private var lastStep: TriageStep?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lumenTheme) private var theme

    private static let swipeDistance: CGFloat = 120

    private var current: PagePreview? {
        notes.first { !skipped.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let note = current {
                    triage(note)
                } else if isLoaded {
                    ContentUnavailableView {
                        Label("Всё разобрано", systemImage: "checkmark.circle")
                    } description: {
                        Text(handled > 0 ? "Разобрано заметок: \(handled)." : "Во «Входящих» пусто.")
                    } actions: {
                        Button("Готово") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .keyHint("Готово") { dismiss() }
                        if lastStep != nil {
                            undoButton
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ThemedBackground())
            .navigationTitle("Разбор входящих")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
        .keyHintHost()
        .sheet(item: $choosingFolderFor) { note in
            MoveToFolderSheet(database: database, item: .page(note.page.id), currentFolderId: nil, isFromInbox: true) {
                choosingFolderFor = nil
                handled += 1
            }
        }
        .task { await observe() }
        .task { await loadFolders() }
    }

    private func triage(_ note: PagePreview) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            progress
            card(note)
            folderChoices(note)
            Spacer(minLength: 0)
            actions(note)
        }
        .padding(20)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var progress: some View {
        let position = min(handled + 1, max(total, 1))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(position) из \(max(total, position))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                if lastStep != nil {
                    undoButton
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<max(total, position), id: \.self) { index in
                    Capsule()
                        .fill(index < position ? theme.vividCard(2).colors.first ?? theme.accent : theme.textPrimary.opacity(0.16))
                        .frame(height: 5)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func card(_ note: PagePreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.page.createdAt.lumenRelative)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            Text(note.page.displayTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.textPrimary)
            if !note.excerpt.isEmpty {
                Text(note.excerpt)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary.opacity(0.85))
                    .lineLimit(8)
            }
            Spacer(minLength: 16)
            HStack {
                Text("← удалить")
                Spacer()
                Button("Открыть заметку") { onOpen(note.page.id) }
                    .buttonStyle(.plain)
                    .keyHint("Открыть заметку") { onOpen(note.page.id) }
                    .foregroundStyle(theme.accent)
                Spacer()
                Text(folders.first.map { "в «\($0.displayName)» →" } ?? "оставить →")
            }
            .font(.caption)
            .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .lumenCard(padding: 22)
        .rotationEffect(.degrees(Double(drag.width) / 25))
        .offset(x: drag.width, y: drag.height * 0.2)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    let width = value.translation.width
                    withAnimation(LumenMotion.standard) { drag = .zero }
                    if width < -Self.swipeDistance {
                        delete(note)
                    } else if width > Self.swipeDistance {
                        if let folder = folders.first { file(note, into: folder) } else { keep(note) }
                    }
                }
        )
        .id(note.id)
        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
    }

    /// «Вернуть»: отменяет последний шаг, заметка снова первая в стопке.
    private var undoButton: some View {
        Button(action: undoLastStep) {
            Label("Вернуть", systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(theme.textPrimary.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textPrimary)
        .keyboardShortcut("z", modifiers: .command)
        .keyHint("Вернуть", perform: undoLastStep)
        .help("Отменить последний шаг (⌘Z)")
        .accessibilityIdentifier("triage-undo")
    }

    private func folderChoices(_ note: PagePreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Положить в папку")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            FlowChips(spacing: 8) {
                ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                    Button {
                        file(note, into: folder)
                    } label: {
                        Label {
                            Text(folder.displayName)
                        } icon: {
                            FolderGlyph(color: folder.color, icon: folder.icon)
                        }
                        .font(.callout.weight(index == 0 ? .bold : .semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(theme.textPrimary.opacity(index == 0 ? 0.16 : 0.08), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textPrimary)
                    .keyHint(folder.displayName) { file(note, into: folder) }
                }
                Button {
                    choosingFolderFor = note
                } label: {
                    Text("Другая…")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .overlay(Capsule().strokeBorder(theme.textPrimary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .keyHint("Другая папка") { choosingFolderFor = note }
            }
        }
    }

    private func actions(_ note: PagePreview) -> some View {
        HStack(spacing: 10) {
            triageButton("В задачи", systemImage: "checkmark.square", tint: theme.vividCard(3).colors.last ?? .green) { toTask(note) }
            triageButton("Оставить", systemImage: "clock", tint: theme.textSecondary) { keep(note) }
            triageButton("Удалить", systemImage: "trash", tint: .red) { delete(note) }
        }
    }

    private func triageButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyHint(title, perform: action)
    }

    // MARK: Действия

    private func file(_ note: PagePreview, into folder: Folder) {
        LumenSounds.play(.dropIntoFolder)
        handled += 1
        lastStep = .filed(note.page.id)
        let database = database
        Task {
            await NoticeCenter.shared.attempt("Не удалось переложить заметку") {
                try await database.movePage(note.page.id, toFolder: folder.id)
            }
        }
    }

    private func keep(_ note: PagePreview) {
        LumenSounds.play(.tap)
        handled += 1
        lastStep = .kept(note.page.id)
        withAnimation(LumenMotion.standard) { _ = skipped.insert(note.id) }
    }

    private func delete(_ note: PagePreview) {
        handled += 1
        lastStep = .deleted(note.page.id)
        NoticeCenter.shared.moveToTrash(.page(note.page.id), in: database)
    }

    /// Отменяет последний шаг. Отменить можно один шаг, как в «Почте».
    private func undoLastStep() {
        guard let step = lastStep else { return }
        lastStep = nil
        handled = max(0, handled - 1)
        LumenSounds.play(.restore)
        let database = database
        switch step {
        case .kept(let id):
            withAnimation(LumenMotion.standard) { _ = skipped.remove(id) }
        case .filed(let id):
            Task {
                await NoticeCenter.shared.attempt("Не удалось вернуть заметку") {
                    try await database.returnToInbox(id)
                }
            }
        case .deleted(let id):
            Task {
                await NoticeCenter.shared.attempt("Не удалось вернуть заметку") {
                    try await database.restorePage(id)
                }
            }
        case .madeTask(let noteId, let rowId, let noteTrashed):
            Task {
                await NoticeCenter.shared.attempt("Не удалось вернуть заметку") {
                    if let rowId { try await database.trashPage(rowId) }
                    if noteTrashed {
                        try await database.restorePage(noteId)
                    } else {
                        try await database.returnToInbox(noteId)
                    }
                }
            }
        }
    }

    /// Задача на сегодня с названием заметки. Если в заметке есть текст, она остаётся
    /// в библиотеке и привязана к задаче как материал, а пустая заметка больше не нужна.
    private func toTask(_ note: PagePreview) {
        LumenSounds.play(.create)
        handled += 1
        let database = database
        let title = note.page.displayTitle
        let hasBody = !note.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        lastStep = .madeTask(note: note.page.id, row: nil, noteTrashed: !hasBody)
        Task {
            let done = await NoticeCenter.shared.attempt("Не удалось сделать задачу") {
                let row = try await Creator.addTodayTask(title: title, in: database)
                // Задача уже есть: отмена уберёт и её.
                if case .madeTask(let noteId, let existing, let trashed) = lastStep, existing == nil, noteId == note.page.id {
                    lastStep = .madeTask(note: noteId, row: row.id, noteTrashed: trashed)
                }
                if hasBody {
                    let table = try await database.tasksDataTable()
                    if let material = table.firstProperty(of: [.page]) {
                        try await database.setValue(.page(note.page.id), property: material.id, row: row.id)
                    }
                    try await database.movePage(note.page.id, toFolder: nil)
                } else {
                    try await database.trashPage(note.page.id)
                }
            }
            if done { NoticeCenter.shared.show("Задача на сегодня добавлена") }
        }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try InboxQuery.fetch(db) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) {
                if !isLoaded { total = value.count }
                withAnimation(LumenMotion.standard) { notes = value }
                isLoaded = true
            }
        } catch {
            lumenLog.error("Triage observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadFolders() async {
        folders = (try? await database.reader.read { db in try SuggestedFoldersQuery.fetch(db) }) ?? []
    }
}

/// Шаг разбора «Входящих», который можно отменить.
private enum TriageStep {
    case filed(UUID)
    case kept(UUID)
    case deleted(UUID)
    /// Заметка стала задачей. `row` появится, когда задача запишется в базу.
    /// Пустая заметка при этом уходит в корзину (`noteTrashed`).
    case madeTask(note: UUID, row: UUID?, noteTrashed: Bool)
}

/// Корзина: восстановить папку, страницу или книгу, удалить одну вещь или всё навсегда.
/// Что лежит здесь дольше 30 дней, удаляется само.
struct TrashView: View {
    let database: AppDatabase

    @State private var trash = TrashSnapshot.empty
    @State private var isConfirmingEmpty = false
    @Environment(\.isActivePane) private var isActivePane
    /// Вещь, которую собираются удалить навсегда: сначала спрашиваем.
    @State private var deleting: TrashEntry?
    @Environment(\.lumenTheme) private var theme

    /// Строка корзины: что это, как называется и когда удалено.
    private struct TrashEntry: Identifiable {
        var item: LibraryItemID
        var title: String
        var deletedAt: Date?

        var id: LibraryItemID { item }
    }

    var body: some View {
        List {
            if !trash.isEmpty {
                Text("Удалённое хранится \(AppDatabase.trashRetentionDays) дней, потом исчезает само.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(trash.folders) { folder in
                row(TrashEntry(item: .folder(folder.id), title: folder.displayName, deletedAt: folder.deletedAt)) {
                    FolderLabel(folder: folder)
                }
            }
            ForEach(trash.sources) { source in
                row(TrashEntry(item: .source(source.id), title: source.displayTitle, deletedAt: source.deletedAt)) {
                    Label(source.displayTitle, systemImage: source.format.symbolName)
                }
            }
            ForEach(trash.pages) { page in
                row(TrashEntry(item: .page(page.id), title: page.displayTitle, deletedAt: page.deletedAt)) {
                    PageLabel(page: page)
                }
            }
        }
        .keyHintClip()
        .scrollContentBackground(.hidden)
        .overlay {
            if trash.isEmpty {
                ContentUnavailableView("Корзина пуста", systemImage: "trash")
            }
        }
        .background(ThemedBackground())
        .navigationTitle("Корзина")
        .toolbar {
            if isActivePane {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Очистить", role: .destructive) { isConfirmingEmpty = true }
                        .disabled(trash.isEmpty)
                }
            }
        }
        .confirmationDialog("Удалить всё из корзины навсегда?", isPresented: $isConfirmingEmpty) {
            Button("Удалить навсегда", role: .destructive) {
                Task {
                    await NoticeCenter.shared.attempt("Не удалось очистить корзину") {
                        try await database.emptyTrash()
                    }
                }
            }
        }
        .confirmationDialog(
            deleting.map { "Удалить «\($0.title)» навсегда?" } ?? "",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить навсегда", role: .destructive) {
                guard let entry = deleting else { return }
                deleting = nil
                Task {
                    await NoticeCenter.shared.attempt("Не удалось удалить") {
                        try await database.deleteForever(entry.item)
                    }
                }
            }
        } message: {
            Text("Вернуть будет нельзя.")
        }
        .task { await observe() }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func row<Title: View>(_ entry: TrashEntry, @ViewBuilder title: () -> Title) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                title()
                if let deletedAt = entry.deletedAt {
                    Text("Удалено \(deletedAt.lumenRelative)")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
            Button("Восстановить") { restore(entry.item) }
                .buttonStyle(.bordered)
                .keyHint("Восстановить «\(entry.title)»") { restore(entry.item) }
            Button {
                deleting = entry
            } label: {
                Image(systemName: "trash.slash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.textSecondary)
            .help("Удалить навсегда")
            .keyHint("Удалить навсегда") { deleting = entry }
        }
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("Восстановить") { restore(entry.item) }
            Button("Удалить навсегда…", role: .destructive) { deleting = entry }
        }
        .swipeActions {
            Button(role: .destructive) {
                deleting = entry
            } label: {
                Label("Удалить навсегда", systemImage: "trash.slash")
            }
        }
    }

    private func restore(_ item: LibraryItemID) {
        Task {
            let restored = await NoticeCenter.shared.attempt("Не удалось восстановить") {
                switch item {
                case .folder(let id): try await database.restoreFolder(id)
                case .page(let id): try await database.restorePage(id)
                case .source(let id): try await database.restoreSource(id)
                }
            }
            if restored { LumenSounds.play(.restore) }
        }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try TrashSnapshot.fetch(db) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) where value != trash {
                // Восстановленное и удалённое навсегда уходит из списка плавно.
                withAnimation(LumenMotion.standard) { trash = value }
            }
        } catch {
            lumenLog.error("Trash observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}
