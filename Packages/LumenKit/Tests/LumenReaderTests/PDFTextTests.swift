import CoreGraphics
import CoreText
import Foundation
import LumenCore
import PDFKit
import Testing
@testable import LumenReader

/// Своя строка текста для каждого номера: одинаковые строки у края страниц приняли бы за колонтитул.
private func sentence(_ number: Int, latin: Bool = false) -> String {
    let words = latin
        ? ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel"]
        : ["яблоко", "груша", "слива", "вишня", "персик", "абрикос", "малина", "ежевика"]
    let picked = (0..<4).map { words[(number >> (3 * $0)) % words.count] }
    return (picked + words.shuffledDeterministically(by: number)).joined(separator: " ").capitalizedFirst + "."
}

private extension Array where Element == String {
    func shuffledDeterministically(by seed: Int) -> [String] {
        enumerated().sorted { ($0.offset * 7 + seed) % count < ($1.offset * 7 + seed) % count }.map(\.element)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct PDFTextLayoutTests {
    private func page(_ lines: [String], size: Double = 0) -> [PDFLine] {
        lines.map { PDFLine($0, size: size) }
    }

    /// Текст главы так, как его видит скрипт читалки: без тегов, с настоящими символами вместо `&amp;`.
    private func visibleText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    @Test func recognisesPageNumbers() {
        for text in ["12", "— 12 —", "- 7 -", "стр. 15", "Page 3", "xiv", "4 из 120", "[ 9 ]"] {
            #expect(PDFTextLayout.isPageNumber(text), "\(text)")
        }
        for text in ["Глава 1", "1945 год был", "I", "Введение"] {
            #expect(!PDFTextLayout.isPageNumber(text), "\(text)")
        }
    }

    @Test func removesRunningHeadersAndPageNumbers() {
        let pages = (1...6).map { number in
            page([
                number.isMultiple(of: 2) ? "Тестовая книга" : "Иван Петров",
                sentence(number),
                "\(number)",
            ])
        }
        let stripped = PDFTextLayout.stripRunningLines(pages, bodySize: 0)
        for (index, lines) in stripped.enumerated() {
            #expect(lines.map(\.text) == [sentence(index + 1)])
        }
    }

    @Test func keepsChapterTitlesThatRepeat() {
        let pages = (1...6).map { number in page(["Глава \(number)", sentence(number)]) }
        let stripped = PDFTextLayout.stripRunningLines(pages, bodySize: 0)
        #expect(stripped.allSatisfy { $0.count == 2 })
    }

    @Test func joinsLinesAndHyphenatedWords() {
        #expect(PDFTextLayout.join("Это приме-", "чание") == "Это примечание")
        #expect(PDFTextLayout.join("Город Нью-", "Йорк") == "Город Нью-Йорк")
        #expect(PDFTextLayout.join("слово", "другое") == "слово другое")
        #expect(PDFTextLayout.join("слово —", "тире") == "слово — тире")
        #expect(PDFTextIndex.reflow("Первая стро-\nка и вторая\r\nстрока") == "Первая строка и вторая строка")
    }

    @Test func buildsParagraphsFromLines() {
        let long = "Это длинная строка основного текста книги, которая занимает всю ширину"
        let book = PDFTextLayout.build(pages: [
            page([long, long, "Конец абзаца.", long, "и его продол-", "жение здесь."]),
        ], outline: [])
        #expect(book.sections.count == 1)
        let html = book.sections[0].html
        #expect(html.components(separatedBy: "<p>").count - 1 == 2)
        #expect(html.contains("продолжение здесь."))
    }

    @Test func splitsChaptersByOutlineAndMapsPages() throws {
        let pages = [
            page(["Предисловие автора.", sentence(1)]),
            page(["Глава первая", sentence(2), sentence(3)]),
            page([sentence(4), "Глава вторая", sentence(5)]),
            page([sentence(6)]),
        ]
        let outline = [
            PDFOutlineItem(title: "Глава первая", page: 1, level: 0),
            PDFOutlineItem(title: "Глава вторая", page: 2, level: 0),
        ]
        let book = PDFTextLayout.build(pages: pages, outline: outline)
        #expect(book.sections.map(\.title) == ["Начало", "Глава первая", "Глава вторая"])
        #expect(book.toc.map(\.section) == [0, 1, 2])
        #expect(book.sections[1].html.hasPrefix("<h1 id=\"pdf-h1\">Глава первая </h1>"))
        // Заголовок из текста страницы не повторяется абзацем.
        #expect(!book.sections[2].html.contains("<p>Глава вторая"))

        let index = book.index
        #expect(index.pageCount == 4)
        #expect(index.local(index.global(page: 0)).section == 0)
        #expect(index.local(index.global(page: 1)).section == 1)
        // Третья страница начинается в первой главе, а кончается во второй.
        #expect(index.local(index.global(page: 2)).section == 1)
        #expect(index.page(2, overlaps: 1) && index.page(2, overlaps: 2))
        #expect(index.local(index.global(page: 3)).section == 2)

        // Длины глав в указателе совпадают с видимым текстом: по ним скрипт читалки находит места.
        for (number, section) in book.sections.enumerated() {
            let end = number + 1 < index.sections.count ? index.sections[number + 1] : index.length
            #expect(visibleText(section.html).utf16.count == end - index.sections[number])
        }
    }

    @Test func findsHeadingsByFontSizeWithoutOutline() {
        let body = "Обычная строка текста главы, такая же длинная, как и другие строки."
        let book = PDFTextLayout.build(pages: [
            [PDFLine("Большое название книги", size: 30), PDFLine(body, size: 11)],
            [PDFLine("Глава 1", size: 20), PDFLine(body, size: 11), PDFLine("Раздел", size: 14), PDFLine(body, size: 11)],
            [PDFLine("Глава 2", size: 20), PDFLine(body, size: 11)],
        ], outline: [])
        // Название на титуле набрано крупнее глав, поэтому оно и есть первая глава.
        #expect(book.sections.map(\.title) == ["Большое название книги", "Глава 1", "Глава 2"])
        #expect(book.toc.contains { $0.title == "Раздел" && $0.level == 1 && $0.section == 1 && $0.anchor != nil })
    }

    @Test func longBooksWithoutChaptersAreCutIntoChunks() {
        let pages = (0..<50).map { page([sentence($0)]) }
        let book = PDFTextLayout.build(pages: pages, outline: [])
        #expect(book.sections.count == 3)
        #expect(book.sections[1].title == "Стр. 21–40")
        #expect(!book.sections[1].html.contains("<h1"))
    }

    @Test func indexFindsPagesAndPlaces() {
        let index = PDFTextIndex(pages: [0, 100, 100, 250], sections: [0, 180], length: 400)
        #expect(index.page(at: 50) == 0)
        // Пустая вторая страница стоит там же, где третья: текст относится к третьей.
        #expect(index.page(at: 100) == 2)
        #expect(index.page(at: 260) == 3)
        #expect(index.local(200) == (section: 1, offset: 20))
        let place = index.place(of: SourceLocator(section: 2, textOffset: 90))
        #expect(place.section == 1 && place.offset == 10)
        #expect(index.fraction(of: 175, onPage: 2) == 0.5)
    }
}

/// Настоящий PDF с текстовым слоем: колонтитулы, номера страниц, заголовки крупным шрифтом.
struct PDFTextConverterTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PDFTextTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func makePDF(pages: [[(String, CGFloat)]]) throws -> URL {
        let url = folder.appendingPathComponent("book.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 640, height: 600)
        let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for lines in pages {
            context.beginPDFPage(nil)
            // Строка опускается на свою высоту до того, как её нарисовать: крупный заголовок
            // не налезает на строку над ним, и PDFKit не склеивает их в одну.
            var y: CGFloat = 590
            for (text, size) in lines {
                y -= size * 1.7
                let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
                let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                let line = CTLineCreateWithAttributedString(string)
                context.textPosition = CGPoint(x: 30, y: y)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    @Test func turnsPDFIntoChaptersWithoutRunningLines() throws {
        var pages: [[(String, CGFloat)]] = []
        for number in 1...6 {
            var lines: [(String, CGFloat)] = [("Sample Book Title", 9)]
            if number == 2 || number == 4 { lines.append(("Chapter \(number / 2)", 22)) }
            lines += (0..<4).map { (sentence(number * 8 + $0, latin: true), 11) }
            lines.append(("Ending \(sentence(number * 100, latin: true))", 11))
            lines.append(("\(number)", 9))
            pages.append(lines)
        }
        let file = try makePDF(pages: pages)
        let document = try PDFTextConverter.convert(file: file, into: folder)
        let index = try #require(document.pdfText)
        #expect(index.pageCount == 6)
        let pdf = try #require(PDFDocument(url: file))
        let extracted = PDFTextConverter.lines(of: pdf.page(at: 1), withSizes: true)
        try #require(
            document.sections.map(\.title) == ["Начало", "Chapter 1", "Chapter 2"],
            "Строки второй страницы: \(extracted.map { "\($0.size) \($0.text)" })"
        )
        let html = try String(contentsOf: folder.appendingPathComponent(document.sections[1].path), encoding: .utf8)
        #expect(html.contains("Ending \(sentence(200, latin: true))"))
        #expect(!html.contains("Sample Book Title"))
        #expect(html.contains("<body><h1"))
        #expect(index.local(index.global(page: 4)).section == 2)
    }

    @Test func keepsPicturesWhereTheyStoodOnThePage() throws {
        let url = folder.appendingPathComponent("pictures.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 640, height: 600)
        let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        let bitmap = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        bitmap.setFillColor(CGColor(srgbRed: 1, green: 0.4, blue: 0.2, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let picture = try #require(bitmap.makeImage())
        context.beginPDFPage(nil)
        func draw(_ text: String, y: CGFloat) {
            let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            ))
            context.textPosition = CGPoint(x: 30, y: y)
            CTLineDraw(line, context)
        }
        draw("Text above the picture is a whole sentence that ends here.", y: 560)
        context.draw(picture, in: CGRect(x: 100, y: 300, width: 300, height: 200))
        draw("Label", y: 400)
        draw("Text below the picture is another sentence that ends here.", y: 260)
        context.endPDFPage()
        context.closePDF()

        let document = try PDFTextConverter.convert(file: url, into: folder)
        let html = try String(contentsOf: folder.appendingPathComponent(document.sections[0].path), encoding: .utf8)
        let above = try #require(html.range(of: "Text above"))
        let image = try #require(html.range(of: "<img src=\"images/p1-1.jpg\""))
        let below = try #require(html.range(of: "Text below"))
        #expect(above.lowerBound < image.lowerBound && image.lowerBound < below.lowerBound)
        // Подпись внутри картинки уже есть на самой картинке.
        #expect(!html.contains("Label"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("images/p1-1.jpg").path))
    }

    @Test func scanWithoutTextIsRefused() throws {
        let file = try makePDF(pages: [[], [], []])
        #expect(throws: ReaderError.noText) {
            try PDFTextConverter.convert(file: file, into: folder)
        }
    }

    @MainActor
    @Test func findsTextFromTheTextModeOnThePage() throws {
        let file = try makePDF(pages: [[
            ("First line of the page with some words", 12),
            ("and a hyphen-", 12),
            ("ated word at the end.", 12),
        ]])
        let finder = try #require(PDFTextFinder(url: file))
        let rects = try #require(finder.rects(of: "with some words and a hyphenated word", page: 0, fraction: 0.2))
        #expect(rects.count >= 2)
        #expect(finder.rects(of: "words that are not there at all", page: 0, fraction: 0) == nil)
    }
}
