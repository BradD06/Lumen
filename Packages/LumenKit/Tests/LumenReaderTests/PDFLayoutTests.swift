import CoreGraphics
import Foundation
import LumenCore
import PDFKit
import Testing
@testable import LumenReader

/// Поля и колонки PDF: как они находятся и как по ним режутся страницы.
struct PDFLayoutTests {
    enum Kind {
        /// Строки во всю ширину текста.
        case single
        /// Две колонки с промежутком посередине.
        case columns
        /// Заголовок во всю ширину, под ним две колонки.
        case titleAndColumns
        /// Только короткий заголовок.
        case heading
        case blank
    }

    /// PDF со страницами 600×800: «текст» нарисован чёрными полосками, поля по 60 точек слева и справа.
    private func makePDF(_ pages: [Kind]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for kind in pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            let top: CGFloat = kind == .titleAndColumns ? 660 : 720
            if kind == .titleAndColumns {
                context.fill(CGRect(x: 60, y: 700, width: 480, height: 24))
            }
            switch kind {
            case .single:
                for y in stride(from: 80, through: top, by: 16) {
                    context.fill(CGRect(x: 60, y: y, width: 480, height: 10))
                }
            case .columns, .titleAndColumns:
                for y in stride(from: 80, through: top, by: 16) {
                    context.fill(CGRect(x: 60, y: y, width: 220, height: 10))
                    context.fill(CGRect(x: 320, y: y, width: 220, height: 10))
                }
            case .heading:
                context.fill(CGRect(x: 200, y: 600, width: 200, height: 20))
            case .blank:
                break
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    @Test func findsMarginsAndTwoColumns() throws {
        let url = try makePDF([.columns, .single, .titleAndColumns, .blank])
        defer { try? FileManager.default.removeItem(at: url) }
        let layout = try #require(PDFLayoutAnalyzer.analyze(url))
        #expect(layout.pages.count == 4)

        let columns = try #require(layout.pages[0].ink.content)
        #expect(abs(columns.minX - 0.1) < 0.01)
        #expect(abs(columns.maxX - 0.9) < 0.01)
        #expect(abs(columns.minY - 0.1) < 0.01)
        #expect(abs(columns.maxY - 0.9125) < 0.01)
        let split = try #require(layout.pages[0].ink.columnSplit)
        #expect(abs(split - 0.5) < 0.02)

        #expect(layout.pages[1].ink.content != nil)
        #expect(layout.pages[1].ink.columnSplit == nil)

        // Заголовок во всю ширину сверху не мешает узнать колонки.
        let titled = try #require(layout.pages[2].ink.columnSplit)
        #expect(abs(titled - 0.5) < 0.02)

        #expect(layout.pages[3].ink.content == nil)
        #expect(layout.hasColumns)
    }

    @Test func croppedPagesShareOneWidth() throws {
        let url = try makePDF([.single, .heading, .single, .blank])
        defer { try? FileManager.default.removeItem(at: url) }
        let layout = try #require(PDFLayoutAnalyzer.analyze(url))
        let crops = PDFLayoutPlan.cropRects(for: layout)
        #expect(crops.count == 4)
        let width = crops[0].width
        // Текст 480 точек и немного воздуха по краям, а не вся страница 600.
        #expect(width > 480 && width < 520)
        for crop in crops {
            #expect(abs(crop.width - width) < 1)
            #expect(CGRect(x: 0, y: 0, width: 600, height: 800).contains(crop))
        }
        // Короткий заголовок не сдвигает страницу: левый край там же, где у обычного текста.
        #expect(abs(crops[1].minX - crops[0].minX) < 1)
        #expect(crops[1].contains(CGRect(x: 200, y: 600, width: 200, height: 20)))
        // Сверху и снизу поля тоже уходят.
        #expect(crops[0].minY > 50 && crops[0].maxY < 760)
    }

    @Test func columnsBecomeTwoPiecesLeftThenRight() throws {
        let url = try makePDF([.columns, .single])
        defer { try? FileManager.default.removeItem(at: url) }
        let layout = try #require(PDFLayoutAnalyzer.analyze(url))
        let pieces = PDFLayoutPlan.pieces(for: layout, options: PDFLayoutOptions(cropsMargins: true, splitsColumns: true))
        #expect(pieces.count == 2)
        let page = try #require(pieces.first)
        #expect(page.count == 2)
        #expect(page[0].maxX <= page[1].minX + 0.5)
        #expect(page[0].contains(CGRect(x: 60, y: 80, width: 220, height: 10)))
        #expect(page[1].contains(CGRect(x: 320, y: 80, width: 220, height: 10)))
        #expect(pieces[1].count == 1)

        let flat = PDFLayoutPlan.pieces(for: layout, options: PDFLayoutOptions(cropsMargins: true, splitsColumns: false))
        #expect(flat.allSatisfy { $0.count == 1 })
    }

    @Test func edgeShadowOfAScanIsNotContent() {
        var counts = [Int](repeating: 0, count: 100)
        // Тень сканера у левого края, потом текст.
        counts[0] = 50
        counts[1] = 50
        for index in 20..<80 { counts[index] = 10 }
        // Одна пылинка ничего не решает.
        counts[95] = 1
        #expect(InkMap.span(counts, length: 100) == 20...79)
    }

    @Test func layoutIsCached() async throws {
        let url = try makePDF([.columns])
        defer { try? FileManager.default.removeItem(at: url) }
        let key = "layout-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: PDFLayoutAnalyzer.cacheURL(for: key)) }
        #expect(PDFLayoutAnalyzer.cachedLayout(cacheKey: key) == nil)
        let layout = await PDFLayoutAnalyzer.layout(of: url, cacheKey: key)
        #expect(layout != nil)
        #expect(PDFLayoutAnalyzer.cachedLayout(cacheKey: key) == layout)
    }

    /// Экран показывает колонки, а места и выделения по-прежнему считаются страницами файла.
    @MainActor @Test func readerShowsColumnsButCountsFilePages() throws {
        let url = try makePDF([.columns, .single, .columns])
        defer { try? FileManager.default.removeItem(at: url) }
        let layout = try #require(PDFLayoutAnalyzer.analyze(url))
        let controller = PDFReaderController()
        controller.pdfView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        #expect(controller.load(url, layout: layout, options: PDFLayoutOptions(cropsMargins: true, splitsColumns: true)))
        #expect(controller.pageCount == 3)
        #expect(controller.pdfView.document?.pageCount == 5)

        // Колонка по ширине экрана: масштаб больше, чем у целой страницы.
        let fit = controller.fitScale
        #expect(fit > 390.0 / 600 * 1.5)
        controller.zoomToFit()
        #expect(abs(controller.scale - fit) < 0.01)

        // Выделение на правой колонке третьей страницы рисуется на её правом куске.
        let highlightId = UUID()
        let rect = LocatorRect(x: 330, y: 400, width: 100, height: 10)
        controller.setHighlights([PDFHighlight(id: highlightId, locator: SourceLocator(section: 2, rects: [rect]), colorHex: 0xFFAA00)])
        let document = try #require(controller.pdfView.document)
        let left = try #require(document.page(at: 3))
        let right = try #require(document.page(at: 4))
        #expect(left.annotations.isEmpty)
        #expect(right.annotations.count == 1)

        // Без колонок страниц на экране столько же, сколько в файле.
        controller.setLayout(layout, options: PDFLayoutOptions(cropsMargins: true, splitsColumns: false))
        #expect(controller.pdfView.document?.pageCount == 3)
        #expect(controller.pageCount == 3)
        controller.setLayout(layout, options: .original)
        #expect(controller.pdfView.document?.page(at: 0)?.bounds(for: .cropBox).width == 600)
    }
}
