import LumenCore
import LumenThemes
import SwiftUI

/// Вариант выбора цветной капсулой, как в Notion.
struct OptionChip: View {
    let option: SelectOption

    var body: some View {
        Text(option.name)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(option.color.textColor)
            .background(option.color.backgroundColor, in: Capsule())
    }
}

/// Срок задачи словами: «Сегодня», «Завтра», «5 нояб.». Просроченный срок красный.
struct DayLabel: View {
    let day: DayDate
    /// Красить ли просроченный срок. У выполненной задачи срок уже не важен.
    var highlightsOverdue = true

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Label(Self.text(day), systemImage: "calendar")
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(color)
    }

    private var color: Color {
        let today = DayDate.today()
        if highlightsOverdue && day < today { return BlockColor.red.textColor }
        if day == today { return theme.accent }
        return theme.textSecondary
    }

    static func text(_ day: DayDate) -> String {
        let today = DayDate.today()
        switch day {
        case today: return "Сегодня"
        case today.adding(days: 1): return "Завтра"
        case today.adding(days: -1): return "Вчера"
        default:
            let format: Date.FormatStyle = day.year == today.year
                ? .dateTime.day().month(.abbreviated)
                : .dateTime.day().month(.abbreviated).year()
            return day.date().formatted(format.locale(Locale(identifier: "ru_RU")))
        }
    }
}

/// Значение свойства только для показа: в карточках доски, списке и календаре.
struct PropertyValueLabel: View {
    let property: PropertyDefinition
    let value: PropertyValue?
    var pages: [Page] = []
    var isDone = false

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        switch value {
        case nil:
            EmptyView()
        case .text(let text)?:
            Text(text).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
        case .number(let number)?:
            Text(NumberText.format(number)).font(.caption.monospacedDigit()).foregroundStyle(theme.textSecondary)
        case .option(let id)?:
            if let option = property.option(id) { OptionChip(option: option) }
        case .options(let ids)?:
            HStack(spacing: 4) {
                ForEach(ids.compactMap { property.option($0) }) { OptionChip(option: $0) }
            }
        case .date(let day)?:
            DayLabel(day: day, highlightsOverdue: !isDone)
        case .checkbox(let isOn)?:
            if isOn {
                Label(property.name, systemImage: "checkmark.square.fill")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        case .page(let id)?:
            Label(pages.first { $0.id == id }?.displayTitle ?? "Страница", systemImage: "arrow.up.right.square")
                .font(.caption)
                .foregroundStyle(theme.accent)
                .lineLimit(1)
        }
    }
}

enum NumberText {
    static func format(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...4)).locale(Locale(identifier: "ru_RU")))
    }

    static func parse(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        return Double(cleaned)
    }
}

/// Текстовое поле, которое пишет в базу не на каждую букву, а когда закончили: по Return
/// или когда поле теряет фокус.
struct CommitTextField: View {
    let placeholder: String
    let text: String
    var font: Font = .body
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .font(font)
            .focused($isFocused)
            .onAppear { draft = text }
            .onChange(of: text) { _, newValue in
                if !isFocused { draft = newValue }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit(commit)
            .onDisappear(perform: commit)
    }

    private func commit() {
        if draft != text { onCommit(draft) }
    }
}

/// Редактор значения свойства: поле, меню вариантов, дата, флажок или ссылка на страницу.
/// Им пользуются ячейки таблицы и панель свойств на странице строки.
struct PropertyValueEditor: View {
    let property: PropertyDefinition
    let value: PropertyValue?
    var pages: [Page] = []
    let onChange: (PropertyValue?) -> Void
    /// Создать вариант по имени, набранному в меню. Возвращает его, чтобы сразу выбрать.
    var onAddOption: ((String) -> SelectOption?)?
    /// Открыть страницу из свойства-ссылки.
    var onOpenPage: ((UUID) -> Void)?

    @State private var isPickingDate = false
    @State private var isAddingOption = false
    @State private var newOptionName = ""
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        control
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .alert("Новый вариант", isPresented: $isAddingOption) {
                TextField("Название", text: $newOptionName)
                Button("Добавить") {
                    if let option = onAddOption?(newOptionName) {
                        select(option)
                    }
                    newOptionName = ""
                }
                Button("Отмена", role: .cancel) { newOptionName = "" }
            }
    }

    @ViewBuilder
    private var control: some View {
        switch property.type {
        case .text:
            CommitTextField(placeholder: "Пусто", text: value?.text ?? "") { text in
                onChange(.text(text))
            }
        case .number:
            CommitTextField(placeholder: "Пусто", text: value?.number.map(NumberText.format) ?? "") { text in
                onChange(NumberText.parse(text).map(PropertyValue.number))
            }
        case .select, .status, .multiSelect:
            optionsMenu
        case .date:
            Button {
                isPickingDate = true
            } label: {
                if let day = value?.dayDate {
                    DayLabel(day: day)
                } else {
                    placeholder
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPickingDate) {
                DayPicker(day: value?.dayDate) { day in
                    onChange(day.map(PropertyValue.date))
                    isPickingDate = false
                }
            }
        case .checkbox:
            Button {
                LumenSounds.play(.toggle)
                onChange(.checkbox(!(value?.isChecked ?? false)))
            } label: {
                Image(systemName: value?.isChecked == true ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(value?.isChecked == true ? theme.accent : theme.textSecondary)
            }
            .buttonStyle(.plain)
        case .page:
            pageMenu
        }
    }

    private var placeholder: some View {
        Text("Пусто")
            .font(.callout)
            .foregroundStyle(theme.textSecondary.opacity(0.6))
    }

    private var selectedIds: [UUID] { value?.optionIds ?? [] }

    private var optionsMenu: some View {
        Menu {
            ForEach(property.options) { option in
                Button {
                    select(option)
                } label: {
                    if selectedIds.contains(option.id) {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
            if onAddOption != nil {
                Divider()
                Button {
                    isAddingOption = true
                } label: {
                    Label("Новый вариант…", systemImage: "plus")
                }
            }
            if !selectedIds.isEmpty {
                Button("Очистить", role: .destructive) { onChange(nil) }
            }
        } label: {
            let selected = selectedIds.compactMap { property.option($0) }
            if selected.isEmpty {
                placeholder
            } else {
                HStack(spacing: 4) {
                    ForEach(selected) { OptionChip(option: $0) }
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func select(_ option: SelectOption) {
        LumenSounds.play(.tap)
        if property.type == .multiSelect {
            var ids = selectedIds
            if let index = ids.firstIndex(of: option.id) {
                ids.remove(at: index)
            } else {
                ids.append(option.id)
            }
            onChange(.options(ids))
        } else if selectedIds == [option.id] {
            onChange(nil)
        } else {
            onChange(.option(option.id))
        }
    }

    private var pageMenu: some View {
        Menu {
            if let id = value?.pageId, let onOpenPage {
                Button {
                    onOpenPage(id)
                } label: {
                    Label("Открыть", systemImage: "arrow.up.right")
                }
                Button("Убрать ссылку", role: .destructive) { onChange(nil) }
                Divider()
            }
            ForEach(pages.prefix(60)) { page in
                Button(page.displayTitle) { onChange(.page(page.id)) }
            }
        } label: {
            if let id = value?.pageId {
                Label(pages.first { $0.id == id }?.displayTitle ?? "Страница", systemImage: "arrow.up.right.square")
                    .font(.callout)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            } else {
                placeholder
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Выбор дня: быстрые варианты и календарь.
struct DayPicker: View {
    let day: DayDate?
    let onPick: (DayDate?) -> Void

    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                quick("Сегодня", days: 0)
                quick("Завтра", days: 1)
                quick("Через неделю", days: 7)
            }
            DatePicker("Дата", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ru_RU"))
            HStack {
                if day != nil {
                    Button("Убрать дату", role: .destructive) { onPick(nil) }
                }
                Spacer()
                Button("Готово") { onPick(DayDate(date)) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 300)
        .onAppear { date = day?.date() ?? Date() }
        .presentationCompactAdaptation(.popover)
    }

    private func quick(_ title: String, days: Int) -> some View {
        Button(title) { onPick(DayDate.today().adding(days: days)) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

extension DataRow {
    /// Строка отмечена статусом «готово».
    func isDone(status: PropertyDefinition?) -> Bool {
        guard let status else { return false }
        return value(status.id)?.optionIds.contains { status.option($0)?.isDone == true } ?? false
    }
}
