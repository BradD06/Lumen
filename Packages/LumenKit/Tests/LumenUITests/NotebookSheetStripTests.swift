import Foundation
import PencilKit
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct NotebookSheetStripTests {
    init() {
        PencilKitTestGuard.install()
    }

    private func stroke(from: CGPoint, to: CGPoint) -> PKStroke {
        let points = [from, to].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.05,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    /// Штрих посередине листа `sheet`.
    private func mark(on sheet: Int, x: CGFloat = 100) -> PKStroke {
        let y = NotebookLayout.sheetRect(sheet).minY + 200
        return stroke(from: CGPoint(x: x, y: y), to: CGPoint(x: x + 50, y: y + 10))
    }

    private func sheetsOf(_ drawing: PKDrawing, count: Int) -> [Int] {
        drawing.strokes.map { NotebookEditing.sheet(ofMidY: $0.renderBounds.midY, sheets: count) }
    }

    /// Тетрадь из трёх листов: на каждом штрих (x = 100, 200, 300), на втором текст и свой шаблон.
    private func threeSheets() async throws -> (AppDatabase, Page, PageEditorModel) {
        let db = try AppDatabase.inMemory()
        let page = try await db.createNotebook()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        model.addNotebookSheet()
        model.addNotebookSheet()
        let block = try #require(model.notebookBlock)
        model.setDrawing(block.id, data: DrawingSupport.data(of: PKDrawing(strokes: [
            mark(on: 0, x: 100), mark(on: 1, x: 200), mark(on: 2, x: 300),
        ])))
        model.setSheetPaper(.cornell, sheet: 1)
        let second = NotebookLayout.sheetRect(1)
        model.addNotebookItem(NotebookItem(kind: .text, frame: CGRect(x: 40, y: second.minY + 300, width: 200, height: 40), text: "Второй"))
        model.setSheetTexts([nil, "почерк второго"])
        return (db, page, model)
    }

    @Test func movingASheetTakesEverythingOnIt() async throws {
        let (_, _, model) = try await threeSheets()
        model.moveNotebookSheet(from: 1, to: 2)

        let drawing = DrawingSupport.drawing(from: model.notebookBlock?.drawing)
        // Штрих второго листа (x = 200) теперь на третьем, третьего на втором.
        let byX = Dictionary(uniqueKeysWithValues: drawing.strokes.map {
            (Int($0.renderBounds.midX / 100), NotebookEditing.sheet(ofMidY: $0.renderBounds.midY, sheets: 3))
        })
        #expect(byX[1] == 0)
        #expect(byX[2] == 2)
        #expect(byX[3] == 1)
        #expect(model.sheetPaper(2) == .cornell)
        #expect(model.sheetPaper(1) == .lined)
        let item = try #require(model.notebookItems.first)
        #expect(NotebookEditing.sheet(ofMidY: item.frame.midY, sheets: 3) == 2)
        #expect(model.notebookBlock?.content.sheetTexts == [nil, nil, "почерк второго"])

        model.undo()
        #expect(model.sheetPaper(1) == .cornell)
        #expect(model.notebookBlock?.content.sheetTexts == [nil, "почерк второго"])
    }

    @Test func duplicatingASheetCopiesItRightAfterIt() async throws {
        let (_, _, model) = try await threeSheets()
        let copy = model.duplicateNotebookSheet(1)
        #expect(copy == 2)
        #expect(model.notebookSheetCount == 4)
        let drawing = DrawingSupport.drawing(from: model.notebookBlock?.drawing)
        #expect(drawing.strokes.count == 4)
        #expect(sheetsOf(drawing, count: 4).sorted() == [0, 1, 2, 3])
        #expect(model.sheetPaper(2) == .cornell)
        #expect(model.notebookItems.count == 2)
        #expect(Set(model.notebookItems.map(\.id)).count == 2)
        #expect(model.notebookBlock?.content.sheetTexts == [nil, "почерк второго", "почерк второго"])

        // Копия это один шаг истории.
        model.undo()
        #expect(model.notebookSheetCount == 3)
        #expect(DrawingSupport.drawing(from: model.notebookBlock?.drawing).strokes.count == 3)
    }

    @Test func recognizedHandwritingFollowsSheetsAndIsSearchable() async throws {
        let (db, page, model) = try await threeSheets()
        model.addNotebookSheet(after: 0)
        #expect(model.notebookBlock?.content.sheetTexts == [nil, nil, "почерк второго"])
        model.removeNotebookSheet(1)
        #expect(model.notebookBlock?.content.sheetTexts == [nil, "почерк второго"])

        await model.flush()
        let found = try await db.search("почерк")
        #expect(found.map(\.pageId) == [page.id])
        let byTextBox = try await db.search("Второй")
        #expect(byTextBox.map(\.pageId) == [page.id])
    }

    @Test func readerKeepsStoredTextsOnOpenAndForgetsEmptySheets() async throws {
        let content = BlockContent(sheetCount: 3, sheetTexts: ["первый", "был текст", "третий"])
        // Чернила только на первом и третьем листе: второй стёрли.
        let drawing = PKDrawing(strokes: [mark(on: 0), mark(on: 2)])
        let reader = HandwritingReader()
        let texts = await reader.read(drawing: drawing, content: content)
        #expect(texts == ["первый", nil, "третий"])
        // Ничего не поменялось: ответ пустой.
        let again = await reader.read(drawing: drawing, content: BlockContent(sheetCount: 3, sheetTexts: ["первый", nil, "третий"]))
        #expect(again == nil)
    }

    @Test func dragTokensOnlyComeFromSheets() {
        #expect(SheetDragToken.sheet(from: SheetDragToken.text(for: 7)) == 7)
        #expect(SheetDragToken.sheet(from: "7") == nil)
        #expect(SheetDragToken.sheet(from: "просто текст") == nil)
    }
}
