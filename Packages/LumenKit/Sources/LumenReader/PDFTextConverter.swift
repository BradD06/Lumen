import Foundation
import LumenCore
import ImageIO
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
    static let version = 6
    /// Меньше стольких символов на страницу в среднем значит, что это скан без текстового слоя.
    static let minimumCharactersPerPage = 40

    static func convert(file: URL, into folder: URL) throws -> ReadableDocument {
        guard let document = PDFDocument(url: file), !document.isLocked else { throw ReaderError.unreadable }
        let outline = outlineItems(document)
        // Размеры шрифта нужны только для поиска заголовков, а их читать дольше, чем просто текст.
        let needsSizes = outline.isEmpty
        var pages: [[PDFLine]] = []
        pages.reserveCapacity(document.pageCount)
        let imagesFolder = folder.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: index) else {
                    pages.append([])
                    return
                }
                let text = lines(of: page, withSizes: needsSizes)
                let images = PDFPageImages.extract(from: page, index: index, into: imagesFolder, pageHasText: text.contains { !$0.text.isEmpty })
                pages.append(images.isEmpty ? text : PDFPageImages.place(images, among: text))
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
        <style>p.image { margin: 1.2em 0; } p.image img { border-radius: 10px; } h1 { font-size: 1.55em; margin: 0.3em 0 1em; } h2 { font-size: 1.25em; margin: 1.6em 0 0.7em; } h3 { font-size: 1.08em; margin: 1.4em 0 0.6em; } p { margin: 0 0 0.85em; }</style>
        </head><body>\(body)</body></html>
        """
    }

    /// Строки страницы с местом каждой на странице. С размерами шрифта, если нужно искать заголовки.
    static func lines(of page: PDFPage?, withSizes: Bool) -> [PDFLine] {
        guard let page else { return [] }
        if let lines = framedLines(of: page, withSizes: withSizes) { return lines }
        guard withSizes else { return PDFTextLayout.split(page.string ?? "").map { PDFLine($0) } }
        if let attributed = page.attributedString, attributed.length > 0 {
            let lines = lines(from: attributed)
            if lines.contains(where: { $0.size > 0 }) { return lines }
        }
        // Шрифта в тексте страницы нет: размер узнаём по высоте строки на странице.
        return measuredLines(of: page)
    }

    /// Строки так, как их делит PDFKit при выделении, с местом на странице. Куски одной строки
    /// (так бывает в выровненном тексте) склеиваются в одну. `nil`, если PDFKit строк не дал.
    static func framedLines(of page: PDFPage, withSizes: Bool) -> [PDFLine]? {
        guard let string = page.string else { return [] }
        let length = (string as NSString).length
        guard length > 0 else { return [] }
        guard let all = page.selection(for: NSRange(location: 0, length: length)) else { return nil }
        var lines: [PDFLine] = []
        for piece in all.selectionsByLine() {
            let attributed = piece.attributedString
            let text = (attributed.map(visibleText) ?? piece.string ?? "").trimmingCharacters(in: .newlines)
            let bounds = piece.bounds(for: page)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty, bounds.width > 0, bounds.height > 0 else { continue }
            let frame = LineFrame(minX: bounds.minX, minY: bounds.minY, maxX: bounds.maxX, maxY: bounds.maxY)
            var size = 0.0
            if withSizes {
                size = attributed.map(dominantSize) ?? 0
                if size == 0 { size = (frame.height * 2).rounded() / 2 }
            }
            if var last = lines.last, let previous = last.frame,
               abs(previous.midY - frame.midY) < min(previous.height, frame.height) * 0.5,
               frame.minX >= previous.maxX - 2 {
                // Вплотную это продолжение слова, с промежутком следующее слово.
                let gap = frame.minX - previous.maxX
                last.text += (gap < min(previous.height, frame.height) * 0.15 ? "" : " ") + text
                last.frame = LineFrame(
                    minX: min(previous.minX, frame.minX), minY: min(previous.minY, frame.minY),
                    maxX: max(previous.maxX, frame.maxX), maxY: max(previous.maxY, frame.maxY)
                )
                last.size = max(last.size, size)
                lines[lines.count - 1] = last
            } else {
                lines.append(PDFLine(text, size: size, frame: frame))
            }
        }
        return lines.isEmpty ? nil : lines
    }

    /// Текст строки без значков из шрифтов-пиктограмм: в таком шрифте буква «h» рисуется
    /// стрелкой или рукой, и в тексте от неё осталась бы просто «h». Значок в начале строки
    /// это пункт списка, он становится «•».
    static func visibleText(_ attributed: NSAttributedString) -> String {
        let string = attributed.string as NSString
        var runs: [(text: String, font: FontInfo?)] = []
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            runs.append((string.substring(with: range), FontInfo(value)))
        }
        var families: [String: Int] = [:]
        for run in runs { if let family = run.font?.family { families[family, default: 0] += run.text.count } }
        let mainFamily = families.max { $0.value < $1.value }?.key
        let hasCyrillic = attributed.string.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }

        var result = ""
        var hasBullet = false
        for (position, run) in runs.enumerated() {
            let isLast = runs[(position + 1)...].allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let font = run.font, isIcon(run.text, font: font, mainFamily: mainFamily, hasCyrillic: hasCyrillic, before: result, isLast: isLast) else {
                result += run.text
                continue
            }
            if !hasBullet, result.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "• "
                hasBullet = true
            }
        }
        return result
    }

    struct FontInfo {
        var name: String
        var family: String

        init(name: String, family: String) {
            self.name = name
            self.family = family
        }

        init?(_ value: Any?) {
            #if canImport(AppKit)
            guard let font = value as? NSFont else { return nil }
            name = font.fontName
            family = font.familyName ?? font.fontName
            #else
            guard let font = value as? UIFont else { return nil }
            name = font.fontName
            family = font.familyName
            #endif
        }
    }

    /// Значок, а не буква: всё, что набрано шрифтом-пиктограммой, или одинокая латинская буква
    /// чужим шрифтом в русском тексте в начале строки или после конца предложения («скрыть её. h»).
    static func isIcon(_ text: String, font: FontInfo, mainFamily: String?, hasCyrillic: Bool, before: String, isLast: Bool) -> Bool {
        if isSymbolFont(font.name) { return true }
        let letter = text.trimmingCharacters(in: .whitespaces)
        guard hasCyrillic, letter.count == 1, letter.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isAlphabetic }),
              let mainFamily, font.family != mainFamily else { return false }
        let name = font.name.lowercased()
        // Переменные в формулах набраны курсивом или математическим шрифтом, их не трогаем.
        if ["italic", "oblique", "math", "cmmi"].contains(where: { name.contains($0) }) { return false }
        let previous = before.trimmingCharacters(in: .whitespaces)
        return previous.isEmpty || isLast && previous.last.map { ".!?:;".contains($0) } == true
    }

    /// Шрифты, в которых вместо букв значки.
    static func isSymbolFont(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["wingding", "dingbat", "webding", "marlett", "fontawesome", "icon", "pictogram", "glyphicon", "materialsymbols"].contains { name.contains($0) }
    }

    /// Размер шрифта, которым набрана большая часть текста.
    static func dominantSize(_ attributed: NSAttributedString) -> Double {
        var sizes: [Double: Int] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, run, _ in
            guard let size = pointSize(value) else { return }
            sizes[(size * 2).rounded() / 2, default: 0] += run.length
        }
        return sizes.max { $0.value < $1.value }?.key ?? 0
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

/// Картинки со страниц PDF для режима «Текст»: каждая вырезается из страницы в свой файл
/// и встаёт в текст там же, где стояла на странице.
enum PDFPageImages {
    struct Image {
        /// Где картинка на странице, в координатах страницы.
        var rect: CGRect
        /// Путь к файлу относительно папки документа.
        var path: String
    }

    /// Картинки мельче этого (значки, линии, буквицы) в текст не попадают.
    static let minimumSide: CGFloat = 40
    /// Самая длинная сторона файла картинки, в точках экрана.
    static let maximumPixels: CGFloat = 1600

    static func extract(from page: PDFPage, index: Int, into folder: URL, pageHasText: Bool) -> [Image] {
        guard let pageRef = page.pageRef else { return [] }
        let bounds = page.bounds(for: .mediaBox)
        var rects = PDFImageFinder.imageRects(in: pageRef)
            .map { $0.intersection(bounds) }
            .filter { !$0.isNull && $0.width >= minimumSide && $0.height >= minimumSide }
        // Картинка под текстом на всю страницу это фон или скан: в тексте она не нужна.
        if pageHasText {
            rects.removeAll { PDFImageFinder.isScan([$0], page: bounds) }
        }
        rects = merged(rects)
        var images: [Image] = []
        for (number, rect) in rects.enumerated() {
            let path = "images/p\(index + 1)-\(number + 1).jpg"
            guard render(rect, of: page, to: folder.deletingLastPathComponent().appendingPathComponent(path)) else { continue }
            images.append(Image(rect: rect, path: path))
        }
        return images
    }

    /// Картинка из нескольких кусков (так часто устроены схемы) становится одной.
    static func merged(_ rects: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rects.sorted(by: { $0.maxY > $1.maxY }) {
            if let index = result.firstIndex(where: { $0.insetBy(dx: -4, dy: -4).intersects(rect) }) {
                result[index] = result[index].union(rect)
            } else {
                result.append(rect)
            }
        }
        return result
    }

    /// Ставит картинки между строками страницы по высоте: картинка идёт перед первой строкой ниже неё.
    /// Строки внутри картинки (подписи на схеме) уже есть на самой картинке и в текст не идут.
    /// Если места строк неизвестны, картинки встают в конце страницы.
    static func place(_ images: [Image], among lines: [PDFLine]) -> [PDFLine] {
        let pending = images.sorted { $0.rect.maxY > $1.rect.maxY }
        var result: [PDFLine] = []
        var next = 0
        for line in lines {
            guard let frame = line.frame, !line.text.isEmpty else {
                result.append(line)
                continue
            }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            while next < pending.count, pending[next].rect.minY > center.y {
                result.append(PDFLine("", image: pending[next].path, frame: LineFrame(pending[next].rect)))
                next += 1
            }
            if images.contains(where: { $0.rect.contains(center) }) { continue }
            result.append(line)
        }
        result += pending[next...].map { PDFLine("", image: $0.path, frame: LineFrame($0.rect)) }
        return result
    }

    /// Вырезает кусок страницы в JPEG на белом фоне.
    static func render(_ rect: CGRect, of page: PDFPage, to url: URL) -> Bool {
        let scale = min(2, maximumPixels / max(rect.width, rect.height))
        let width = Int((rect.width * scale).rounded())
        let height = Int((rect.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return false }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Страница рисуется от начала своей рамки, а прямоугольники картинок в координатах страницы.
        let box = page.bounds(for: .mediaBox)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: box.minX - rect.minX, y: box.minY - rect.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}

extension LineFrame {
    init(_ rect: CGRect) {
        self.init(minX: rect.minX, minY: rect.minY, maxX: rect.maxX, maxY: rect.maxY)
    }
}
