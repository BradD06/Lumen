import CoreGraphics
import Foundation
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
