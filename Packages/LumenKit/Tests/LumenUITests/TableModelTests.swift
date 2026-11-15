import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct TableModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func openTable() async throws -> (PageEditorModel, UUID) {
        let page = try await db.createQuickNote("Страница\nа")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let id = model.blocks[0].id
        model.setType(id, .table)
        return (model, id)
    }

    @Test func slashMenuMakesTableAndFocusesFirstCell() async throws {
        let (model, id) = try await openTable()
        #expect(model.findBlock(id)?.type == .table)
        #expect(model.table(of: id)?.rowCount == 3)
        #expect(model.cellFocusRequest == TableCellFocus(blockId: id, row: 0, column: 0))
        #expect(model.children(of: nil).last?.type == .paragraph, "Под таблицей абзац, чтобы писать дальше")
    }

    @Test func typingInCellsIsSavedAndUndone() async throws {
        let (model, id) = try await openTable()
        model.updateTableCell(id, row: 1, column: 2, source: "**жирно**")
        #expect(model.table(of: id)?.cell(1, 2).runs == [TextRun("жирно", marks: [.bold])])
        await model.flush()
        let saved = try await db.blocks(of: model.pageId).first { $0.id == id }
        #expect(saved?.content.table?.cell(1, 2).text == "жирно")
        model.undo()
        #expect(model.table(of: id)?.cell(1, 2).text == "")
    }

    @Test func tabWalksCellsAndAddsRowAtTheEnd() async throws {
        let (model, id) = try await openTable()
        model.moveTableFocus(id, row: 0, column: 2, direction: .next)
        #expect(model.cellFocusRequest == TableCellFocus(blockId: id, row: 1, column: 0))
        model.moveTableFocus(id, row: 1, column: 0, direction: .previous)
        #expect(model.cellFocusRequest == TableCellFocus(blockId: id, row: 0, column: 2))
        model.moveTableFocus(id, row: 2, column: 2, direction: .next)
        #expect(model.table(of: id)?.rowCount == 4)
        #expect(model.cellFocusRequest == TableCellFocus(blockId: id, row: 3, column: 0))
    }

    @Test func returnInLastRowLeavesTable() async throws {
        let (model, id) = try await openTable()
        model.cellFocusRequest = nil
        model.moveTableFocus(id, row: 2, column: 1, direction: .down)
        #expect(model.cellFocusRequest == nil)
        let below = try #require(model.children(of: nil).last)
        #expect(model.focusRequest == below.id)
    }

    @Test func structureChangesAreOneUndoStep() async throws {
        let (model, id) = try await openTable()
        model.insertTableColumn(id, at: 1)
        #expect(model.table(of: id)?.columnCount == 4)
        model.toggleTableHeaderColumn(id)
        #expect(model.table(of: id)?.hasHeaderColumn == true)
        model.setTableColumnWidths(id, [10, 200, 300, 2000])
        #expect(model.table(of: id)?.columnWidths == [TableData.minColumnWidth, 200, 300, TableData.maxColumnWidth])
        model.undo()
        model.undo()
        #expect(model.table(of: id)?.hasHeaderColumn == false)
        #expect(model.table(of: id)?.columnCount == 4)
    }
}
