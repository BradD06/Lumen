import Foundation

/// Простая таблица внутри страницы, как в Notion: ячейки с текстом, строка и столбец
/// заголовков, ширина столбцов. Вся таблица лежит в одном блоке (`BlockContent.table`).
public struct TableData: Hashable, Codable, Sendable {
    /// Строки сверху вниз, в каждой ячейки слева направо. Все строки одной длины.
    public var rows: [[TableCell]]
    /// Первая строка выделена как заголовок.
    public var hasHeaderRow: Bool
    /// Первый столбец выделен как заголовок.
    public var hasHeaderColumn: Bool
    /// Ширина столбцов в пунктах. `nil`: столбцы делят ширину страницы поровну.
    public var columnWidths: [Double]?

    public static let minColumnWidth = 60.0
    public static let maxColumnWidth = 900.0
    /// Самая узкая ширина столбца, когда они делят страницу поровну.
    public static let defaultColumnWidth = 120.0

    public init(rows: [[TableCell]], hasHeaderRow: Bool = true, hasHeaderColumn: Bool = false, columnWidths: [Double]? = nil) {
        self.rows = rows
        self.hasHeaderRow = hasHeaderRow
        self.hasHeaderColumn = hasHeaderColumn
        self.columnWidths = columnWidths
        normalize()
    }

    /// Пустая таблица: по умолчанию три столбца и три строки, первая строка заголовок.
    public static func empty(rows: Int = 3, columns: Int = 3) -> TableData {
        TableData(rows: Array(repeating: Array(repeating: TableCell(), count: max(columns, 1)), count: max(rows, 1)))
    }

    public var rowCount: Int { rows.count }
    public var columnCount: Int { rows.first?.count ?? 0 }

    public func cell(_ row: Int, _ column: Int) -> TableCell {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return TableCell() }
        return rows[row][column]
    }

    public mutating func setCell(_ row: Int, _ column: Int, _ cell: TableCell) {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
        rows[row][column] = cell
    }

    public func isHeader(row: Int, column: Int) -> Bool {
        (hasHeaderRow && row == 0) || (hasHeaderColumn && column == 0)
    }

    // MARK: Строки и столбцы

    public mutating func insertRow(at index: Int) {
        let at = min(max(index, 0), rows.count)
        rows.insert(Array(repeating: TableCell(), count: max(columnCount, 1)), at: at)
    }

    public mutating func insertColumn(at index: Int) {
        let at = min(max(index, 0), columnCount)
        for row in rows.indices {
            rows[row].insert(TableCell(), at: at)
        }
        if var widths = columnWidths {
            widths.insert(Self.defaultColumnWidth, at: min(at, widths.count))
            columnWidths = widths
        }
    }

    /// Последняя строка не удаляется: таблица без строк убирается целиком, как блок.
    public mutating func removeRow(at index: Int) {
        guard rows.count > 1, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    public mutating func removeColumn(at index: Int) {
        guard columnCount > 1, (0..<columnCount).contains(index) else { return }
        for row in rows.indices {
            rows[row].remove(at: index)
        }
        if var widths = columnWidths, widths.indices.contains(index) {
            widths.remove(at: index)
            columnWidths = widths
        }
    }

    public mutating func moveRow(_ index: Int, by offset: Int) {
        let target = index + offset
        guard rows.indices.contains(index), rows.indices.contains(target) else { return }
        rows.swapAt(index, target)
    }

    public mutating func moveColumn(_ index: Int, by offset: Int) {
        let target = index + offset
        guard (0..<columnCount).contains(index), (0..<columnCount).contains(target) else { return }
        for row in rows.indices {
            rows[row].swapAt(index, target)
        }
        if var widths = columnWidths, widths.indices.contains(index), widths.indices.contains(target) {
            widths.swapAt(index, target)
            columnWidths = widths
        }
    }

    /// Ширина столбцов на экране шириной `available`: сохранённые, иначе поровну, но не уже 120.
    public func widths(available: Double) -> [Double] {
        let count = max(columnCount, 1)
        if let columnWidths, columnWidths.count == count {
            return columnWidths.map { min(max($0, Self.minColumnWidth), Self.maxColumnWidth) }
        }
        let share = available > 0 ? available / Double(count) : Self.defaultColumnWidth
        return Array(repeating: max(share, Self.defaultColumnWidth), count: count)
    }

    /// Текст ячеек по строкам: для поиска и оценки высоты.
    public var plainText: String {
        rows.map { $0.map(\.text).joined(separator: "\t") }.joined(separator: "\n")
    }

    /// Строки одной длины, ширины столбцов по их числу. Данные из более новой или
    /// повреждённой версии не ломают таблицу.
    public mutating func normalize() {
        if rows.isEmpty { rows = [[TableCell()]] }
        let count = max(rows.map(\.count).max() ?? 1, 1)
        for row in rows.indices where rows[row].count < count {
            rows[row] += Array(repeating: TableCell(), count: count - rows[row].count)
        }
        if let widths = columnWidths, widths.count != count {
            columnWidths = widths.count > count
                ? Array(widths.prefix(count))
                : widths + Array(repeating: Self.defaultColumnWidth, count: count - widths.count)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case rows, hasHeaderRow, hasHeaderColumn, columnWidths
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decodeIfPresent([[TableCell]].self, forKey: .rows) ?? []
        hasHeaderRow = try container.decodeIfPresent(Bool.self, forKey: .hasHeaderRow) ?? false
        hasHeaderColumn = try container.decodeIfPresent(Bool.self, forKey: .hasHeaderColumn) ?? false
        columnWidths = try container.decodeIfPresent([Double].self, forKey: .columnWidths)
        normalize()
    }
}

/// Ячейка таблицы: текст с оформлением, как у блока.
public struct TableCell: Hashable, Codable, Sendable {
    public var runs: [TextRun]

    public init(runs: [TextRun] = []) {
        self.runs = runs
    }

    public init(text: String) {
        runs = text.isEmpty ? [] : [TextRun(text)]
    }

    public var text: String { runs.map(\.text).joined() }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runs = try container.decodeIfPresent([TextRun].self, forKey: .runs) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case runs
    }
}
