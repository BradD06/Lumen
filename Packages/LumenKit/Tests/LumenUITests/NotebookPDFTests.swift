import CoreGraphics
import Foundation
import PDFKit
import PencilKit
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct NotebookPDFTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    /// PDF из пустых страниц A4.
    private func makePDF(pages: Int) throws -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    private func stroke(at y: CGFloat) -> PKStroke {
        let points = [CGPoint(x: 50, y: y), CGPoint(x: 120, y: y + 10)].enumerated().map { index, location in
            PKStrokePoint(
                location: location, timeOffset: TimeInterval(index) * 0.05, size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    @Test func pdfPagesReplaceAnEmptyNotebook() async throws {
        let page = try await db.createNotebook()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()

        let first = model.insertPDFSheets(from: try makePDF(pages: 5), pages: 1...3, after: 0)
        #expect(first == 0)
        let block = try #require(model.notebookBlock)
        #expect(model.notebookSheetCount == 3, "Пустой лист заменён страницами")
        let backgrounds = try #require(block.content.sheetBackgrounds)
        #expect(backgrounds.map { $0?.page } == [0, 1, 2])
        // Выбранные страницы лежат во вложениях отдельным PDF.
        let name = try #require(backgrounds.first??.attachment)
        let saved = try #require(PDFDocument(url: db.attachments.url(for: name)))
        #expect(saved.pageCount == 3)

        model.undo()
        #expect(model.notebookSheetCount == 1)
        #expect(model.notebookBlock?.content.sheetBackgrounds == nil)
    }

    @Test func pdfPagesGoAfterTheCurrentSheetAndPushTheRestDown() async throws {
        let page = try await db.createNotebook()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        model.addNotebookSheet()
        let block = try #require(model.notebookBlock)
        let secondY = NotebookLayout.sheetRect(1).minY + 60
        model.setDrawing(block.id, data: DrawingSupport.data(of: PKDrawing(strokes: [stroke(at: 60), stroke(at: secondY)])))
        let note = try #require(model.addTextBox(at: CGPoint(x: 80, y: secondY)))

        let first = model.insertPDFSheets(from: try makePDF(pages: 2), pages: 0...1, after: 0)
        #expect(first == 1)
        #expect(model.notebookSheetCount == 4)
        let content = try #require(model.notebookBlock?.content)
        #expect(content.sheetBackgrounds?.map { $0?.page } == [nil, 0, 1])

        // Штрих и текст со второго листа уехали на четвёртый, первый лист на месте.
        let drawing = DrawingSupport.drawing(from: model.notebookBlock?.drawing)
        let sheetsOfInk = drawing.strokes.map { NotebookLayout.sheetIndex(at: $0.renderBounds.midY, sheets: 4) }.sorted()
        #expect(sheetsOfInk == [0, 3])
        let moved = try #require(model.notebookItem(note.id))
        #expect(NotebookLayout.sheetIndex(at: moved.frame.midY, sheets: 4) == 3)

        // Удалили лист со страницей: страница ниже поднялась, текст тоже.
        model.removeNotebookSheet(1)
        #expect(model.notebookBlock?.content.sheetBackgrounds?.map { $0?.page } == [nil, 1])
        let lifted = try #require(model.notebookItem(note.id))
        #expect(NotebookLayout.sheetIndex(at: lifted.frame.midY, sheets: 3) == 2)

        try await Task.sleep(for: .milliseconds(900))
        let saved = try #require(try await db.blocks(of: page.id).first)
        #expect(saved.content.sheetBackgrounds?.map { $0?.page } == [nil, 1])
    }

    @Test func pdfPageImageIsRenderedForASheet() async throws {
        let page = try await db.createNotebook()
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        model.insertPDFSheets(from: try makePDF(pages: 1), pages: 0...0, after: nil)
        let content = try #require(model.notebookBlock?.content)
        let background = try #require(NotebookSheets.background(of: content, sheet: 0))
        let size = try #require(SheetPDFImages.pageSize(background, attachments: db.attachments))
        #expect(abs(size.width - 595) < 1)
        let image = try #require(SheetPDFImages.image(background, attachments: db.attachments, pixelWidth: 300, dark: true))
        #expect(image.width == 512)
    }
}
