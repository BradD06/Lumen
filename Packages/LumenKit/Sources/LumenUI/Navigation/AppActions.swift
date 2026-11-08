import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Что можно создать кнопкой «Создать». Один список для сайдбара, панели окна, ⌘K и iPhone.
enum CreateKind: String, CaseIterable, Identifiable, Sendable {
    case note
    case task
    case notebook
    case book
    case database
    case folder

    var id: Self { self }

    var title: String {
        switch self {
        case .note: "Заметка"
        case .task: "Задача"
        case .notebook: "Тетрадь от руки"
        case .book: "Книга или файл"
        case .database: "База данных"
        case .folder: "Папка"
        }
    }

    var subtitle: String {
        switch self {
        case .note: "Пустая страница с блоками"
        case .task: "Сразу в «Задачи» на сегодня"
        #if os(macOS)
        case .notebook: "Писать пером или мышью"
        #else
        case .notebook: "Писать пальцем или Apple Pencil"
        #endif
        case .book: "EPUB, PDF, FB2, DOCX и другие"
        case .database: "Таблица, доска, календарь"
        case .folder: "Чтобы разложить всё по темам"
        }
    }

    var systemImage: String {
        switch self {
        case .note: "doc.text"
        case .task: "checklist"
        case .notebook: "pencil.and.scribble"
        case .book: "book.closed"
        case .database: "tablecells"
        case .folder: "folder"
        }
    }

    /// Цвет значка: номер яркой карточки темы, у папки нейтральный.
    var vividIndex: Int? {
        switch self {
        case .note: 0
        case .task: 3
        case .notebook: 1
        case .book: 4
        case .database: 2
        case .folder: nil
        }
    }

    /// Подсказка о сочетании клавиш в меню. Сами сочетания висят на невидимых кнопках в `RootView`.
    var shortcutHint: String? {
        switch self {
        case .note: "⌘N"
        case .task: "⇧⌘N"
        case .book: "⌘O"
        default: nil
        }
    }
}

/// Действия приложения, доступные с любого экрана: открыть раздел, создать, найти, настроить.
/// Корневой экран (Mac, iPad, iPhone) кладёт их в окружение, экраны только вызывают.
struct AppActions {
    var open: @MainActor (SidebarItem) -> Void = { _ in }
    var create: @MainActor (CreateKind) -> Void = { _ in }
    /// Быстрая мысль из поля «Запишите мысль»: во «Входящие» или задачей на сегодня.
    var capture: @MainActor (_ text: String, _ asTask: Bool) -> Void = { _, _ in }
    var search: @MainActor () -> Void = {}
    var settings: @MainActor () -> Void = {}
    /// Минута дыхания на весь экран («Дзен»), там, где есть окно, которое её покажет.
    var breathe: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    @Entry var appActions = AppActions()
}

/// Создаёт новое и говорит, что открыть. Общая часть для Mac, iPad и iPhone.
@MainActor
struct Creator {
    let database: AppDatabase
    var open: (SidebarItem) -> Void

    /// Всё, кроме книги: для неё сначала нужно окно выбора файла, его показывает экран.
    func create(_ kind: CreateKind) {
        Task {
            switch kind {
            case .note:
                if let page = await NoticeCenter.shared.perform("Не удалось создать заметку", {
                    try await database.createPage(inInbox: true)
                }) {
                    LumenSounds.play(.create)
                    open(.page(page.id))
                }
            case .task:
                if let row = await NoticeCenter.shared.perform("Не удалось создать задачу", {
                    try await Self.addTodayTask(title: "", in: database)
                }) {
                    LumenSounds.play(.create)
                    open(.page(row.id))
                }
            case .notebook:
                if let page = await NoticeCenter.shared.perform("Не удалось создать тетрадь", {
                    try await database.createNotebook()
                }) {
                    LumenSounds.play(.create)
                    open(.page(page.id))
                }
            case .database:
                if let table = await NoticeCenter.shared.perform("Не удалось создать базу", {
                    try await database.createDataTable(title: "Новая база", icon: "📋")
                }) {
                    LumenSounds.play(.create)
                    open(.page(table.pageId))
                }
            case .folder:
                if let folder = await NoticeCenter.shared.perform("Не удалось создать папку", {
                    try await database.createFolder(name: "Новая папка", parentId: nil)
                }) {
                    LumenSounds.play(.create)
                    open(.library(folder.id))
                }
            case .book:
                break
            }
        }
    }

    /// Мысль из поля на главной: заметка во «Входящих» или задача на сегодня. Ничего не открывает,
    /// чтобы можно было записать следующую.
    func capture(_ text: String, asTask: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            let saved: Bool
            if asTask {
                saved = await NoticeCenter.shared.attempt("Не удалось добавить задачу") {
                    _ = try await Self.addTodayTask(title: trimmed, in: database)
                }
            } else {
                saved = await NoticeCenter.shared.attempt("Не удалось сохранить мысль") {
                    _ = try await database.createPage(title: trimmed, inInbox: true)
                }
            }
            if saved {
                LumenSounds.play(.create)
                NoticeCenter.shared.show(asTask ? "Задача на сегодня добавлена" : "Записано во «Входящие»")
            }
        }
    }

    /// Книги и файлы из окна выбора: в корень библиотеки. Одна книга сразу открывается.
    func importBooks(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let sources = await SourceImporter.importFiles(urls, into: database, folderId: nil, positions: [])
            if !sources.isEmpty { LumenSounds.play(.dropIntoFolder) }
            if sources.count == 1, let source = sources.first {
                open(.source(source.id, highlight: nil))
            }
        }
    }

    /// Новая задача в базе «Задачи» со сроком на сегодня, чтобы она сразу попала в «Сегодня».
    static func addTodayTask(title: String, in database: AppDatabase) async throws -> Page {
        let table = try await database.tasksDataTable()
        let values = table.views.first.map { DataQuery.presetValues(for: $0, in: table) } ?? PropertyValues()
        return try await database.addRow(to: table.id, title: title, values: values)
    }
}

// MARK: - Меню «Создать»

/// Список «Создать»: значок, название, пояснение и сочетание клавиш. На Mac и iPad во всплывающем окне.
struct CreateMenuList: View {
    var onSelect: (CreateKind) -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(CreateKind.allCases) { kind in
                if kind == .folder {
                    Divider().padding(.vertical, 4).padding(.horizontal, 10)
                }
                Button {
                    onSelect(kind)
                } label: {
                    HStack(spacing: 12) {
                        CreateKindIcon(kind: kind, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(kind.subtitle)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 12)
                        if let hint = kind.shortcutHint {
                            ShortcutHint(text: hint)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MenuRowButtonStyle())
                .accessibilityIdentifier("create-\(kind.rawValue)")
            }
        }
        .padding(8)
        .frame(width: 340)
    }
}

/// Цветная плитка со значком того, что создаётся.
struct CreateKindIcon: View {
    let kind: CreateKind
    var size: CGFloat = 34

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let vivid = kind.vividIndex.map { theme.vividCard($0) }
        Image(systemName: kind.systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(vivid?.foreground ?? theme.textPrimary)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(
                        vivid.map { AnyShapeStyle(LinearGradient(colors: $0.colors, startPoint: .top, endPoint: .bottom)) }
                            ?? AnyShapeStyle(theme.textPrimary.opacity(0.12))
                    )
            }
            .accessibilityHidden(true)
    }
}

/// Подпись сочетания клавиш, как на клавише.
struct ShortcutHint: View {
    let text: String
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.textPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.textPrimary.opacity(0.12)))
            .accessibilityHidden(true)
    }
}

/// Строка меню: подсвечивается под курсором и при нажатии.
struct MenuRowButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        MenuRowBody(configuration: configuration, isSelected: isSelected)
    }

    private struct MenuRowBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @State private var isHovered = false
        @Environment(\.lumenTheme) private var theme

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fill)
                }
                .onHover { isHovered = $0 }
        }

        private var fill: Color {
            if configuration.isPressed { return theme.textPrimary.opacity(0.14) }
            if isSelected { return theme.accent.opacity(0.22) }
            return isHovered ? theme.textPrimary.opacity(0.08) : .clear
        }
    }
}

/// Кнопка «Создать» в сайдбаре: открывает список того, что можно создать.
struct CreateButton: View {
    var onSelect: (CreateKind) -> Void

    @State private var isOpen = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Label("Создать", systemImage: "plus")
                .font(.callout.weight(.bold))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(theme.vividCard(0).foreground)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: theme.vividCard(0).colors, startPoint: .top, endPoint: .bottom))
                        .shadow(color: (theme.vividCard(0).colors.last ?? .orange).opacity(0.35), radius: 10, y: 5)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Создать заметку, задачу, тетрадь, книгу, базу или папку")
        .accessibilityIdentifier("create-button")
        .popover(isPresented: $isOpen, arrowEdge: .trailing) {
            CreateMenuList { kind in
                isOpen = false
                onSelect(kind)
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Быстрая мысль

/// Поле «Запишите мысль»: Return сохраняет во «Входящие», с переключателем «Это задача»
/// мысль становится задачей на сегодня. После сохранения поле очищается для следующей.
struct CaptureField: View {
    var placeholder = "Запишите мысль, она попадёт во «Входящие»"
    var onCapture: (_ text: String, _ asTask: Bool) -> Void

    @State private var text = ""
    @State private var isTask = false
    @FocusState private var isFocused: Bool
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isTask ? "checklist" : "pencil.line")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.glow)
                .frame(width: 22)
                .accessibilityHidden(true)
            TextField(isTask ? "Новая задача на сегодня" : placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.textPrimary)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .accessibilityIdentifier("capture-field")
            Toggle(isOn: $isTask) {
                Label("Это задача", systemImage: "checkmark.square")
                    .font(.footnote.weight(.semibold))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(isTask ? theme.vividCard(3).colors.last : theme.textSecondary)
            .help("Сохранить как задачу на сегодня")
            if !text.isEmpty {
                Button(action: save) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Сохранить")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(minHeight: 54)
        .lumenCard(padding: 0)
        .animation(.snappy, value: text.isEmpty)
    }

    private func save() {
        let value = text
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onCapture(value, isTask)
        text = ""
        isFocused = true
    }
}

// MARK: - iPhone: окно «Создать»

/// Окно «Создать» на iPhone: сверху поле для мысли, ниже плитки со всем, что можно создать.
struct CreateSheet: View {
    var onCapture: (_ text: String, _ asTask: Bool) -> Void
    var onSelect: (CreateKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CaptureField(placeholder: "Или просто начните печатать…") { text, asTask in
                        onCapture(text, asTask)
                        dismiss()
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(CreateKind.allCases) { kind in
                            Button {
                                dismiss()
                                onSelect(kind)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    CreateKindIcon(kind: kind, size: 40)
                                    Text(kind.title)
                                        .font(.callout.weight(.bold))
                                        .foregroundStyle(theme.textPrimary)
                                    Text(kind.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                        .lineLimit(2, reservesSpace: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lumenCard(padding: 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .background(ThemedBackground())
            .navigationTitle("Создать")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Настройки

/// «Настройки»: тема оформления, звуки, данные и копии, синхронизация. Одно окно вместо разбросанных пунктов.
struct SettingsSheet: View {
    let database: AppDatabase
    var onDone: () -> Void

    @AppStorage(LumenSounds.enabledKey) private var soundsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThemePicker()
                } header: {
                    Text("Тема оформления")
                } footer: {
                    Text("Меняет цвета, шрифт и светлый или тёмный режим во всём приложении. Вид книги в читалке настраивается отдельно, кнопкой «Аа».")
                }
                Section("Звук") {
                    Toggle("Звуки при действиях", isOn: $soundsEnabled)
                }
                Section {
                    NavigationLink {
                        DataSafetyView(database: database)
                            .navigationTitle("Данные и копии")
                    } label: {
                        Label("Данные и копии", systemImage: "externaldrive")
                    }
                } footer: {
                    Text("Резервная копия, восстановление и синхронизация.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", action: onDone)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}
