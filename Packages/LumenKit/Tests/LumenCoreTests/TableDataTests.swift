import Foundation
import Testing
@testable import LumenCore

struct TableDataTests {
    private func texts(_ table: TableData) -> [[String]] {
        table.rows.map { $0.map(\.text) }
    }

    @Test func emptyTableHasHeaderRow() {
        let table = TableData.empty()
        #expect(table.rowCount == 3)
        #expect(table.columnCount == 3)
        #expect(table.hasHeaderRow)
        #expect(table.isHeader(row: 0, column: 2))
        #expect(!table.isHeader(row: 1, column: 0))
    }

    @Test func rowsAndColumnsChange() {
        var table = TableData(rows: [[TableCell(text: "а"), TableCell(text: "б")], [TableCell(text: "в"), TableCell(text: "г")]])
        table.insertRow(at: 1)
        #expect(texts(table) == [["а", "б"], ["", ""], ["в", "г"]])
        table.insertColumn(at: 0)
        #expect(texts(table) == [["", "а", "б"], ["", "", ""], ["", "в", "г"]])
        table.removeColumn(at: 0)
        table.removeRow(at: 1)
        #expect(texts(table) == [["а", "б"], ["в", "г"]])
        table.moveRow(1, by: -1)
        table.moveColumn(0, by: 1)
        #expect(texts(table) == [["г", "в"], ["б", "а"]])
        table.removeRow(at: 0)
        table.removeRow(at: 0)
        #expect(table.rowCount == 1, "Последняя строка остаётся")
    }

    @Test func widthsFollowColumns() {
        var table = TableData.empty(rows: 1, columns: 2)
        #expect(table.widths(available: 600) == [300, 300])
        #expect(table.widths(available: 100) == [TableData.defaultColumnWidth, TableData.defaultColumnWidth])
        table.columnWidths = [200, 10]
        #expect(table.widths(available: 600) == [200, TableData.minColumnWidth])
        table.insertColumn(at: 2)
        #expect(table.columnWidths?.count == 3)
        table.removeColumn(at: 0)
        #expect(table.columnWidths == [10, TableData.defaultColumnWidth])
    }

    @Test func raggedDataIsRepaired() throws {
        let json = #"{"rows":[[{"runs":[{"text":"а","marks":[]}]}],[]],"columnWidths":[100,100,100]}"#
        let table = try JSONDecoder().decode(TableData.self, from: Data(json.utf8))
        #expect(table.rowCount == 2)
        #expect(table.columnCount == 1)
        #expect(table.columnWidths == [100])
        #expect(!table.hasHeaderRow)
    }

    @Test func tableGoesToMarkdownAndSearch() {
        var content = BlockContent()
        content.table = TableData(rows: [[TableCell(text: "Имя"), TableCell(text: "a|b")], [TableCell(text: "Лев"), TableCell(text: "")]])
        #expect(content.searchText == "Имя\ta|b\nЛев\t")
        let block = Block(pageId: UUID(), type: .table, content: content, sortKey: "a")
        let page = Page(title: "Т", sortKey: "a")
        let markdown = PageExport(page: page, blocks: [block]).markdown(includesTitle: false)
        #expect(markdown == "| Имя | a\\|b |\n| --- | --- |\n| Лев |  |\n")
    }
}
