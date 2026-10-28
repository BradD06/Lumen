import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct BlockTreeTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func open(_ lines: String) async throws -> (PageEditorModel, UUID, [UUID]) {
        let page = try await db.createQuickNote("Страница\n" + lines)
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        return (model, page.id, model.blocks.map(\.id))
    }

    private func texts(_ model: PageEditorModel, in parent: UUID?) -> [String] {
        model.children(of: parent).map(\.text)
    }

    @Test func indentAndOutdent() async throws {
        let (model, pageId, ids) = try await open("а\nб\nв")

        #expect(!model.canIndent(ids[0]), "Первый блок вкладывать некуда")
        model.indent(ids[1])
        model.indent(ids[2])
        #expect(texts(model, in: nil) == ["а"])
        #expect(texts(model, in: ids[0]) == ["б", "в"])
        #expect(model.blocks.map(\.text) == ["а", "б", "в"], "Порядок документа не меняется")

        await model.flush()
        let saved = try await db.blocks(of: pageId)
        #expect(saved.first { $0.id == ids[2] }?.parentBlockId == ids[0])

        model.outdent(ids[1])
        #expect(texts(model, in: nil) == ["а", "б"])
        #expect(texts(model, in: ids[0]) == ["в"])

        model.undo()
        #expect(texts(model, in: ids[0]) == ["б", "в"])
    }

    @Test func emptyNestedBlockOutdentsOnBackspaceAndReturn() async throws {
        let (model, _, ids) = try await open("а\nб")
        model.indent(ids[1])
        model.updateText(ids[1], to: "")

        #expect(model.backspaceInEmptyBlock(ids[1]))
        #expect(texts(model, in: nil) == ["а", ""])

        model.updateText(ids[0], to: "- а")
        model.indent(ids[1])
        model.setType(ids[1], .bulletedList)
        model.submit(ids[1])
        #expect(model.children(of: nil).map(\.id) == [ids[0], ids[1]], "Return в пустом вложенном пункте выносит его наверх")
    }

    @Test func backspaceDeletesEmptyBlock() async throws {
        let (model, pageId, ids) = try await open("а\nб\nв")
        model.updateText(ids[1], to: "")

        #expect(model.backspaceInEmptyBlock(ids[1]))
        #expect(texts(model, in: nil) == ["а", "в"])
        #expect(model.focusRequest == ids[0], "Курсор переходит в блок выше")

        model.updateText(ids[0], to: "")
        #expect(model.backspaceInEmptyBlock(ids[0]), "Первый пустой блок тоже удаляется")
        #expect(texts(model, in: nil) == ["в"])
        #expect(model.focusTitleRequest, "Выше блоков нет, курсор уходит в заголовок")

        model.updateText(ids[2], to: "")
        #expect(!model.backspaceInEmptyBlock(ids[2]), "Единственный блок остаётся")

        await model.flush()
        #expect(try await db.blocks(of: pageId).count == 1)
    }

    @Test func returnInCodeBlockAddsLineAndDoubleReturnLeaves() async throws {
        let (model, _, ids) = try await open("let a = 1")
        model.setType(ids[0], .code)

        model.submit(ids[0])
        #expect(texts(model, in: nil) == ["let a = 1\n"], "Return переносит строку внутри кода")
        model.updateText(ids[0], to: "let a = 1\nlet b = 2")
        model.submit(ids[0])
        model.submit(ids[0])

        let top = model.children(of: nil)
        #expect(top.map(\.text) == ["let a = 1\nlet b = 2", ""], "Второй Return создаёт блок ниже")
        #expect(top.map(\.type) == [.code, .paragraph])
        #expect(model.focusRequest == top[1].id)
    }

    @Test func doubleNewlineTypedInCodeBlockLeavesIt() async throws {
        let (model, _, ids) = try await open("x")
        model.setType(ids[0], .code)
        model.updateText(ids[0], to: "x\n")
        model.updateText(ids[0], to: "x\n\n")

        #expect(model.children(of: nil).map(\.text) == ["x", ""])
    }

    @Test func returnInsideOpenToggleCreatesChild() async throws {
        let (model, _, ids) = try await open("Раздел")
        model.setType(ids[0], .toggle)
        model.updateText(ids[0], to: "Раздел\nвнутри")

        #expect(texts(model, in: ids[0]) == ["внутри"])
        #expect(texts(model, in: nil) == ["Раздел"])

        model.toggleCollapsed(ids[0])
        #expect(model.findBlock(ids[0])?.content.isCollapsed == true)
    }

    @Test func deletingParentDeletesChildren() async throws {
        let (model, pageId, ids) = try await open("а\nб\nв")
        model.indent(ids[1])
        await model.flush()

        model.deleteBlock(ids[0])
        #expect(model.blocks.map(\.text) == ["в"])
        await model.flush()
        #expect(try await db.blocks(of: pageId).map(\.text) == ["в"])

        model.undo()
        await model.flush()
        let restored = try await db.blocks(of: pageId)
        #expect(Set(restored.map(\.text)) == ["а", "б", "в"])
        #expect(restored.first { $0.id == ids[1] }?.parentBlockId == ids[0])
    }

    @Test func columnsAppearAndDisappear() async throws {
        let (model, pageId, ids) = try await open("а\nб\nв")

        model.placeBeside(ids[1], ids[0])
        let row = try #require(model.children(of: nil).first)
        #expect(row.type == .columnList)
        let columns = model.children(of: row.id)
        #expect(columns.count == 2)
        #expect(texts(model, in: columns[0].id) == ["а"])
        #expect(texts(model, in: columns[1].id) == ["б"])
        #expect(model.children(of: nil).map(\.text) == ["", "в"])

        // Третья колонка справа от «б».
        model.placeBeside(ids[2], ids[1])
        #expect(model.children(of: row.id).count == 3)

        await model.flush()
        #expect(try await db.blocks(of: pageId).count == 7)

        // Вынесли блоки из колонок: пустые колонки исчезают, ряд из одной колонки разворачивается.
        model.moveBlock(ids[2], nextTo: row.id, after: true)
        model.moveBlock(ids[1], nextTo: ids[2], after: true)
        #expect(model.children(of: nil).map(\.id) == [ids[0], ids[2], ids[1]])
        #expect(!model.blocks.contains { $0.type.isLayout })

        await model.flush()
        #expect(try await db.blocks(of: pageId).map(\.id).sorted { $0.uuidString < $1.uuidString }
            == ids.sorted { $0.uuidString < $1.uuidString })
    }

    @Test func placeBesidePreviousFromMenu() async throws {
        let (model, _, ids) = try await open("а\nб")
        #expect(model.previousSibling(of: ids[0]) == nil)
        model.placeBesidePrevious(ids[1])

        let row = try #require(model.children(of: nil).first)
        #expect(row.type == .columnList)
        #expect(model.children(of: row.id).map { texts(model, in: $0.id) } == [["а"], ["б"]])
    }

    @Test func columnWidthsAreSaved() async throws {
        let (model, pageId, ids) = try await open("а\nб\nв")
        model.placeBeside(ids[1], ids[0])
        let row = try #require(model.children(of: nil).first)
        #expect(model.columnFractions(row.id) == [0.5, 0.5])

        model.setColumnFractions(row.id, [0.7, 0.3])
        #expect(model.columnFractions(row.id).map { ($0 * 100).rounded() } == [70, 30])

        // Новая колонка без своей ширины получает среднюю долю, сумма остаётся 1.
        model.placeBeside(ids[2], ids[1])
        let fractions = model.columnFractions(row.id)
        #expect(fractions.count == 3)
        #expect(abs(fractions.reduce(0, +) - 1) < 0.0001)

        await model.flush()
        let saved = try await db.blocks(of: pageId).filter { $0.type == .column }
        #expect(saved.compactMap(\.content.columnWidth).count == 2)
    }

    @Test func duplicateCopiesSubtree() async throws {
        let (model, pageId, ids) = try await open("а\nб")
        model.indent(ids[1])
        model.duplicateBlock(ids[0])

        let top = model.children(of: nil)
        #expect(top.map(\.text) == ["а", "а"])
        #expect(top[1].id != ids[0])
        #expect(texts(model, in: top[1].id) == ["б"])

        await model.flush()
        #expect(try await db.blocks(of: pageId).count == 4)
    }

    @Test func colorsAreSaved() async throws {
        let (model, pageId, ids) = try await open("важно")
        model.setTextColor(ids[0], .red)
        model.setBackgroundColor(ids[0], .yellow)
        await model.flush()

        let saved = try #require(try await db.blocks(of: pageId).first)
        #expect(saved.content.backgroundColor == .yellow)
        #expect(saved.content.textColor == .red, "Цвет текста и фон задаются вместе")
    }

    @Test func numberingRestartsInsideNestedList() async throws {
        let (model, _, ids) = try await open("раз\nдва\nвложенный\nтри")
        for id in ids {
            model.setType(id, .numberedList)
        }
        model.indent(ids[2])
        #expect(model.listNumber(for: ids[1]) == 2)
        #expect(model.listNumber(for: ids[2]) == 1)
        #expect(model.listNumber(for: ids[3]) == 3)
    }
}
