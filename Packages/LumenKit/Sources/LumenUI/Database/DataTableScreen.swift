import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Экран базы данных: название, вкладки представлений, фильтры и сортировки, а под ними
/// таблица, доска, календарь или список. Одна и та же для задач и любых своих баз.
struct DataTableScreen: View {
    @State private var model: DataTableModel
    var onOpenPage: (UUID) -> Void

    @State private var isEditingFilters = false
    @State private var isEditingSorts = false
    @State private var renamingView: DataView?
    @State private var newName = ""
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme

    private static let icons = ["✅", "📋", "📚", "🎓", "🗓️", "🎯", "💡", "🧠", "📈", "⭐️"]

    init(database: AppDatabase, pageId: UUID, initialViewId: UUID? = nil, onOpenPage: @escaping (UUID) -> Void) {
        _model = State(initialValue: DataTableModel(database: database, pageId: pageId, initialViewId: initialViewId))
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.table != nil {
                    viewTabs
                    controls
                    content
                }
            }
            .padding(.horizontal, isCompact ? 16 : 28)
            .padding(.vertical, isCompact ? 16 : 24)
            .frame(maxWidth: model.view?.layout == .list ? 820 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ThemedBackground())
        .navigationTitle(model.page?.displayTitle ?? "")
        .task { await model.observe() }
        .alert("Название представления", isPresented: Binding(get: { renamingView != nil }, set: { if !$0 { renamingView = nil } })) {
            TextField("Название", text: $newName)
            Button("Готово") {
                if let view = renamingView {
                    model.renameView(view.id, newName)
                }
                renamingView = nil
            }
            Button("Отмена", role: .cancel) { renamingView = nil }
        }
        .overlay {
            if model.isLoaded, model.table == nil {
                ContentUnavailableView("Базы данных здесь нет", systemImage: "tablecells")
            }
        }
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
        HStack(alignment: .center, spacing: 10) {
            Menu {
                ForEach(Self.icons, id: \.self) { icon in
                    Button(icon) { model.setIcon(icon) }
                }
                if model.page?.icon != nil {
                    Divider()
                    Button("Убрать иконку", role: .destructive) { model.setIcon(nil) }
                }
            } label: {
                Text(model.page?.icon ?? "📋").font(.system(size: 36))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            CommitTextField(placeholder: "Без названия", text: model.page?.title ?? "", font: .system(size: 32, weight: .bold)) {
                model.rename($0)
            }
            .foregroundStyle(theme.textPrimary)
        }
    }

    // MARK: Вкладки представлений

    private var viewTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.table?.views ?? []) { view in
                    let isSelected = view.id == model.view?.id
                    Button {
                        LumenSounds.play(.tap)
                        withAnimation(.snappy) { model.selectedViewId = view.id }
                    } label: {
                        Label(view.name, systemImage: view.layout.symbolName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                            .background {
                                Capsule().fill(isSelected ? theme.accent.opacity(0.25) : Color.clear)
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            newName = view.name
                            renamingView = view
                        } label: {
                            Label("Переименовать", systemImage: "pencil")
                        }
                        Button {
                            model.duplicateView(view.id)
                        } label: {
                            Label("Дублировать", systemImage: "plus.square.on.square")
                        }
                        if (model.table?.views.count ?? 0) > 1 {
                            Divider()
                            Button(role: .destructive) {
                                model.deleteView(view.id)
                            } label: {
                                Label("Удалить представление", systemImage: "trash")
                            }
                        }
                    }
                }
                Menu {
                    ForEach(DataViewLayout.allCases) { layout in
                        Button {
                            model.addView(layout)
                        } label: {
                            Label(layout.title, systemImage: layout.symbolName)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .padding(8)
                        .foregroundStyle(theme.textSecondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Новое представление")
            }
        }
    }

    // MARK: Фильтры, сортировки, настройки

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                isEditingFilters = true
            } label: {
                controlLabel("Фильтр", systemImage: "line.3.horizontal.decrease", count: model.view?.filters.count ?? 0)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEditingFilters) {
                FilterEditor(model: model)
            }

            Button {
                isEditingSorts = true
            } label: {
                controlLabel("Сортировка", systemImage: "arrow.up.arrow.down", count: model.view?.sorts.count ?? 0)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEditingSorts) {
                SortEditor(model: model)
            }

            ViewSettingsMenu(model: model) {
                controlLabel("Вид", systemImage: "slider.horizontal.3", count: 0)
            }

            Spacer()

            Text(rowCountText)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var rowCountText: String {
        let count = model.visibleRows.count
        let tens = count % 100
        let ones = count % 10
        let word = if (11...14).contains(tens) {
            "записей"
        } else if ones == 1 {
            "запись"
        } else if (2...4).contains(ones) {
            "записи"
        } else {
            "записей"
        }
        return "\(count) \(word)"
    }

    private func controlLabel(_ title: String, systemImage: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            if !isCompact || count > 0 {
                Text(count > 0 ? "\(title): \(count)" : title)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(count > 0 ? theme.accent : theme.textSecondary)
        .background(Capsule().fill(count > 0 ? theme.accent.opacity(0.15) : theme.cardFill))
        .overlay(Capsule().strokeBorder(theme.cardStroke))
    }

    @ViewBuilder
    private var content: some View {
        switch model.view?.layout ?? .table {
        case .table:
            DataTableGrid(model: model, onOpen: open)
        case .board:
            DataBoardView(model: model, onOpen: open)
        case .calendar:
            DataCalendarView(model: model, onOpen: open)
        case .list:
            DataListView(model: model, onOpen: open)
        }
    }

    private func open(_ id: UUID) {
        onOpenPage(id)
    }
}

// MARK: - Меню свойств

/// Меню заголовка колонки: переименовать, тип, варианты, сортировка, скрыть, удалить.
struct PropertyHeaderMenu<Label: View>: View {
    let model: DataTableModel
    let property: PropertyDefinition
    @ViewBuilder var label: () -> Label

    @State private var isRenaming = false
    @State private var isAddingOption = false
    @State private var name = ""

    var body: some View {
        Menu {
            Button {
                name = property.name
                isRenaming = true
            } label: {
                SwiftUI.Label("Переименовать", systemImage: "pencil")
            }
            Picker(selection: Binding(
                get: { property.type },
                set: { type in model.updateProperty(property.id) { $0.type = type } }
            )) {
                ForEach(PropertyType.allCases) { type in
                    SwiftUI.Label(type.title, systemImage: type.symbolName).tag(type)
                }
            } label: {
                SwiftUI.Label("Тип", systemImage: property.type.symbolName)
            }
            if property.type.hasOptions {
                Menu {
                    Button {
                        isAddingOption = true
                    } label: {
                        SwiftUI.Label("Новый вариант…", systemImage: "plus")
                    }
                    Divider()
                    ForEach(property.options) { option in
                        OptionMenu(model: model, property: property, option: option)
                    }
                } label: {
                    SwiftUI.Label("Варианты", systemImage: "list.bullet")
                }
            }
            Divider()
            Button {
                let id = property.id
                model.updateView { $0.sorts = [DataSort(propertyId: id, ascending: true)] }
            } label: {
                SwiftUI.Label("Сортировать по возрастанию", systemImage: "arrow.up")
            }
            Button {
                let id = property.id
                model.updateView { $0.sorts = [DataSort(propertyId: id, ascending: false)] }
            } label: {
                SwiftUI.Label("Сортировать по убыванию", systemImage: "arrow.down")
            }
            Button {
                let id = property.id
                model.updateView { $0.hiddenProperties.append(id) }
            } label: {
                SwiftUI.Label("Скрыть в этом представлении", systemImage: "eye.slash")
            }
            Divider()
            Button(role: .destructive) {
                model.deleteProperty(property.id)
            } label: {
                SwiftUI.Label("Удалить свойство", systemImage: "trash")
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .alert("Название свойства", isPresented: $isRenaming) {
            TextField("Название", text: $name)
            Button("Готово") {
                let newName = name.trimmingCharacters(in: .whitespaces)
                if !newName.isEmpty {
                    model.updateProperty(property.id) { $0.name = newName }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Новый вариант", isPresented: $isAddingOption) {
            TextField("Название", text: $name)
            Button("Добавить") {
                _ = model.addOption(to: property.id, name: name)
                name = ""
            }
            Button("Отмена", role: .cancel) { name = "" }
        }
    }
}

/// Подменю одного варианта: цвет, «значит готово» у статуса, удалить.
private struct OptionMenu: View {
    let model: DataTableModel
    let property: PropertyDefinition
    let option: SelectOption

    var body: some View {
        Menu(option.name) {
            Picker("Цвет", selection: Binding(
                get: { option.color },
                set: { color in update { $0.color = color } }
            )) {
                ForEach(BlockColor.allCases) { color in
                    Text(color.title).tag(color)
                }
            }
            if property.type == .status {
                Toggle("Значит «готово»", isOn: Binding(
                    get: { option.isDone },
                    set: { isDone in update { $0.isDone = isDone } }
                ))
            }
            Divider()
            Button("Удалить вариант", role: .destructive) {
                let optionId = option.id
                model.updateProperty(property.id) { $0.options.removeAll { $0.id == optionId } }
            }
        }
    }

    private func update(_ change: @escaping @Sendable (inout SelectOption) -> Void) {
        let optionId = option.id
        model.updateProperty(property.id) { property in
            guard let index = property.options.firstIndex(where: { $0.id == optionId }) else { return }
            change(&property.options[index])
        }
    }
}

/// Меню «+» в конце заголовка таблицы: новое свойство нужного типа.
struct AddPropertyMenu<Label: View>: View {
    let model: DataTableModel
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            ForEach(PropertyType.allCases) { type in
                Button {
                    model.addProperty(type)
                } label: {
                    SwiftUI.Label(type.title, systemImage: type.symbolName)
                }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Новое свойство")
    }
}

/// Меню «Вид»: раскладка, группировка, дата для календаря, скрытые свойства.
private struct ViewSettingsMenu<Label: View>: View {
    let model: DataTableModel
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            if let view = model.view, let table = model.table {
                Picker(selection: Binding(
                    get: { view.layout },
                    set: { layout in model.updateView { $0.layout = layout } }
                )) {
                    ForEach(DataViewLayout.allCases) { layout in
                        SwiftUI.Label(layout.title, systemImage: layout.symbolName).tag(layout)
                    }
                } label: {
                    SwiftUI.Label("Раскладка", systemImage: view.layout.symbolName)
                }
                let groupable = table.properties.filter(\.type.canGroup)
                if view.layout == .board, !groupable.isEmpty {
                    Picker("Группировать по", selection: Binding(
                        get: { view.groupBy },
                        set: { id in model.updateView { $0.groupBy = id } }
                    )) {
                        ForEach(groupable) { property in
                            Text(property.name).tag(UUID?.some(property.id))
                        }
                    }
                }
                let dates = table.properties.filter { $0.type == .date }
                if view.layout == .calendar, !dates.isEmpty {
                    Picker("Дата", selection: Binding(
                        get: { view.dateProperty },
                        set: { id in model.updateView { $0.dateProperty = id } }
                    )) {
                        ForEach(dates) { property in
                            Text(property.name).tag(UUID?.some(property.id))
                        }
                    }
                }
                Menu {
                    ForEach(table.properties) { property in
                        Toggle(property.name, isOn: Binding(
                            get: { view.shows(property) },
                            set: { isShown in
                                let id = property.id
                                model.updateView { view in
                                    view.hiddenProperties.removeAll { $0 == id }
                                    if !isShown { view.hiddenProperties.append(id) }
                                }
                            }
                        ))
                    }
                } label: {
                    SwiftUI.Label("Свойства", systemImage: "eye")
                }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Фильтры

/// Список условий выбранного представления: свойство, условие, значение.
private struct FilterEditor: View {
    let model: DataTableModel

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Показывать записи, где")
                .font(.headline)
            let filters = model.view?.filters ?? []
            if filters.isEmpty {
                Text("Условий нет: видны все записи.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(filters) { filter in
                FilterRow(model: model, filter: filter)
            }
            Menu {
                Button("Название") { add(nil) }
                ForEach(model.table?.properties ?? []) { property in
                    Button {
                        add(property)
                    } label: {
                        Label(property.name, systemImage: property.type.symbolName)
                    }
                }
            } label: {
                Label("Добавить условие", systemImage: "plus")
            }
            .fixedSize()
        }
        .padding(16)
        .frame(minWidth: 380, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private func add(_ property: PropertyDefinition?) {
        let op = DataFilter.Operator.available(for: property?.type).first ?? .isNotEmpty
        var filter = DataFilter(propertyId: property?.id, op: op)
        switch property?.type {
        case .checkbox: filter.value = .checkbox(true)
        case .date: filter.relativeDays = 0
        default: break
        }
        let newFilter = filter
        model.updateView { $0.filters.append(newFilter) }
    }
}

private struct FilterRow: View {
    let model: DataTableModel
    let filter: DataFilter

    var body: some View {
        let property = model.table?.property(filter.propertyId)
        HStack(spacing: 8) {
            Text(property?.name ?? "Название")
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Picker("", selection: Binding(
                get: { filter.op },
                set: { op in change { $0.op = op } }
            )) {
                ForEach(DataFilter.Operator.available(for: property?.type), id: \.self) { op in
                    Text(op.title).tag(op)
                }
            }
            .labelsHidden()
            .fixedSize()
            if !filter.op.isUnary {
                valueControl(property)
            }
            Spacer(minLength: 0)
            Button {
                let id = filter.id
                model.updateView { $0.filters.removeAll { $0.id == id } }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func valueControl(_ property: PropertyDefinition?) -> some View {
        switch property?.type {
        case nil, .text, .number:
            CommitTextField(placeholder: "Значение", text: filterText) { text in
                let value: PropertyValue? = if property?.type == .number {
                    NumberText.parse(text).map(PropertyValue.number)
                } else {
                    text.isEmpty ? nil : .text(text)
                }
                change { $0.value = value }
            }
            .frame(width: 120)
        case .date:
            Picker("", selection: Binding(
                get: { filter.relativeDays ?? 0 },
                set: { days in change { $0.relativeDays = days; $0.value = nil } }
            )) {
                Text("неделю назад").tag(-7)
                Text("вчера").tag(-1)
                Text("сегодня").tag(0)
                Text("завтра").tag(1)
                Text("через неделю").tag(7)
            }
            .labelsHidden()
            .fixedSize()
        case .checkbox:
            Picker("", selection: Binding(
                get: { filter.value?.isChecked ?? true },
                set: { isOn in change { $0.value = .checkbox(isOn) } }
            )) {
                Text("отмечено").tag(true)
                Text("не отмечено").tag(false)
            }
            .labelsHidden()
            .fixedSize()
        case let type?:
            if let property {
                PropertyValueEditor(
                    property: property,
                    value: filterValueForEditor(type),
                    pages: model.snapshot.linkablePages,
                    onChange: { value in
                        // В условии «содержит» для нескольких вариантов хватает одного варианта.
                        let stored: PropertyValue? = if type == .multiSelect, let id = value?.optionIds.last {
                            .option(id)
                        } else {
                            value
                        }
                        change { $0.value = stored }
                    }
                )
                .frame(width: 140)
            }
        }
    }

    private func filterValueForEditor(_ type: PropertyType) -> PropertyValue? {
        if type == .multiSelect, let id = filter.value?.optionIds.first {
            return .options([id])
        }
        return filter.value
    }

    private var filterText: String {
        switch filter.value {
        case .text(let text)?: text
        case .number(let number)?: NumberText.format(number)
        default: ""
        }
    }

    private func change(_ update: @escaping @Sendable (inout DataFilter) -> Void) {
        let id = filter.id
        model.updateView { view in
            guard let index = view.filters.firstIndex(where: { $0.id == id }) else { return }
            update(&view.filters[index])
        }
    }
}

// MARK: - Сортировки

private struct SortEditor: View {
    let model: DataTableModel

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сортировать по")
                .font(.headline)
            let sorts = model.view?.sorts ?? []
            if sorts.isEmpty {
                Text("Без сортировки записи идут в том порядке, в каком их расставили.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(sorts) { sort in
                HStack(spacing: 8) {
                    Text(model.table?.property(sort.propertyId)?.name ?? "Название")
                        .font(.callout.weight(.medium))
                    Picker("", selection: Binding(
                        get: { sort.ascending },
                        set: { ascending in
                            let id = sort.id
                            model.updateView { view in
                                guard let index = view.sorts.firstIndex(where: { $0.id == id }) else { return }
                                view.sorts[index].ascending = ascending
                            }
                        }
                    )) {
                        Text("по возрастанию").tag(true)
                        Text("по убыванию").tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer(minLength: 0)
                    Button {
                        let id = sort.id
                        model.updateView { $0.sorts.removeAll { $0.id == id } }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Menu {
                Button("Название") { add(nil) }
                ForEach(model.table?.properties ?? []) { property in
                    Button {
                        add(property.id)
                    } label: {
                        Label(property.name, systemImage: property.type.symbolName)
                    }
                }
            } label: {
                Label("Добавить сортировку", systemImage: "plus")
            }
            .fixedSize()
        }
        .padding(16)
        .frame(minWidth: 320, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private func add(_ propertyId: UUID?) {
        let sort = DataSort(propertyId: propertyId)
        model.updateView { $0.sorts.append(sort) }
    }
}

// MARK: - Страница строки

/// Свойства строки над текстом её страницы, как в Notion: открыл задачу и видишь статус и срок.
struct RowPropertiesPanel: View {
    let database: AppDatabase
    let rowId: UUID
    var onOpenPage: (UUID) -> Void

    @State private var snapshot = DataRowSnapshot.empty
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let table = snapshot.table, let row = snapshot.row {
                ForEach(table.properties) { property in
                    HStack(alignment: .center, spacing: 12) {
                        Label(property.name, systemImage: property.type.symbolName)
                            .font(.callout)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)
                        PropertyValueEditor(
                            property: property,
                            value: row.value(property.id),
                            pages: snapshot.linkablePages,
                            onChange: { value in
                                let propertyId = property.id
                                Task { try? await database.setValue(value, property: propertyId, row: rowId) }
                            },
                            onAddOption: { name in addOption(name, to: property, tableId: table.id) },
                            onOpenPage: onOpenPage
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .task { await observe() }
    }

    private func addOption(_ name: String, to property: PropertyDefinition, tableId: UUID) -> SelectOption? {
        guard let found = DataTableModel.option(named: name, in: property) else { return nil }
        let option = found.option
        if found.isNew {
            let propertyId = property.id
            Task {
                try? await database.updateDataTable(tableId) { table in
                    guard let index = table.properties.firstIndex(where: { $0.id == propertyId }) else { return }
                    table.properties[index].options.append(option)
                }
            }
        }
        return option
    }

    private func observe() async {
        let rowId = rowId
        let observation = ValueObservation.tracking { db in try DataRowSnapshot.fetch(db, rowId: rowId) }
        do {
            for try await value in observation.values(in: database.reader) {
                snapshot = value
            }
        } catch {
            print("Row observation failed: \(error)")
        }
    }
}

// MARK: - Маршрутизация

/// Страница по ссылке: обычная страница открывается в редакторе, а страница с базой как база.
struct PageScreen: View {
    let database: AppDatabase
    let pageId: UUID
    var onOpenPage: (UUID) -> Void
    var onClose: () -> Void
    var onOpenSource: (UUID, UUID?) -> Void

    @State private var isDataTable: Bool

    init(
        database: AppDatabase,
        pageId: UUID,
        onOpenPage: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void,
        onOpenSource: @escaping (UUID, UUID?) -> Void
    ) {
        self.database = database
        self.pageId = pageId
        self.onOpenPage = onOpenPage
        self.onClose = onClose
        self.onOpenSource = onOpenSource
        // Короткое чтение прямо при открытии: так экран не мигает редактором перед базой.
        let hasTable = (try? database.reader.read { db in
            try DataTable.filter(Column("pageId") == pageId).fetchCount(db) > 0
        }) ?? false
        _isDataTable = State(initialValue: hasTable)
    }

    var body: some View {
        if isDataTable {
            DataTableScreen(database: database, pageId: pageId, onOpenPage: onOpenPage)
        } else {
            PageEditorView(
                database: database,
                pageId: pageId,
                onOpenPage: onOpenPage,
                onClose: onClose,
                onOpenSource: onOpenSource
            )
        }
    }
}

/// Раздел «Задачи»: база задач, открытая на представлении «Сегодня». Создаётся при первом входе.
struct TasksScreen: View {
    let database: AppDatabase
    var onOpenPage: (UUID) -> Void

    @State private var table: DataTable?

    var body: some View {
        Group {
            if let table {
                DataTableScreen(database: database, pageId: table.pageId, initialViewId: table.views.first?.id, onOpenPage: onOpenPage)
                    .id(table.id)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ThemedBackground())
            }
        }
        .task {
            table = try? await database.tasksDataTable()
        }
    }
}
