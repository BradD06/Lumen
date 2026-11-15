import Foundation
import LumenCore

/// Ячейка таблицы, куда перевести курсор.
struct TableCellFocus: Equatable {
    var blockId: UUID
    var row: Int
    var column: Int
}

/// Правки блока «Таблица»: текст ячеек, строки и столбцы, шапка, ширина столбцов.
extension PageEditorModel {
    enum TableMove {
        /// Tab: следующая ячейка, после последней новая строка.
        case next
        /// ⇧Tab: предыдущая ячейка.
        case previous
        /// Return: ячейка ниже, из последней строки курсор выходит под таблицу.
        case down
    }

    func table(of id: UUID) -> TableData? {
        guard let block = findBlock(id), block.type == .table else { return nil }
        return block.content.table ?? .empty()
    }

    /// Правка устройства таблицы одним шагом отмены.
    func updateTable(_ id: UUID, _ change: (inout TableData) -> Void) {
        guard let block = findBlock(id), block.type == .table else { return }
        var table = block.content.table ?? .empty()
        change(&table)
        table.normalize()
        guard table != block.content.table else { return }
        recordUndo()
        update(id) { $0.content.table = table }
    }

    /// Набор в ячейке: разметка `InlineMarkup`, как в тексте блока. Набор подряд отменяется одним шагом.
    func updateTableCell(_ id: UUID, row: Int, column: Int, source: String) {
        guard var table = table(of: id) else { return }
        let runs = InlineMarkup.runs(from: source)
        guard InlineMarkup.normalized(table.cell(row, column).runs) != runs else { return }
        recordUndo(typing: .cell(id, row, column))
        table.setCell(row, column, TableCell(runs: runs))
        update(id) { $0.content.table = table }
    }

    func moveTableFocus(_ id: UUID, row: Int, column: Int, direction: TableMove) {
        guard let table = table(of: id) else { return }
        var row = row
        var column = column
        switch direction {
        case .next:
            column += 1
            if column >= table.columnCount {
                column = 0
                row += 1
            }
            if row >= table.rowCount {
                updateTable(id) { $0.insertRow(at: table.rowCount) }
            }
        case .previous:
            column -= 1
            if column < 0 {
                column = table.columnCount - 1
                row -= 1
            }
            guard row >= 0 else { return }
        case .down:
            row += 1
            if row >= table.rowCount {
                leaveTable(id)
                return
            }
        }
        cellFocusRequest = TableCellFocus(blockId: id, row: row, column: column)
    }

    /// Курсор под таблицу: в следующий блок с текстом или в новый абзац.
    func leaveTable(_ id: UUID) {
        guard let block = findBlock(id) else { return }
        let siblings = children(of: block.parentBlockId)
        if let index = siblings.firstIndex(where: { $0.id == id }), index + 1 < siblings.count,
           siblings[index + 1].type.hasText {
            focusRequest = siblings[index + 1].id
        } else {
            recordUndo()
            focusRequest = insertBlock(after: id, type: .paragraph).id
        }
    }

    func insertTableRow(_ id: UUID, at index: Int, focusColumn: Int? = nil) {
        updateTable(id) { $0.insertRow(at: index) }
        if let focusColumn {
            cellFocusRequest = TableCellFocus(blockId: id, row: index, column: focusColumn)
        }
    }

    func insertTableColumn(_ id: UUID, at index: Int, focusRow: Int? = nil) {
        updateTable(id) { $0.insertColumn(at: index) }
        if let focusRow {
            cellFocusRequest = TableCellFocus(blockId: id, row: focusRow, column: index)
        }
    }

    func removeTableRow(_ id: UUID, at index: Int) {
        updateTable(id) { $0.removeRow(at: index) }
    }

    func removeTableColumn(_ id: UUID, at index: Int) {
        updateTable(id) { $0.removeColumn(at: index) }
    }

    func moveTableRow(_ id: UUID, _ index: Int, by offset: Int) {
        updateTable(id) { $0.moveRow(index, by: offset) }
    }

    func moveTableColumn(_ id: UUID, _ index: Int, by offset: Int) {
        updateTable(id) { $0.moveColumn(index, by: offset) }
    }

    func toggleTableHeaderRow(_ id: UUID) {
        updateTable(id) { $0.hasHeaderRow.toggle() }
    }

    func toggleTableHeaderColumn(_ id: UUID) {
        updateTable(id) { $0.hasHeaderColumn.toggle() }
    }

    /// Ширина столбцов после перетаскивания границы. `nil` возвращает ровные столбцы.
    func setTableColumnWidths(_ id: UUID, _ widths: [Double]?) {
        updateTable(id) { table in
            table.columnWidths = widths?.map { min(max($0, TableData.minColumnWidth), TableData.maxColumnWidth) }
        }
    }
}
