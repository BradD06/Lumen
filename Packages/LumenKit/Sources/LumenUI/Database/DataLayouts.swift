import LumenCore
import LumenThemes
import SwiftUI

// MARK: - Таблица

/// Таблица: строка на запись, колонка на свойство. Ячейки редактируются прямо в таблице.
struct DataTableGrid: View {
    let model: DataTableModel
    var onOpen: (UUID) -> Void

    @Environment(\.lumenTheme) private var theme

    private let titleWidth: CGFloat = 260
    private let columnWidth: CGFloat = 180

    var body: some View {
        let properties = model.visibleProperties
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    headerCell("Название", systemImage: "textformat", width: titleWidth)
                    ForEach(properties) { property in
                        PropertyHeaderMenu(model: model, property: property) {
                            headerCell(property.name, systemImage: property.type.symbolName, width: columnWidth)
                        }
                    }
                    AddPropertyMenu(model: model) {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 34)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Divider().overlay(theme.cardStroke)

                ForEach(model.visibleRows) { row in
                    HStack(spacing: 0) {
                        RowTitleCell(model: model, row: row, onOpen: onOpen)
                            .frame(width: titleWidth, alignment: .leading)
                        ForEach(properties) { property in
                            PropertyValueEditor(
                                property: property,
                                value: row.value(property.id),
                                pages: model.snapshot.linkablePages,
                                onChange: { model.setValue($0, property: property.id, row: row.id) },
                                onAddOption: { model.addOption(to: property.id, name: $0) },
                                onOpenPage: onOpen
                            )
                            .padding(.horizontal, 10)
                            .frame(width: columnWidth, height: 38, alignment: .leading)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(theme.cardStroke).frame(width: 1)
                            }
                        }
                    }
                    .contextMenu { RowMenu(model: model, row: row, onOpen: onOpen) }
                    Divider().overlay(theme.cardStroke.opacity(0.6))
                }

                Button {
                    Task { await model.addRow() }
                } label: {
                    Label("Новая строка", systemImage: "plus")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        }
        .lumenCard(padding: 0)
    }

    private func headerCell(_ title: String, systemImage: String, width: CGFloat) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(width: width, height: 34, alignment: .leading)
    }
}

/// Название строки: редактируется на месте, стрелка открывает строку как страницу.
private struct RowTitleCell: View {
    let model: DataTableModel
    let row: DataRow
    var onOpen: (UUID) -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if model.statusProperty != nil {
                DoneButton(model: model, row: row)
            }
            CommitTextField(placeholder: "Без названия", text: row.title, font: .body.weight(.medium)) {
                model.renameRow(row.id, $0)
            }
            Button {
                LumenSounds.play(.navigate)
                onOpen(row.id)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Открыть как страницу")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }
}

/// Кружок «выполнено» для баз со статусом.
struct DoneButton: View {
    let model: DataTableModel
    let row: DataRow

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let isDone = row.isDone(status: model.statusProperty)
        Button {
            model.toggleDone(row)
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isDone ? BlockColor.green.textColor : theme.textSecondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(isDone ? "Вернуть в работу" : "Отметить выполненным")
    }
}

/// Меню строки: открыть, переставить, удалить.
struct RowMenu: View {
    let model: DataTableModel
    let row: DataRow
    var onOpen: (UUID) -> Void

    var body: some View {
        Button {
            onOpen(row.id)
        } label: {
            Label("Открыть", systemImage: "arrow.up.right")
        }
        if model.view?.sorts.isEmpty == true {
            let rows = model.visibleRows
            if let index = rows.firstIndex(where: { $0.id == row.id }) {
                if index > 0 {
                    Button {
                        model.moveRow(row.id, after: index > 1 ? rows[index - 2].id : nil)
                    } label: {
                        Label("Выше", systemImage: "arrow.up")
                    }
                }
                if index < rows.count - 1 {
                    Button {
                        model.moveRow(row.id, after: rows[index + 1].id)
                    } label: {
                        Label("Ниже", systemImage: "arrow.down")
                    }
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            model.trashRow(row.id)
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}

// MARK: - Список

/// Список: строка с кружком «выполнено», названием и короткими значениями. Так выглядит «Сегодня».
struct DataListView: View {
    let model: DataTableModel
    var onOpen: (UUID) -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let rows = model.visibleRows
        VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text(model.view?.filters.isEmpty == false ? "Здесь пусто: под условия ничего не подходит." : "Пока ни одной записи.")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, 12)
            }
            ForEach(rows) { row in
                DataRowCard(model: model, row: row, onOpen: onOpen)
            }
            NewRowField(model: model)
        }
    }
}

/// Строка списка или карточка доски.
struct DataRowCard: View {
    let model: DataTableModel
    let row: DataRow
    var onOpen: (UUID) -> Void
    /// Свойство, которое не показывать: на доске оно и так видно по колонке.
    var hiding: UUID?
    var isCompact = false

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let isDone = row.isDone(status: model.statusProperty)
        // В списке статус показывает кружок слева, на доске колонка: повторять их незачем.
        let properties = model.visibleProperties.filter { property in
            property.id != hiding && (isCompact || property.id != model.statusProperty?.id)
        }
        HStack(alignment: .top, spacing: 10) {
            if model.statusProperty != nil, !isCompact {
                DoneButton(model: model, row: row)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(row.page.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isDone ? theme.textSecondary : theme.textPrimary)
                    .strikethrough(isDone && !isCompact)
                    .multilineTextAlignment(.leading)
                let shown = properties.filter { row.value($0.id) != nil }
                if !shown.isEmpty {
                    FlowChips(spacing: 6) {
                        ForEach(shown) { property in
                            PropertyValueLabel(
                                property: property,
                                value: row.value(property.id),
                                pages: model.snapshot.linkablePages,
                                isDone: isDone
                            )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.cardStroke))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            LumenSounds.play(.navigate)
            onOpen(row.id)
        }
        .contextMenu { RowMenu(model: model, row: row, onOpen: onOpen) }
    }
}

/// Поле «Новая задача» внизу списка или колонки: пишешь название и Return.
struct NewRowField: View {
    let model: DataTableModel
    var group: DataGroup?
    var day: DayDate?

    @State private var title = ""
    @FocusState private var isFocused: Bool
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(theme.textSecondary)
            TextField("Новая запись", text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(add)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        title = ""
        Task {
            await model.addRow(title: trimmed, group: group, day: day)
            // Курсор остаётся в поле: можно сразу писать следующую.
            isFocused = true
        }
    }
}

/// Значения в карточке переносятся на новую строку, когда не помещаются.
struct FlowChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for row in rows {
            for (index, x) in zip(row.indices, row.xs) {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var xs: [CGFloat] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if size.width == 0 && size.height == 0 { continue }
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.xs.append(current.indices.isEmpty ? 0 : current.width + spacing)
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Доска

/// Доска: колонка на каждый вариант свойства группировки. Карточку можно перетащить в другую колонку.
struct DataBoardView: View {
    let model: DataTableModel
    var onOpen: (UUID) -> Void

    @State private var targetedGroup: String?
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if let table = model.table, let view = model.view {
            if table.property(view.groupBy) == nil {
                GroupByHint(model: model)
            } else {
                let groups = DataQuery.groups(model.visibleRows, by: view.groupBy, in: table)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(groups) { group in
                            column(group, groupBy: view.groupBy)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func column(_ group: DataGroup, groupBy: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let option = group.option {
                    OptionChip(option: option)
                } else {
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                }
                Text("\(group.rows.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(group.rows) { row in
                DataRowCard(model: model, row: row, onOpen: onOpen, hiding: groupBy, isCompact: true)
                    .draggable(PageDragItem(pageId: row.id)) {
                        Text(row.page.displayTitle)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
            }
            NewRowField(model: model, group: group)
        }
        .padding(10)
        .frame(width: 270, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(group.option?.color.backgroundColor.opacity(0.35) ?? theme.cardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(targetedGroup == group.id ? theme.accent : theme.cardStroke, lineWidth: targetedGroup == group.id ? 2 : 1)
        }
        .dropDestination(for: PageDragItem.self) { items, _ in
            guard let groupBy else { return false }
            let value = model.table?.property(groupBy)?.type == .multiSelect
                ? group.value.flatMap { $0.optionIds.first }.map { PropertyValue.options([$0]) }
                : group.value
            for item in items {
                model.setValue(value, property: groupBy, row: item.pageId)
            }
            LumenSounds.play(.drop)
            return !items.isEmpty
        } isTargeted: { isTargeted in
            targetedGroup = isTargeted ? group.id : (targetedGroup == group.id ? nil : targetedGroup)
        }
    }
}

/// Подсказка, когда доске или календарю не хватает свойства.
private struct GroupByHint: View {
    let model: DataTableModel

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let candidates = model.table?.properties.filter(\.type.canGroup) ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text("Доске нужно свойство, по которому раскладывать карточки: выбор, статус или флажок.")
                .foregroundStyle(theme.textSecondary)
            if candidates.isEmpty {
                Button("Добавить свойство «Статус»") { model.addProperty(.status) }
                    .buttonStyle(.borderedProminent)
            } else {
                Menu("Группировать по…") {
                    ForEach(candidates) { property in
                        Button(property.name) {
                            let id = property.id
                            model.updateView { $0.groupBy = id }
                        }
                    }
                }
                .fixedSize()
            }
        }
        .lumenCard()
    }
}

// MARK: - Календарь

/// Календарь на месяц: записи стоят в днях своей даты. В пустой день можно добавить запись.
struct DataCalendarView: View {
    let model: DataTableModel
    var onOpen: (UUID) -> Void

    @State private var month = DayDate.today()
    @State private var addingDay: DayDate?
    @State private var newTitle = ""
    @Environment(\.lumenTheme) private var theme

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar
    }

    var body: some View {
        if let table = model.table, let view = model.view {
            if table.property(view.dateProperty)?.type != .date {
                dateHint(table)
            } else {
                let byDay = DataQuery.byDay(model.visibleRows, dateProperty: view.dateProperty)
                VStack(spacing: 10) {
                    header
                    weekdayRow
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day, rows: byDay[day] ?? [])
                            } else {
                                Color.clear.frame(height: 96)
                            }
                        }
                    }
                }
                .alert("Новая запись", isPresented: Binding(get: { addingDay != nil }, set: { if !$0 { addingDay = nil } })) {
                    TextField("Название", text: $newTitle)
                    Button("Добавить") {
                        let title = newTitle
                        let day = addingDay
                        newTitle = ""
                        addingDay = nil
                        Task { await model.addRow(title: title, day: day) }
                    }
                    Button("Отмена", role: .cancel) { newTitle = "" }
                } message: {
                    if let addingDay { Text(DayLabel.text(addingDay)) }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(month.date(calendar: calendar).formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "ru_RU"))).capitalized)
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                month = shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Button("Сегодня") { month = DayDate.today() }
            Button {
                month = shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.bordered)
    }

    private var weekdayRow: some View {
        HStack(spacing: 6) {
            ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Дни месяца по неделям, пустые места до первого числа.
    private var days: [DayDate?] {
        let first = DayDate(year: month.year, month: month.month, day: 1)
        let firstDate = first.date(calendar: calendar)
        let weekday = calendar.component(.weekday, from: firstDate)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: firstDate)?.count ?? 30
        return Array(repeating: nil, count: leading) + (0..<count).map { first.adding(days: $0, calendar: calendar) }
    }

    private func shiftMonth(_ delta: Int) -> DayDate {
        let first = DayDate(year: month.year, month: month.month, day: 1).date(calendar: calendar)
        return DayDate(calendar.date(byAdding: .month, value: delta, to: first) ?? first, calendar: calendar)
    }

    private func dayCell(_ day: DayDate, rows: [DataRow]) -> some View {
        let isToday = day == DayDate.today()
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(day.day)")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? theme.accent : theme.textSecondary)
                Spacer()
                Button {
                    addingDay = day
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            ForEach(rows.prefix(3)) { row in
                let isDone = row.isDone(status: model.statusProperty)
                Button {
                    onOpen(row.id)
                } label: {
                    Text(row.page.displayTitle)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .strikethrough(isDone)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.accent.opacity(isDone ? 0.1 : 0.22), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .contextMenu { RowMenu(model: model, row: row, onOpen: onOpen) }
            }
            if rows.count > 3 {
                Text("ещё \(rows.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isToday ? theme.accent.opacity(0.7) : theme.cardStroke)
        }
        .dropDestination(for: PageDragItem.self) { items, _ in
            guard let dateProperty = model.view?.dateProperty else { return false }
            for item in items {
                model.setValue(.date(day), property: dateProperty, row: item.pageId)
            }
            return !items.isEmpty
        }
    }

    private func dateHint(_ table: DataTable) -> some View {
        let candidates = table.properties.filter { $0.type == .date }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Календарю нужно свойство-дата, по которому ставить записи в дни.")
                .foregroundStyle(theme.textSecondary)
            if candidates.isEmpty {
                Button("Добавить свойство «Дата»") { model.addProperty(.date) }
                    .buttonStyle(.borderedProminent)
            } else {
                Menu("Показывать по дате…") {
                    ForEach(candidates) { property in
                        Button(property.name) {
                            let id = property.id
                            model.updateView { $0.dateProperty = id }
                        }
                    }
                }
                .fixedSize()
            }
        }
        .lumenCard()
    }
}
