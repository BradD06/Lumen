import Foundation
import LumenCore
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Режим «Текст» для PDF: текст страниц достаётся через PDFKit и становится книгой, как EPUB.
/// Главы берутся из закладок файла, а если их нет, из заголовков, набранных крупным шрифтом.
enum PDFTextConverter {
    /// Версия разбора: если поменять вывод, старый кэш перестанет подходить.
    static let version = 1
    /// Меньше стольких символов на страницу в среднем значит, что это скан без текстового слоя.
    static let minimumCharactersPerPage = 40

    static func convert(file: URL, into folder: URL) throws -> ReadableDocument {
        guard let document = PDFDocument(url: file), !document.isLocked else { throw ReaderError.unreadable }
        let outline = outlineItems(document)
        // Размеры шрифта нужны только для поиска заголовков, а их читать дольше, чем просто текст.
        let needsSizes = outline.isEmpty
        var pages: [[PDFLine]] = []
        pages.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            autoreleasepool {
                pages.append(lines(of: document.page(at: index), withSizes: needsSizes))
            }
        }
        let characters = pages.reduce(0) { $0 + $1.reduce(0) { $0 + $1.text.count } }
        guard characters >= max(document.pageCount, 1) * minimumCharactersPerPage / 2 else { throw ReaderError.noText }

        let book = PDFTextLayout.build(pages: pages, outline: outline)
        var sections: [ReadableSection] = []
        for (index, section) in book.sections.enumerated() {
            let path = "section-\(index + 1).html"
            try page(title: section.title, body: section.html)
                .write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
            sections.append(ReadableSection(title: section.title, path: path))
        }
        return ReadableDocument(sections: sections, toc: book.toc, pdfText: book.index)
    }

    /// Страница главы. Между `<body>` и текстом нет переносов строк: каждый символ тела
    /// на счету, по ним места текста связаны со страницами PDF.
    static func page(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(HTML.escape(title))</title>
        <style>h1 { font-size: 1.55em; margin: 0.3em 0 1em; } h2 { font-size: 1.25em; margin: 1.6em 0 0.7em; } h3 { font-size: 1.08em; margin: 1.4em 0 0.6em; } p { margin: 0 0 0.85em; }</style>
        </head><body>\(body)</body></html>
        """
    }

    /// Строки страницы. С размерами шрифта, если нужно искать заголовки.
    static func lines(of page: PDFPage?, withSizes: Bool) -> [PDFLine] {
        guard let page else { return [] }
        guard withSizes else { return PDFTextLayout.split(page.string ?? "").map { PDFLine($0) } }
        if let attributed = page.attributedString, attributed.length > 0 {
            let lines = lines(from: attributed)
            if lines.contains(where: { $0.size > 0 }) { return lines }
        }
        // Шрифта в тексте страницы нет: размер узнаём по высоте строки на странице.
        return measuredLines(of: page)
    }

    /// Строки текста с размером шрифта, которым набрана большая часть строки.
    static func lines(from attributed: NSAttributedString) -> [PDFLine] {
        let string = attributed.string as NSString
        return lineRanges(in: string).map { range in
            var sizes: [Double: Int] = [:]
            if range.length > 0 {
                attributed.enumerateAttribute(.font, in: range) { value, run, _ in
                    guard let size = pointSize(value) else { return }
                    sizes[(size * 2).rounded() / 2, default: 0] += run.length
                }
            }
            let size = sizes.max { $0.value < $1.value }?.key ?? 0
            return PDFLine(string.substring(with: range), size: size)
        }
    }

    /// Строки с высотой каждой строки на странице вместо размера шрифта: соотношение то же.
    static func measuredLines(of page: PDFPage) -> [PDFLine] {
        let string = (page.string ?? "") as NSString
        return lineRanges(in: string).map { range in
            var size = 0.0
            if range.length > 0, let selection = page.selection(for: range) {
                let height = Double(selection.bounds(for: page).height)
                if height.isFinite, height > 0 { size = (height * 2).rounded() / 2 }
            }
            return PDFLine(string.substring(with: range), size: size)
        }
    }

    /// Диапазоны строк текста. «\r\n» это один перенос, а не пустая строка между абзацами.
    static func lineRanges(in string: NSString) -> [NSRange] {
        let length = string.length
        var ranges: [NSRange] = []
        var start = 0
        while start <= length {
            let found = string.rangeOfCharacter(from: .newlines, options: [], range: NSRange(location: start, length: length - start))
            let end = found.location == NSNotFound ? length : found.location
            ranges.append(NSRange(location: start, length: end - start))
            guard found.location != NSNotFound else { break }
            var next = found.location + found.length
            if string.character(at: found.location) == 13, next < length, string.character(at: next) == 10 { next += 1 }
            start = next
        }
        return ranges
    }

    private static func pointSize(_ value: Any?) -> Double? {
        #if canImport(AppKit)
        (value as? NSFont).map { Double($0.pointSize) }
        #else
        (value as? UIFont).map { Double($0.pointSize) }
        #endif
    }

    /// Закладки PDF по порядку, с уровнем вложенности.
    static func outlineItems(_ document: PDFDocument) -> [PDFOutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        var items: [PDFOutlineItem] = []
        func walk(_ item: PDFOutline, level: Int) {
            for index in 0..<item.numberOfChildren {
                guard let child = item.child(at: index) else { continue }
                let title = (child.label ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let page = child.destination?.page ?? (child.action as? PDFActionGoTo)?.destination.page
                if !title.isEmpty, let page {
                    items.append(PDFOutlineItem(title: title, page: document.index(for: page), level: level))
                }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 0)
        return items
    }
}

/// Находит в оригинале PDF текст, выделенный в режиме «Текст», чтобы выделение было видно и там.
@MainActor
public final class PDFTextFinder {
    private let document: PDFDocument

    public init?(url: URL) {
        guard let document = PDFDocument(url: url) else { return nil }
        self.document = document
    }

    /// Прямоугольники строк выделения на странице `page` (или соседней), в координатах страницы.
    /// `fraction` это примерное место на странице, от 0 до 1: из одинаковых кусков берётся ближайший.
    /// Выделение может перейти на следующую страницу. `nil`, если текст в PDF не нашёлся.
    public func rects(of text: String, page: Int, fraction: Double) -> [LocatorRect]? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, words.count <= 2000 else { return nil }
        let headCount = min(words.count, 12)
        guard let head = Self.regex(for: words.prefix(headCount)) else { return nil }
        let tail = words.count > headCount ? Self.regex(for: words.suffix(12)) : nil

        for candidate in [page, page + 1, page - 1] where candidate >= 0 && candidate < document.pageCount {
            guard let pdfPage = document.page(at: candidate), let string = pdfPage.string else { continue }
            let length = (string as NSString).length
            let starts = head.matches(in: string, range: NSRange(location: 0, length: length))
            guard let start = starts.min(by: {
                abs(Double($0.range.location) / Double(max(length, 1)) - fraction) < abs(Double($1.range.location) / Double(max(length, 1)) - fraction)
            }) else { continue }

            guard let tail else {
                return rects(for: start.range, on: pdfPage, index: candidate, base: page)
            }
            let after = start.range.location + 1
            if let end = tail.firstMatch(in: string, range: NSRange(location: after, length: length - after)) {
                let range = NSRange(location: start.range.location, length: NSMaxRange(end.range) - start.range.location)
                return rects(for: range, on: pdfPage, index: candidate, base: page)
            }
            // Конец выделения на следующей странице.
            guard candidate + 1 < document.pageCount, let nextPage = document.page(at: candidate + 1), let nextString = nextPage.string,
                  let end = tail.firstMatch(in: nextString, range: NSRange(location: 0, length: (nextString as NSString).length)) else { continue }
            let first = rects(for: NSRange(location: start.range.location, length: length - start.range.location), on: pdfPage, index: candidate, base: page) ?? []
            let second = rects(for: NSRange(location: 0, length: NSMaxRange(end.range)), on: nextPage, index: candidate + 1, base: page) ?? []
            let all = first + second
            return all.isEmpty ? nil : all
        }
        return nil
    }

    private func rects(for range: NSRange, on page: PDFPage, index: Int, base: Int) -> [LocatorRect]? {
        guard range.length > 0, let selection = page.selection(for: range) else { return nil }
        var rects: [LocatorRect] = []
        for line in selection.selectionsByLine() {
            let bounds = line.bounds(for: page)
            guard bounds.width > 0.5, bounds.height > 0.5 else { continue }
            rects.append(LocatorRect(page: index == base ? nil : index, x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height))
        }
        return rects.isEmpty ? nil : rects
    }

    /// Слова текста, между которыми на странице PDF может быть любой пробел или перенос строки,
    /// а внутри слова перенос через дефис.
    static func regex<S: Sequence>(for words: S) -> NSRegularExpression? where S.Element == String {
        let wrap = #"(?:[\-­‐]?\s+|­)?"#
        let pattern = words.map { word in
            word.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: wrap)
        }.joined(separator: #"\s+"#)
        guard !pattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
