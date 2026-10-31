import Foundation

/// База данных в духе Notion: набор свойств (колонок) и представлений над строками.
/// Сама база живёт на странице-контейнере (`pageId`), а каждая строка это обычная страница
/// с `databaseId` этой базы: у строки есть свой текст, а значения свойств лежат в `Page.properties`.
/// Название строки это название её страницы, отдельного свойства для него нет.
public struct DataTable: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// Страница, которая показывает эту базу. Строки вложены в неё (`parentId`).
    public var pageId: UUID
    /// Колонки по порядку.
    public var properties: [PropertyDefinition]
    /// Представления: таблица, доска, календарь, список. Порядок как во вкладках.
    public var views: [DataView]
    /// Встроенный шаблон, из которого база сделана, например `tasks`. По нему находится база задач.
    public var template: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        pageId: UUID,
        properties: [PropertyDefinition] = [],
        views: [DataView] = [],
        template: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.pageId = pageId
        self.properties = properties
        self.views = views
        self.template = template
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public func property(_ id: UUID?) -> PropertyDefinition? {
        guard let id else { return nil }
        return properties.first { $0.id == id }
    }

    public func view(_ id: UUID?) -> DataView? {
        guard let id else { return views.first }
        return views.first { $0.id == id } ?? views.first
    }

    /// Первое свойство нужного типа: для доски, календаря и «готово».
    public func firstProperty(of types: Set<PropertyType>) -> PropertyDefinition? {
        properties.first { types.contains($0.type) }
    }
}

// MARK: - Свойства

public enum PropertyType: String, Codable, Sendable, CaseIterable, Identifiable {
    case text
    case number
    case select
    case multiSelect
    /// Выбор с отметкой, какие варианты значат «готово». Им отмечается выполненная задача.
    case status
    case date
    case checkbox
    /// Ссылка на другую страницу Lumen.
    case page

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .text: "Текст"
        case .number: "Число"
        case .select: "Выбор"
        case .multiSelect: "Несколько вариантов"
        case .status: "Статус"
        case .date: "Дата"
        case .checkbox: "Флажок"
        case .page: "Ссылка на страницу"
        }
    }

    /// Значок SF Symbols для заголовка колонки.
    public var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .number: "number"
        case .select: "chevron.down.circle"
        case .multiSelect: "list.bullet"
        case .status: "circle.dashed"
        case .date: "calendar"
        case .checkbox: "checkmark.square"
        case .page: "arrow.up.right.square"
        }
    }

    /// У свойства есть список вариантов.
    public var hasOptions: Bool { self == .select || self == .multiSelect || self == .status }

    /// По свойству можно разложить строки на колонки доски.
    public var canGroup: Bool { self == .select || self == .status || self == .checkbox }
}

/// Вариант выбора: «В работе», «Высокий», «Математика».
public struct SelectOption: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var color: BlockColor
    /// Для статуса: вариант означает, что задача выполнена.
    public var isDone: Bool

    public init(id: UUID = UUID(), name: String, color: BlockColor = .gray, isDone: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.isDone = isDone
    }
}

/// Колонка базы.
public struct PropertyDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var type: PropertyType
    public var options: [SelectOption]

    public init(id: UUID = UUID(), name: String, type: PropertyType, options: [SelectOption] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.options = options
    }

    public func option(_ id: UUID?) -> SelectOption? {
        guard let id else { return nil }
        return options.first { $0.id == id }
    }
}

/// День без времени и часового пояса: срок задачи. Хранится строкой `2026-10-31`,
/// поэтому «сегодня» одинаково на всех устройствах и не съезжает при смене пояса.
public struct DayDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> DayDate {
        DayDate(now, calendar: calendar)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Полдень этого дня: безопасная точка для календарных расчётов.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayDate {
        DayDate(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? date(calendar: calendar), calendar: calendar)
    }

    public static func < (lhs: DayDate, rhs: DayDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = DayDate(string: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Не дата: \(string)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Значение свойства в строке.
public enum PropertyValue: Hashable, Codable, Sendable {
    case text(String)
    case number(Double)
    /// Выбор или статус.
    case option(UUID)
    case options([UUID])
    case date(DayDate)
    case checkbox(Bool)
    case page(UUID)

    /// Пустое значение не хранится вовсе: пустой текст, пустой список.
    public var isEmpty: Bool {
        switch self {
        case .text(let text): text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .options(let ids): ids.isEmpty
        case .checkbox(let isOn): !isOn
        case .number, .option, .date, .page: false
        }
    }

    public var text: String? { if case .text(let value) = self { value } else { nil } }
    public var number: Double? { if case .number(let value) = self { value } else { nil } }
    public var dayDate: DayDate? { if case .date(let value) = self { value } else { nil } }
    public var isChecked: Bool { if case .checkbox(let value) = self { value } else { false } }
    public var pageId: UUID? { if case .page(let value) = self { value } else { nil } }

    /// Выбранные варианты для выбора, статуса и нескольких вариантов.
    public var optionIds: [UUID] {
        switch self {
        case .option(let id): [id]
        case .options(let ids): ids
        default: []
        }
    }
}

/// Значения свойств одной строки по идентификатору свойства.
/// В базе это JSON в колонке `page.properties`: `{"storage": {"<UUID>": значение}}`.
public struct PropertyValues: Hashable, Codable, Sendable {
    public var storage: [String: PropertyValue]

    public init(_ values: [UUID: PropertyValue] = [:]) {
        storage = Dictionary(uniqueKeysWithValues: values.map { ($0.key.uuidString, $0.value) })
    }

    public subscript(id: UUID) -> PropertyValue? {
        get { storage[id.uuidString] }
        set {
            if let newValue, !newValue.isEmpty {
                storage[id.uuidString] = newValue
            } else {
                storage[id.uuidString] = nil
            }
        }
    }

    public var isEmpty: Bool { storage.isEmpty }
}

// MARK: - Представления

public enum DataViewLayout: String, Codable, Sendable, CaseIterable, Identifiable {
    case table
    case board
    case calendar
    case list

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .table: "Таблица"
        case .board: "Доска"
        case .calendar: "Календарь"
        case .list: "Список"
        }
    }

    public var symbolName: String {
        switch self {
        case .table: "tablecells"
        case .board: "rectangle.split.3x1"
        case .calendar: "calendar"
        case .list: "list.bullet.rectangle"
        }
    }
}

/// Условие фильтра. `propertyId == nil` значит название строки.
public struct DataFilter: Identifiable, Hashable, Codable, Sendable {
    public enum Operator: String, Codable, Sendable, CaseIterable {
        /// Совпадает: текст, число, вариант, дата, флажок, страница.
        case equals
        case notEquals
        /// Текст содержит, или среди вариантов есть.
        case contains
        case notContains
        case isEmpty
        case isNotEmpty
        /// Число или дата меньше, не больше, больше, не меньше.
        case less
        case lessOrEqual
        case greater
        case greaterOrEqual
        /// Статус с отметкой «готово» / без неё.
        case isDone
        case isNotDone

        public var title: String {
            switch self {
            case .equals: "равно"
            case .notEquals: "не равно"
            case .contains: "содержит"
            case .notContains: "не содержит"
            case .isEmpty: "пусто"
            case .isNotEmpty: "не пусто"
            case .less: "раньше / меньше"
            case .lessOrEqual: "не позже / не больше"
            case .greater: "позже / больше"
            case .greaterOrEqual: "не раньше / не меньше"
            case .isDone: "готово"
            case .isNotDone: "не готово"
            }
        }

        /// Условию не нужно значение для сравнения.
        public var isUnary: Bool {
            switch self {
            case .isEmpty, .isNotEmpty, .isDone, .isNotDone: true
            default: false
            }
        }

        /// Какие условия подходят свойству.
        public static func available(for type: PropertyType?) -> [Operator] {
            switch type {
            case nil, .text: [.contains, .notContains, .equals, .notEquals, .isEmpty, .isNotEmpty]
            case .number, .date: [.equals, .notEquals, .less, .lessOrEqual, .greater, .greaterOrEqual, .isEmpty, .isNotEmpty]
            case .select: [.equals, .notEquals, .isEmpty, .isNotEmpty]
            case .multiSelect: [.contains, .notContains, .isEmpty, .isNotEmpty]
            case .status: [.equals, .notEquals, .isDone, .isNotDone, .isEmpty, .isNotEmpty]
            case .checkbox: [.equals]
            case .page: [.equals, .notEquals, .isEmpty, .isNotEmpty]
            }
        }
    }

    public var id: UUID
    public var propertyId: UUID?
    public var op: Operator
    public var value: PropertyValue?
    /// Для дат: сравнивать не с днём из `value`, а с «сегодня» плюс столько дней.
    /// Так фильтр «Срок не позже сегодня» работает каждый день, а не только в день создания.
    public var relativeDays: Int?

    public init(id: UUID = UUID(), propertyId: UUID?, op: Operator, value: PropertyValue? = nil, relativeDays: Int? = nil) {
        self.id = id
        self.propertyId = propertyId
        self.op = op
        self.value = value
        self.relativeDays = relativeDays
    }
}

/// Сортировка. `propertyId == nil` значит название строки.
public struct DataSort: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var propertyId: UUID?
    public var ascending: Bool

    public init(id: UUID = UUID(), propertyId: UUID?, ascending: Bool = true) {
        self.id = id
        self.propertyId = propertyId
        self.ascending = ascending
    }
}

/// Представление базы: как показывать строки и какие из них.
public struct DataView: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var layout: DataViewLayout
    /// Все условия должны выполняться одновременно.
    public var filters: [DataFilter]
    /// Без сортировок строки идут в ручном порядке (`Page.sortKey`).
    public var sorts: [DataSort]
    /// Доска и список: по какому свойству раскладывать на группы.
    public var groupBy: UUID?
    /// Календарь: свойство-дата.
    public var dateProperty: UUID?
    /// Свойства, которые не показаны в этом представлении.
    public var hiddenProperties: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        layout: DataViewLayout,
        filters: [DataFilter] = [],
        sorts: [DataSort] = [],
        groupBy: UUID? = nil,
        dateProperty: UUID? = nil,
        hiddenProperties: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.filters = filters
        self.sorts = sorts
        self.groupBy = groupBy
        self.dateProperty = dateProperty
        self.hiddenProperties = hiddenProperties
    }

    public func shows(_ property: PropertyDefinition) -> Bool {
        !hiddenProperties.contains(property.id)
    }
}

// MARK: - Строки и запрос

/// Строка базы: её страница и значения свойств.
public struct DataRow: Identifiable, Hashable, Sendable {
    public var page: Page

    public init(page: Page) {
        self.page = page
    }

    public var id: UUID { page.id }
    public var title: String { page.title }
    public var values: PropertyValues { page.properties ?? PropertyValues() }

    public func value(_ propertyId: UUID) -> PropertyValue? {
        values[propertyId]
    }
}

/// Группа строк на доске: колонка одного варианта или «Без значения».
public struct DataGroup: Identifiable, Hashable, Sendable {
    /// Значение, которое получит строка, если перетащить её в эту группу. `nil` значит пусто.
    public var value: PropertyValue?
    public var option: SelectOption?
    public var title: String
    public var rows: [DataRow]

    public var id: String {
        switch value {
        case nil: "empty"
        case .option(let id): id.uuidString
        case .checkbox(let isOn): isOn ? "checked" : "unchecked"
        case let other?: String(describing: other)
        }
    }
}

/// Фильтры, сортировки и группировки над строками. Чистая логика, проверяется тестами.
/// Базы небольшие (сотни строк), поэтому всё считается в памяти, а не в SQL.
public enum DataQuery {
    /// Строки представления: отфильтрованные и отсортированные.
    public static func rows(_ rows: [DataRow], in table: DataTable, view: DataView, today: DayDate = .today()) -> [DataRow] {
        let filtered = rows.filter { row in
            view.filters.allSatisfy { matches(row, $0, in: table, today: today) }
        }
        return sorted(filtered, by: view.sorts, in: table)
    }

    public static func matches(_ row: DataRow, _ filter: DataFilter, in table: DataTable, today: DayDate = .today()) -> Bool {
        let property = table.property(filter.propertyId)
        // Условие на удалённое свойство ничего не отсекает.
        if filter.propertyId != nil, property == nil { return true }
        let value: PropertyValue? = if let property {
            row.value(property.id)
        } else {
            row.title.isEmpty ? nil : .text(row.title)
        }
        var target = filter.value
        if let days = filter.relativeDays {
            target = .date(today.adding(days: days))
        }

        switch filter.op {
        case .isEmpty:
            return value == nil || value?.isEmpty == true
        case .isNotEmpty:
            return value != nil && value?.isEmpty == false
        case .isDone, .isNotDone:
            let isDone = value?.optionIds.contains { property?.option($0)?.isDone == true } ?? false
            return filter.op == .isDone ? isDone : !isDone
        case .equals, .notEquals:
            let equal: Bool
            if case .checkbox(let wanted)? = target {
                equal = (value?.isChecked ?? false) == wanted
            } else if let text = target?.text {
                equal = (value?.text ?? "").localizedCaseInsensitiveCompare(text) == .orderedSame
            } else {
                equal = value == target
            }
            return filter.op == .equals ? equal : !equal
        case .contains, .notContains:
            let contains: Bool
            switch target {
            case .text(let text)?:
                contains = text.isEmpty || (value?.text ?? "").localizedCaseInsensitiveContains(text)
            case .option(let id)?:
                contains = value?.optionIds.contains(id) ?? false
            case .options(let ids)?:
                contains = !Set(ids).isDisjoint(with: value?.optionIds ?? [])
            default:
                contains = true
            }
            return filter.op == .contains ? contains : !contains
        case .less, .lessOrEqual, .greater, .greaterOrEqual:
            // Пустое значение не проходит сравнение: у задачи без срока нет «просрочено».
            guard let value, let target, let order = compare(value, target) else { return false }
            switch filter.op {
            case .less: return order == .orderedAscending
            case .lessOrEqual: return order != .orderedDescending
            case .greater: return order == .orderedDescending
            default: return order != .orderedAscending
            }
        }
    }

    /// Сравнение двух значений одного типа. `nil`, если сравнивать нечего.
    static func compare(_ lhs: PropertyValue, _ rhs: PropertyValue) -> ComparisonResult? {
        switch (lhs, rhs) {
        case (.number(let a), .number(let b)):
            return a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        case (.date(let a), .date(let b)):
            return a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        case (.text(let a), .text(let b)):
            return a.localizedStandardCompare(b)
        default:
            return nil
        }
    }

    /// Сортирует по очереди по каждому правилу, при равенстве в ручном порядке.
    /// Пустые значения всегда в конце, в какую сторону ни сортируй.
    public static func sorted(_ rows: [DataRow], by sorts: [DataSort], in table: DataTable) -> [DataRow] {
        rows.sorted { lhs, rhs in
            for sort in sorts {
                let property = table.property(sort.propertyId)
                if sort.propertyId != nil, property == nil { continue }
                let a = sortKey(lhs, property)
                let b = sortKey(rhs, property)
                switch (a, b) {
                case (nil, nil): continue
                case (nil, _): return false
                case (_, nil): return true
                case let (a?, b?):
                    let order = compareSortKeys(a, b)
                    if order == .orderedSame { continue }
                    return sort.ascending ? order == .orderedAscending : order == .orderedDescending
                }
            }
            return lhs.page.sortKey < rhs.page.sortKey
        }
    }

    private enum SortValue {
        case number(Double)
        case text(String)
        case date(DayDate)
    }

    private static func sortKey(_ row: DataRow, _ property: PropertyDefinition?) -> SortValue? {
        guard let property else {
            return row.title.isEmpty ? nil : .text(row.title)
        }
        guard let value = row.value(property.id) else { return nil }
        switch value {
        case .text(let text): return .text(text)
        case .number(let number): return .number(number)
        case .date(let day): return .date(day)
        case .checkbox(let isOn): return .number(isOn ? 1 : 0)
        // Варианты сортируются по их порядку в списке вариантов: «Высокий» раньше «Низкого».
        case .option(let id):
            return property.options.firstIndex { $0.id == id }.map { .number(Double($0)) }
        case .options(let ids):
            return ids.compactMap { id in property.options.firstIndex { $0.id == id } }.min().map { .number(Double($0)) }
        case .page(let id): return .text(id.uuidString)
        }
    }

    private static func compareSortKeys(_ a: SortValue, _ b: SortValue) -> ComparisonResult {
        switch (a, b) {
        case (.number(let x), .number(let y)): x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (.date(let x), .date(let y)): x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (.text(let x), .text(let y)): x.localizedStandardCompare(y)
        default: .orderedSame
        }
    }

    /// Колонки доски по свойству `propertyId`: по одной на каждый вариант по порядку и «Без значения» первой,
    /// если такие строки есть. Строки внутри групп в порядке `rows`.
    public static func groups(_ rows: [DataRow], by propertyId: UUID?, in table: DataTable) -> [DataGroup] {
        guard let property = table.property(propertyId) else {
            return [DataGroup(value: nil, option: nil, title: "Все", rows: rows)]
        }
        if property.type == .checkbox {
            return [
                DataGroup(value: nil, option: nil, title: "Не отмечено", rows: rows.filter { !($0.value(property.id)?.isChecked ?? false) }),
                DataGroup(value: .checkbox(true), option: nil, title: "Отмечено", rows: rows.filter { $0.value(property.id)?.isChecked ?? false }),
            ]
        }
        let known = Set(property.options.map(\.id))
        let empty = rows.filter { row in
            !(row.value(property.id)?.optionIds.contains { known.contains($0) } ?? false)
        }
        var groups: [DataGroup] = []
        if !empty.isEmpty {
            groups.append(DataGroup(value: nil, option: nil, title: "Без значения", rows: empty))
        }
        for option in property.options {
            groups.append(DataGroup(
                value: .option(option.id),
                option: option,
                title: option.name,
                rows: rows.filter { $0.value(property.id)?.optionIds.contains(option.id) ?? false }
            ))
        }
        return groups
    }

    /// Строки по дням для календаря. Строки без даты не попадают.
    public static func byDay(_ rows: [DataRow], dateProperty: UUID?) -> [DayDate: [DataRow]] {
        guard let dateProperty else { return [:] }
        var result: [DayDate: [DataRow]] = [:]
        for row in rows {
            if let day = row.value(dateProperty)?.dayDate {
                result[day, default: []].append(row)
            }
        }
        return result
    }

    /// Значения, которые получит новая строка, созданная в этом представлении, чтобы она его не покинула:
    /// например задача, добавленная в колонку «В работе», сразу получает этот статус.
    public static func presetValues(for view: DataView, in table: DataTable, group: DataGroup? = nil, day: DayDate? = nil, today: DayDate = .today()) -> PropertyValues {
        var values = PropertyValues()
        for filter in view.filters {
            guard let property = table.property(filter.propertyId) else { continue }
            switch filter.op {
            case .equals:
                if let value = filter.value { values[property.id] = value }
            case .contains:
                if property.type == .multiSelect, let id = filter.value?.optionIds.first {
                    values[property.id] = .options([id])
                }
            case .lessOrEqual, .greaterOrEqual:
                guard property.type == .date else { break }
                if let days = filter.relativeDays {
                    values[property.id] = .date(today.adding(days: days))
                } else if let value = filter.value {
                    values[property.id] = value
                }
            case .isNotDone:
                if let option = property.options.first(where: { !$0.isDone }) {
                    values[property.id] = .option(option.id)
                }
            default:
                break
            }
        }
        if let group, let property = table.property(view.groupBy) {
            switch group.value {
            case .option(let id)? where property.type == .multiSelect:
                values[property.id] = .options([id])
            default:
                values[property.id] = group.value
            }
        }
        if let day, let property = table.property(view.dateProperty) {
            values[property.id] = .date(day)
        }
        return values
    }
}

// MARK: - Шаблоны

public enum DataTableTemplate {
    public static let tasksKey = "tasks"

    /// Свойства и представления базы «Задачи»: статус, срок, приоритет, проект, ссылка на материал.
    /// Первое представление «Сегодня»: всё, что не сделано и срок которого сегодня или раньше.
    public static func tasks(pageId: UUID) -> DataTable {
        let todo = SelectOption(name: "Не начато", color: .gray)
        let doing = SelectOption(name: "В работе", color: .blue)
        let done = SelectOption(name: "Готово", color: .green, isDone: true)
        let status = PropertyDefinition(name: "Статус", type: .status, options: [todo, doing, done])
        let due = PropertyDefinition(name: "Срок", type: .date)
        let priority = PropertyDefinition(name: "Приоритет", type: .select, options: [
            SelectOption(name: "Высокий", color: .red),
            SelectOption(name: "Средний", color: .yellow),
            SelectOption(name: "Низкий", color: .gray),
        ])
        let project = PropertyDefinition(name: "Проект", type: .multiSelect, options: [
            SelectOption(name: "Учёба", color: .purple),
            SelectOption(name: "Чтение", color: .orange),
            SelectOption(name: "Личное", color: .pink),
        ])
        let material = PropertyDefinition(name: "Материал", type: .page)

        let today = DataView(
            name: "Сегодня",
            layout: .list,
            filters: [
                DataFilter(propertyId: status.id, op: .isNotDone),
                DataFilter(propertyId: due.id, op: .lessOrEqual, relativeDays: 0),
            ],
            sorts: [DataSort(propertyId: due.id), DataSort(propertyId: priority.id)],
            groupBy: nil,
            dateProperty: due.id
        )
        let board = DataView(
            name: "Доска",
            layout: .board,
            sorts: [DataSort(propertyId: priority.id)],
            groupBy: status.id,
            dateProperty: due.id
        )
        let table = DataView(name: "Все задачи", layout: .table, groupBy: status.id, dateProperty: due.id)
        let calendar = DataView(name: "Календарь", layout: .calendar, groupBy: status.id, dateProperty: due.id)

        return DataTable(
            pageId: pageId,
            properties: [status, due, priority, project, material],
            views: [today, board, table, calendar],
            template: tasksKey
        )
    }

    /// Пустая база: одна колонка «Заметка» и представление «Таблица».
    public static func blank(pageId: UUID) -> DataTable {
        let tags = PropertyDefinition(name: "Метки", type: .multiSelect)
        return DataTable(
            pageId: pageId,
            properties: [tags, PropertyDefinition(name: "Заметка", type: .text)],
            views: [DataView(name: "Таблица", layout: .table)]
        )
    }
}
