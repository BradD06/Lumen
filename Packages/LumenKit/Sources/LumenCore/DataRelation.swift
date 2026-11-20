import Foundation

// MARK: - Настройки связи и сводки

/// Колонка «Связь с базой»: строки этой базы ссылаются на строки базы `targetTableId`.
/// Значение в строке `PropertyValue.pages` с идентификаторами страниц-строк той базы.
public struct RelationConfig: Hashable, Codable, Sendable {
    /// База, на строки которой ссылается колонка. Может быть та же база.
    public var targetTableId: UUID
    /// Обратная колонка в той базе: связь двусторонняя, и обе колонки всегда согласованы.
    /// `nil` значит связь видна только здесь.
    public var pairedPropertyId: UUID?

    public init(targetTableId: UUID, pairedPropertyId: UUID? = nil) {
        self.targetTableId = targetTableId
        self.pairedPropertyId = pairedPropertyId
    }

    public var isTwoWay: Bool { pairedPropertyId != nil }
}

/// Колонка «Сводка по связи»: берёт колонку связанных строк и что-то по ней считает.
public struct RollupConfig: Hashable, Codable, Sendable {
    /// Колонка-связь этой базы.
    public var relationPropertyId: UUID?
    /// Колонка в связанной базе. `nil` значит название строки.
    public var targetPropertyId: UUID?
    public var function: RollupFunction

    public init(relationPropertyId: UUID? = nil, targetPropertyId: UUID? = nil, function: RollupFunction = .count) {
        self.relationPropertyId = relationPropertyId
        self.targetPropertyId = targetPropertyId
        self.function = function
    }
}

/// Что сводка считает по связанным строкам.
public enum RollupFunction: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Значения через запятую.
    case showOriginal
    /// Сколько связанных строк.
    case count
    /// Сколько строк с заполненным значением.
    case countValues
    /// Сколько разных значений.
    case countUnique
    case sum
    case average
    case min
    case max
    case earliest
    case latest
    /// Сколько строк отмечено флажком или статусом «готово».
    case countDone
    /// Какая доля строк готова, в процентах.
    case percentDone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .showOriginal: "Показать значения"
        case .count: "Количество строк"
        case .countValues: "Заполнено"
        case .countUnique: "Разных значений"
        case .sum: "Сумма"
        case .average: "Среднее"
        case .min: "Наименьшее"
        case .max: "Наибольшее"
        case .earliest: "Самая ранняя дата"
        case .latest: "Самая поздняя дата"
        case .countDone: "Готово, штук"
        case .percentDone: "Готово, %"
        }
    }

    /// Результат показывают со знаком процента.
    public var isPercent: Bool { self == .percentDone }

    /// Что имеет смысл считать по колонке такого типа. `nil` значит название строки.
    public static func available(for type: PropertyType?) -> [RollupFunction] {
        let common: [RollupFunction] = [.count, .countValues, .countUnique, .showOriginal]
        switch type {
        case .number?: return common + [.sum, .average, .min, .max]
        case .date?: return common + [.earliest, .latest]
        case .checkbox?, .status?: return common + [.countDone, .percentDone]
        case .formula?, .rollup?: return common + [.sum, .average, .min, .max, .earliest, .latest]
        default: return common
        }
    }
}

// MARK: - Связанные строки

/// Строки баз, на которые ссылаются связи открытой базы: из них считаются сводки,
/// по ним показываются названия связанных строк и выбираются новые.
public struct RelationContext: Hashable, Sendable {
    /// Связанные базы по идентификатору.
    public var tables: [UUID: DataTable]
    /// Названия связанных баз (названия их страниц).
    public var tableTitles: [UUID: String]
    /// Живые строки каждой связанной базы в ручном порядке, с посчитанными формулами.
    public let rows: [UUID: [DataRow]]
    private var index: [UUID: DataRow]

    public static let empty = RelationContext()

    public init(tables: [UUID: DataTable] = [:], tableTitles: [UUID: String] = [:], rows: [UUID: [DataRow]] = [:]) {
        self.tables = tables
        self.tableTitles = tableTitles
        self.rows = rows
        var index: [UUID: DataRow] = [:]
        for list in rows.values {
            for row in list { index[row.id] = row }
        }
        self.index = index
    }

    /// Живая строка любой связанной базы. Строки в корзине сюда не попадают, поэтому
    /// связь с удалённой строкой просто не видна, а после восстановления появляется снова.
    public func row(_ id: UUID) -> DataRow? { index[id] }

    /// Связанные строки значения, только живые и только из нужной базы.
    public func linkedRows(_ value: PropertyValue?, in tableId: UUID?) -> [DataRow] {
        guard let value else { return [] }
        var seen = Set<UUID>()
        return value.pageIds.compactMap { id in
            guard seen.insert(id).inserted, let row = index[id] else { return nil }
            if let tableId, row.page.databaseId != tableId { return nil }
            return row
        }
    }
}

// MARK: - Сводки

public enum Rollup {
    /// Значения колонок-сводок дописываются в строки (только в памяти, как у формул).
    public static func computed(_ rows: [DataRow], in table: DataTable, relations: RelationContext) -> [DataRow] {
        let rollups = table.properties.filter { $0.type == .rollup }
        guard !rollups.isEmpty else { return rows }
        return rows.map { row in
            var row = row
            var values = row.values
            for property in rollups {
                values[property.id] = value(of: property, row: row, table: table, relations: relations)
            }
            row.page.properties = values
            return row
        }
    }

    /// Значение одной сводки для строки. `nil`, если сводка не настроена или считать нечего.
    public static func value(of property: PropertyDefinition, row: DataRow, table: DataTable, relations: RelationContext) -> PropertyValue? {
        guard let config = property.rollup,
              let relation = table.property(config.relationPropertyId),
              relation.type == .relation,
              let targetTableId = relation.relation?.targetTableId else { return nil }
        let related = relations.linkedRows(row.value(relation.id), in: targetTableId)
        let target: PropertyDefinition?
        if let id = config.targetPropertyId {
            // Колонку в той базе удалили: считать нечего.
            guard let found = relations.tables[targetTableId]?.property(id) else { return nil }
            target = found
        } else {
            target = nil
        }
        return compute(config.function, rows: related, target: target)
    }

    /// Чистый расчёт по уже найденным связанным строкам.
    public static func compute(_ function: RollupFunction, rows: [DataRow], target: PropertyDefinition?) -> PropertyValue? {
        let values: [PropertyValue?] = rows.map { row in
            guard let target else { return row.title.isEmpty ? nil : .text(row.title) }
            return row.value(target.id)
        }
        let filled = values.compactMap { $0 }.filter { !$0.isEmpty }
        let numbers = filled.compactMap(\.number)
        let days = filled.compactMap(\.dayDate)

        switch function {
        case .showOriginal:
            let texts = values.compactMap { $0.flatMap { displayText($0, property: target) } }.filter { !$0.isEmpty }
            return texts.isEmpty ? nil : .text(texts.joined(separator: ", "))
        case .count:
            return .number(Double(rows.count))
        case .countValues:
            return .number(Double(filled.count))
        case .countUnique:
            let unique = Set(filled.compactMap { displayText($0, property: target) })
            return .number(Double(unique.count))
        case .sum:
            return .number(numbers.reduce(0, +))
        case .average:
            return numbers.isEmpty ? nil : .number(numbers.reduce(0, +) / Double(numbers.count))
        case .min:
            return numbers.min().map(PropertyValue.number)
        case .max:
            return numbers.max().map(PropertyValue.number)
        case .earliest:
            return days.min().map(PropertyValue.date)
        case .latest:
            return days.max().map(PropertyValue.date)
        case .countDone:
            return .number(Double(values.filter { isDone($0, property: target) }.count))
        case .percentDone:
            guard !rows.isEmpty else { return nil }
            let done = values.filter { isDone($0, property: target) }.count
            let percent = Double(done) / Double(rows.count) * 100
            return .number((percent * 10).rounded() / 10)
        }
    }

    /// Флажок отмечен или статус с отметкой «готово».
    static func isDone(_ value: PropertyValue?, property: PropertyDefinition?) -> Bool {
        guard let value else { return false }
        if value.isChecked { return true }
        guard let property else { return false }
        return value.optionIds.contains { property.option($0)?.isDone == true }
    }

    /// Значение текстом: «Высокий», «31.10.2026», «да». Для сводки «Показать значения» и подсчёта разных.
    public static func displayText(_ value: PropertyValue, property: PropertyDefinition?) -> String? {
        switch value {
        case .text(let text): return text
        case .number(let number): return Formula.format(number)
        case .option(let id): return property?.option(id)?.name
        case .options(let ids):
            let names = ids.compactMap { property?.option($0)?.name }
            return names.isEmpty ? nil : names.joined(separator: ", ")
        case .date(let day): return FormulaValue.date(day).displayText
        case .checkbox(let isOn): return isOn ? "да" : "нет"
        case .page, .pages: return nil
        }
    }
}

// MARK: - Двусторонняя связь

public enum DataRelation {
    /// Какие строки другой базы нужно поправить, когда значение связи сменилось со `old` на `new`:
    /// в добавленных дописать эту строку, из убранных её вычеркнуть.
    public static func changes(old: PropertyValue?, new: PropertyValue?) -> (added: [UUID], removed: [UUID]) {
        let before = old?.pageIds ?? []
        let after = new?.pageIds ?? []
        let beforeSet = Set(before)
        let afterSet = Set(after)
        var seen = Set<UUID>()
        let added = after.filter { !beforeSet.contains($0) && seen.insert($0).inserted }
        let removed = before.filter { !afterSet.contains($0) && seen.insert($0).inserted }
        return (added, removed)
    }

    /// Значение связи, в которое дописали (`adding == true`) или из которого убрали строку `id`.
    /// Порядок остальных строк не меняется, повторов не бывает.
    public static func updating(_ value: PropertyValue?, with id: UUID, adding: Bool) -> PropertyValue? {
        var ids = value?.pageIds ?? []
        if adding {
            guard !ids.contains(id) else { return value }
            ids.append(id)
        } else {
            ids.removeAll { $0 == id }
        }
        return ids.isEmpty ? nil : .pages(ids)
    }

    /// Значение связи без повторов: так его и хранят.
    public static func normalized(_ ids: [UUID]) -> PropertyValue? {
        var seen = Set<UUID>()
        let unique = ids.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : .pages(unique)
    }
}
