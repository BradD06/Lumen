import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Действие в ⌘K: «Новая задача», «Перейти во Входящие», «Настройки».
struct PaletteCommand: Identifiable {
    var id: String
    var title: String
    var systemImage: String
    var shortcut: String?
    /// Слова, по которым действие находится, кроме названия.
    var keywords: [String] = []
    /// Значок в цветной плитке, как в меню «Создать».
    var createKind: CreateKind?
    var run: @MainActor () -> Void

    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(separator: " ")
        let haystack = ([title] + keywords).joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// ⌘K: поиск по страницам, книгам и цитатам и быстрые действия в одном окне.
/// Пока ничего не набрано, показывает недавнее и главные действия. Стрелки выбирают строку,
/// Return открывает, ⌘Return открывает рядом. «>» в начале оставляет только действия.
struct CommandPalette: View {
    let database: AppDatabase
    let commands: [PaletteCommand]
    var onOpen: (_ item: SidebarItem, _ beside: Bool) -> Void
    var onDismiss: () -> Void

    @State private var query = ""
    @State private var results = LibrarySearchResults.empty
    @State private var recent: [RecentItem] = []
    @State private var selected = 0
    @FocusState private var isFieldFocused: Bool
    @Environment(\.lumenTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// iPhone: окно на весь экран, без подсказок клавиш, которых там нет.
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// Строка списка: что-то открыть или что-то сделать.
    private struct Row: Identifiable {
        enum Kind {
            case open(SidebarItem)
            case command(PaletteCommand)
        }

        var id: String
        var section: String
        var title: String
        var detail: String
        var systemImage: String
        var kind: Kind
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            list
            if !isCompact {
                Divider()
                footer
            }
        }
        .frame(width: isCompact ? nil : 640)
        .frame(minHeight: 300, idealHeight: 460, maxHeight: isCompact ? .infinity : 560)
        .background(ThemedBackground())
        .task { await loadRecent() }
        .task(id: query) { await runSearch() }
        .onChange(of: query) { _, _ in selected = 0 }
        .onAppear { isFieldFocused = true }
    }

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.glow)
                .accessibilityHidden(true)
            TextField("Найдите страницу, книгу или действие", text: $query)
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .focused($isFieldFocused)
                .onSubmit { activate(selected, beside: false) }
                .onKeyPress(.upArrow) {
                    move(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    move(1)
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    activate(selected, beside: true)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
                .accessibilityIdentifier("palette-field")
            Button("Закрыть", action: onDismiss)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var list: some View {
        let rows = self.rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index == 0 || rows[index - 1].section != row.section {
                            Text(row.section)
                                .font(.caption.weight(.bold))
                                .textCase(.uppercase)
                                .foregroundStyle(theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.top, index == 0 ? 4 : 12)
                                .padding(.bottom, 4)
                        }
                        Button {
                            activate(index, beside: false)
                        } label: {
                            rowView(row, isSelected: index == selected)
                        }
                        .buttonStyle(MenuRowButtonStyle(isSelected: index == selected))
                        .id(row.id)
                    }
                    if rows.isEmpty {
                        Text(query.isEmpty ? "Здесь появится недавнее" : "Ничего не нашлось")
                            .font(.callout)
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(10)
            }
            .onChange(of: selected) { _, index in
                guard rows.indices.contains(index) else { return }
                proxy.scrollTo(rows[index].id)
            }
        }
    }

    private func rowView(_ row: Row, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            if case .command(let command) = row.kind, let kind = command.createKind {
                CreateKindIcon(kind: kind, size: 26)
            } else {
                Image(systemName: row.systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .frame(width: 26, height: 26)
            }
            Text(row.title)
                .font(.callout)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            if !isCompact, case .command(let command) = row.kind, let shortcut = command.shortcut {
                ShortcutHint(text: shortcut)
            }
            if isSelected, !isCompact {
                ShortcutHint(text: "↵")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Label { Text("выбрать") } icon: { ShortcutHint(text: "↑↓") }
            Label { Text("открыть") } icon: { ShortcutHint(text: "↵") }
            Label { Text("открыть рядом") } icon: { ShortcutHint(text: "⌘↵") }
            Spacer()
            Text("«>» в начале: только действия")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, 18)
        .frame(height: 40)
    }

    // MARK: Строки

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var rows: [Row] {
        let text = trimmedQuery
        let commandsOnly = text.hasPrefix(">")
        let commandQuery = commandsOnly ? String(text.dropFirst()).trimmingCharacters(in: .whitespaces) : text
        var rows: [Row] = []

        if text.isEmpty {
            rows += recent.map { item -> Row in
                switch item {
                case .page(let page):
                    Row(id: "recent-\(page.id)", section: "Недавнее", title: page.displayTitle, detail: page.updatedAt.lumenRelative, systemImage: page.isNotebook ? "pencil.and.scribble" : "doc.text", kind: .open(.page(page.id)))
                case .source(let source):
                    Row(id: "recent-\(source.id)", section: "Недавнее", title: source.displayTitle, detail: "Книга · \(Int((source.progress * 100).rounded()))%", systemImage: source.format.symbolName, kind: .open(.source(source.id, highlight: nil)))
                }
            }
        } else if !commandsOnly {
            rows += results.pages.map {
                Row(id: "page-\($0.pageId)", section: "Страницы", title: $0.title.isEmpty ? "Без названия" : $0.title, detail: $0.snippet, systemImage: "doc.text", kind: .open(.page($0.pageId)))
            }
            rows += results.sources.map {
                Row(id: "source-\($0.id)", section: "Книги и файлы", title: $0.displayTitle, detail: $0.author ?? "", systemImage: $0.format.symbolName, kind: .open(.source($0.id, highlight: nil)))
            }
            rows += results.highlights.map {
                Row(id: "highlight-\($0.id)", section: "Цитаты", title: $0.highlight.text, detail: $0.sourceTitle, systemImage: "quote.opening", kind: .open(.source($0.highlight.sourceId, highlight: $0.highlight.id)))
            }
        }

        let matching = commandQuery.isEmpty ? commands : commands.filter { $0.matches(commandQuery) }
        rows += matching.map {
            Row(id: "command-\($0.id)", section: "Действия", title: $0.title, detail: "", systemImage: $0.systemImage, kind: .command($0))
        }
        return rows
    }

    private func move(_ step: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selected = (selected + step + count) % count
    }

    private func activate(_ index: Int, beside: Bool) {
        let rows = rows
        guard rows.indices.contains(index) else { return }
        switch rows[index].kind {
        case .open(let item):
            LumenSounds.play(.navigate)
            onOpen(item, beside)
        case .command(let command):
            onDismiss()
            command.run()
        }
    }

    private func loadRecent() async {
        do {
            recent = try await database.reader.read { db in try RecentQuery.fetch(db, limit: 6) }
        } catch {
            lumenLog.error("Palette recent failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func runSearch() async {
        let text = trimmedQuery
        guard !text.isEmpty, !text.hasPrefix(">") else {
            results = .empty
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let found = (try? await database.searchEverything(text)) ?? .empty
        guard !Task.isCancelled else { return }
        results = found
    }
}

extension PaletteCommand {
    /// Общие действия ⌘K. Действия, которым нужен экран вокруг, передаёт он сам.
    @MainActor
    static func standard(actions: AppActions, extra: [PaletteCommand] = []) -> [PaletteCommand] {
        var list: [PaletteCommand] = CreateKind.allCases.map { kind in
            PaletteCommand(
                id: "create-\(kind.rawValue)",
                title: kind == .book ? "Добавить книгу или файл" : "Новая \(kind.paletteNoun)",
                systemImage: kind.systemImage,
                shortcut: kind.shortcutHint,
                keywords: ["создать", "новый", "новая", kind.title, kind.subtitle],
                createKind: kind,
                run: { actions.create(kind) }
            )
        }
        let places: [(String, String, SidebarItem, [String])] = [
            ("Перейти: Сегодня", "sun.max", .home, ["главная", "дом"]),
            ("Перейти: Входящие", "tray", .inbox, ["заметки", "разобрать"]),
            ("Перейти: Задачи", "checklist", .tasks, ["дела", "список"]),
            ("Перейти: Библиотека", "books.vertical", .library(nil), ["папки", "книги"]),
            ("Перейти: Корзина", "trash", .trash, ["удалённое"]),
        ]
        list += places.map { title, image, item, words in
            PaletteCommand(id: "go-\(title)", title: title, systemImage: image, keywords: words, run: { actions.open(item) })
        }
        list.append(PaletteCommand(id: "settings", title: "Настройки", systemImage: "gearshape", keywords: ["звук", "копия", "данные", "синхронизация"], run: actions.settings))
        return list + extra
    }
}

extension PaletteCommand {
    /// «Минута дыхания» из «Дзена».
    static func breathe(_ run: @escaping @MainActor () -> Void) -> PaletteCommand {
        PaletteCommand(
            id: "breathe",
            title: "Минута дыхания",
            systemImage: "wind",
            keywords: ["дзен", "тишина", "успокоиться", "пауза", "вдох"],
            run: run
        )
    }

    /// «Тема: Закат» и остальные: сменить оформление, не открывая настроек.
    static func themes(current: String) -> [PaletteCommand] {
        Theme.all.map { option in
            PaletteCommand(
                id: "theme-\(option.id)",
                title: "Тема: \(option.name)",
                systemImage: option.id == current ? "checkmark.circle.fill" : "paintpalette",
                keywords: ["тема", "оформление", "цвет", "вид"],
                run: { UserDefaults.standard.set(option.id, forKey: Theme.storageKey) }
            )
        }
    }
}

private extension CreateKind {
    /// «Новая …» в ⌘K.
    var paletteNoun: String {
        switch self {
        case .note: "заметка"
        case .task: "задача на сегодня"
        case .notebook: "тетрадь от руки"
        case .book: "книга"
        case .database: "база данных"
        case .folder: "папка"
        }
    }
}
