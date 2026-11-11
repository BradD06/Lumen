import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import LumenReader

struct PDFPageTintTests {
    /// PDF на одну страницу 600×800 с картинкой в заданном месте и строчкой текста.
    private func makePDF(imageRect: CGRect) throws -> CGPDFPage {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 600, height: 800)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        let bitmap = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        bitmap.setFillColor(CGColor(srgbRed: 1, green: 0.4, blue: 0.2, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(bitmap.makeImage())
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 40, y: 700, width: 300, height: 12))
        context.saveGState()
        context.draw(image, in: imageRect)
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        return try #require(document.page(at: 1))
    }

    /// Страница без полей (рамка начинается не в нуле) перекрашивается вся, а текст стоит на своём месте.
    @Test func croppedPageIsTintedEverywhere() throws {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 600, height: 800)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        pdf.beginPDFPage(nil)
        pdf.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        pdf.fill(CGRect(x: 150, y: 150, width: 100, height: 100))
        pdf.endPDFPage()
        pdf.closePDF()

        let factory = TintedPageFactory()
        let document = try #require(PDFDocument(data: data as Data))
        document.delegate = factory
        let page = try #require(document.page(at: 0) as? TintedPDFPage)
        page.style = PDFPageStyle(tint: .paper(0xF4EADB), backdrop: 0x00FF00)
        let crop = CGRect(x: 100, y: 100, width: 400, height: 600)
        page.setBounds(crop, for: .cropBox)

        let width = 400, height = 600
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Синий там, где страница ничего не нарисовала.
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        page.draw(with: .cropBox, to: context)

        let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        func color(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let offset = ((height - 1 - y) * width + x) * 4
            return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
        }
        func isPaper(_ x: Int, _ y: Int) -> Bool {
            let (red, green, blue) = color(x, y)
            return abs(red - 0xF4) < 6 && abs(green - 0xEA) < 6 && abs(blue - 0xDB) < 6
        }
        // Квадрат файла (150, 150) в рамке стоит в точке (50, 50).
        let ink = color(100, 100)
        #expect(ink.0 < 60 && ink.1 < 60 && ink.2 < 60, "\(ink)")
        // Слева, снизу, справа, сверху и посередине: бумага, а не пустое место.
        for (x, y) in [(30, 300), (200, 30), (370, 300), (200, 570), (200, 300)] {
            #expect(isPaper(x, y), "(\(x), \(y)) = \(color(x, y))")
        }
    }

    @Test func findsWhereTheImageIs() throws {
        let page = try makePDF(imageRect: CGRect(x: 100, y: 200, width: 150, height: 90))
        let rects = PDFImageFinder.imageRects(in: page)
        #expect(rects.count == 1)
        let rect = try #require(rects.first)
        #expect(abs(rect.minX - 100) < 1 && abs(rect.minY - 200) < 1)
        #expect(abs(rect.width - 150) < 1 && abs(rect.height - 90) < 1)
    }

    @Test func pageCoveredByOneImageIsAScan() {
        let page = CGRect(x: 0, y: 0, width: 600, height: 800)
        #expect(PDFImageFinder.isScan([CGRect(x: 0, y: 0, width: 600, height: 800)], page: page))
        #expect(!PDFImageFinder.isScan([CGRect(x: 100, y: 200, width: 150, height: 90)], page: page))
        #expect(!PDFImageFinder.isScan([], page: page))
    }

    @Test func nightPageLiftsToThePageColorAfterInk() {
        let lift = TintedPDFPage.lift(page: 0x3A2A40, ink: 0xF3E3DA)
        let components = lift.components ?? []
        let ink = TintedPDFPage.channels(0xF3E3DA)
        let page = TintedPDFPage.channels(0x3A2A40)
        #expect(components.count >= 3)
        #expect(abs(components[0] * ink.0 - page.0) < 0.01)
        #expect(abs(components[1] * ink.1 - page.1) < 0.01)
        #expect(abs(components[2] * ink.2 - page.2) < 0.01)
    }

    @Test func everyThemeHasAPDFLook() {
        #expect(ReaderAppearance.Palette.night.pdfStyle.isNight)
        #expect(ReaderAppearance.Palette.paper.pdfStyle.tint == .paper(0xF4EADB))
        #expect(ReaderAppearance.Palette.original.pdfStyle == .original)
    }
}
