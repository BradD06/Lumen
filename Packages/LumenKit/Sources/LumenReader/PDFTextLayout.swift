import Foundation
import LumenCore

/// Строка текста со страницы PDF и размер её шрифта (0, если он неизвестен).
struct PDFLine: Hashable, Sendable {
    var text: String
    var size: Double

    init(_ text: String, size: Double = 0) {
        self.text = text
        self.size = size
    }
}

/// Пункт закладок PDF: название, страница и вложенность.
struct PDFOutlineItem: Hashable, Sendable {
    var title: String
    var page: Int
    var level: Int
}

/// Как текст режима «Текст» связан со страницами PDF. Все места считаются сквозным номером
/// символа по всей книге: так страница, на которой начинается новая глава, всё равно одна.
public struct PDFTextIndex: Codable, Hashable, Sendable {
    /// С какого символа книги начинается каждая страница PDF. Пустые страницы стоят там же, где следующая.
    public var pages: [Int]
    /// С какого символа книги начинается каждая глава.
    public var sections: [Int]
    /// Сколько символов во всей книге.
    public var length: Int

    public init(pages: [Int], sections: [Int], length: Int) {
        self.pages = pages
        self.sections = sections
        self.length = length
    }

    public var pageCount: Int { pages.count }

    /// Сквозной номер символа `offset` главы `section`.
    public func global(section: Int, offset: Int) -> Int {
        guard !sections.isEmpty else { return max(offset, 0) }
        return sections[min(max(section, 0), sections.count - 1)] + max(offset, 0)
    }

    /// Сквозной номер символа на странице `page`, `within` символов от её начала.
    public func global(page: Int, within: Int = 0) -> Int {
        guard !pages.isEmpty else { return max(within, 0) }
        return min(max(pages[min(max(page, 0), pages.count - 1)] + within, 0), length)
    }

    /// Глава и символ в ней для сквозного номера.
    public func local(_ global: Int) -> (section: Int, offset: Int) {
        let section = Self.lastIndex(in: sections, notAfter: global)
        return (section, global - (sections.isEmpty ? 0 : sections[section]))
    }

    /// Страница PDF, на которой стоит символ.
    public func page(at global: Int) -> Int {
        Self.lastIndex(in: pages, notAfter: global)
    }

    /// Где в тексте место из PDF: начало страницы плюс сдвиг внутри неё, если место запомнили в режиме «Текст».
    public func place(of locator: SourceLocator) -> (section: Int, offset: Int) {
        local(global(page: locator.section, within: locator.textOffset ?? 0))
    }

    /// Задевает ли страница главу: на странице может кончаться одна глава и начинаться другая.
    public func page(_ page: Int, overlaps section: Int) -> Bool {
        guard pages.indices.contains(page), sections.indices.contains(section) else { return false }
        let pageEnd = page + 1 < pages.count ? pages[page + 1] : length
        let sectionEnd = section + 1 < sections.count ? sections[section + 1] : length
        return pages[page] <= sectionEnd && pageEnd >= sections[section]
    }

    /// Насколько дочитано место внутри страницы, от 0 до 1.
    public func fraction(of global: Int, onPage page: Int) -> Double {
        guard pages.indices.contains(page) else { return 0 }
        let end = page + 1 < pages.count ? pages[page + 1] : length
        let size = end - pages[page]
        return size > 0 ? min(max(Double(global - pages[page]) / Double(size), 0), 1) : 0
    }

    /// Текст, выделенный в оригинале PDF, в том виде, в каком он стоит в режиме «Текст»:
    /// строки склеены, переносы слов убраны.
    public static func reflow(_ text: String) -> String {
        PDFTextLayout.split(text)
            .map(PDFTextLayout.clean)
            .filter { !$0.isEmpty }
            .reduce("") { $0.isEmpty ? $1 : PDFTextLayout.join($0, $1) }
    }

    /// Последний индекс, где значение не больше `value`. Из равных берётся последний:
    /// пустая страница стоит там же, где следующая, и текст относится к следующей.
    static func lastIndex(in values: [Int], notAfter value: Int) -> Int {
        guard !values.isEmpty else { return 0 }
        var low = 0
        var high = values.count - 1
        var found = 0
        while low <= high {
            let middle = (low + high) / 2
            if values[middle] <= value {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }
}

/// Как текст страниц PDF становится главами и абзацами, как в EPUB: без колонтитулов
/// и номеров страниц, со склеенными строками и переносами.
enum PDFTextLayout {
    struct Section: Hashable {
        var title: String
        /// Тело главы. Между тегами нет пробелов, поэтому символы текста считаются точно так же,
        /// как их считает скрипт читалки.
        var html: String
    }

    struct Book {
        var sections: [Section]
        var toc: [TocEntry]
        var index: PDFTextIndex
    }

    /// Начало главы (уровень 0) или подзаголовок внутри неё.
    struct Break: Hashable {
        var page: Int
        var line: Int
        /// Сколько строк страницы занимает заголовок: они не попадают в текст второй раз.
        var length: Int
        var title: String
        var level: Int
        /// Глава без заголовка: книгу без оглавления просто режем на куски по страницам.
        var showsHeading = true
    }

    /// Столько страниц в одном куске, если глав найти не удалось.
    static let chunkPages = 20

    static func build(pages raw: [[PDFLine]], outline: [PDFOutlineItem], frontTitle: String = "Начало") -> Book {
        let cleaned = raw.map { $0.map { PDFLine(clean($0.text), size: $0.size) } }
        let body = bodySize(cleaned)
        let pages = stripRunningLines(cleaned, bodySize: body)
        var breaks = outline.isEmpty ? headingBreaks(pages, bodySize: body) : outlineBreaks(outline, pages: pages)
        if !breaks.contains(where: { $0.level == 0 }) {
            breaks += chunkBreaks(pageCount: pages.count)
        }
        breaks.sort { ($0.page, $0.line, $0.level) < ($1.page, $1.line, $1.level) }
        let full = typicalLineLength(pages)

        var writer = Writer(title: frontTitle)
        var nextBreak = 0
        for (pageIndex, lines) in pages.enumerated() {
            writer.pendingPages += 1
            var index = 0
            func applyBreaks(upTo line: Int) -> Int {
                var consumed = 0
                while nextBreak < breaks.count,
                      breaks[nextBreak].page < pageIndex || (breaks[nextBreak].page == pageIndex && breaks[nextBreak].line <= line) {
                    let item = breaks[nextBreak]
                    nextBreak += 1
                    if item.level == 0 {
                        writer.startSection(item.title, showsHeading: item.showsHeading)
                    } else {
                        writer.heading(item.title, level: item.level)
                    }
                    if item.page == pageIndex, item.line == line { consumed = max(consumed, item.length) }
                }
                return consumed
            }
            while index < lines.count {
                let consumed = applyBreaks(upTo: index)
                if consumed > 0 {
                    index += consumed
                    continue
                }
                let line = lines[index]
                if line.text.isEmpty {
                    writer.flushParagraph()
                    index += 1
                    continue
                }
                let next = index + 1 < lines.count
                    ? lines[index + 1]
                    : pages.dropFirst(pageIndex + 1).lazy.compactMap { following in following.first { !$0.text.isEmpty } }.first
                let breaksNext = nextBreak < breaks.count && breaks[nextBreak].page == pageIndex && breaks[nextBreak].line == index + 1
                writer.append(line.text, breakAfter: breaksNext || endsParagraph(line, next: next, fullLength: full))
                index += 1
            }
            _ = applyBreaks(upTo: Int.max)
        }
        return writer.finish()
    }

    // MARK: Строки

    /// Строки текста страницы, какими бы символами они ни были разделены.
    static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .components(separatedBy: "\n")
    }

    private static let ligatures: [Character: String] = [
        "\u{FB00}": "ff", "\u{FB01}": "fi", "\u{FB02}": "fl", "\u{FB03}": "ffi", "\u{FB04}": "ffl", "\u{FB05}": "st", "\u{FB06}": "st",
    ]

    /// Строка без управляющих символов, лигатур и двойных пробелов.
    static func clean(_ line: String) -> String {
        var result = ""
        result.reserveCapacity(line.count)
        var lastWasSpace = true
        for character in line {
            if let replacement = ligatures[character] {
                result += replacement
                lastWasSpace = false
            } else if character.isWhitespace || character == "\u{FEFF}" {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else if character == "\u{00AD}" || character.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .control }) {
                // Мягкий перенос внутри строки не виден и только мешает искать текст. В конце строки он нужен для склейки.
                continue
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        while result.last == " " { result.removeLast() }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("\u{00AD}"), !result.isEmpty { result.append("\u{00AD}") }
        return result
    }

    /// Склеивает конец абзаца со следующей строкой. Слово, перенесённое через дефис, снова целое.
    static func join(_ text: String, _ line: String) -> String {
        if text.hasSuffix("\u{00AD}") {
            return String(text.dropLast()) + line
        }
        if text.hasSuffix("-") || text.hasSuffix("\u{2010}") {
            let beforeHyphen = text.dropLast().last
            if beforeHyphen?.isLetter == true {
                // «приме-» + «чание» это одно слово, а «Нью-» + «Йорк» пишется с дефисом.
                return line.first?.isLowercase == true ? String(text.dropLast()) + line : text + line
            }
        }
        return text + " " + line
    }

    /// Кончается ли абзац на этой строке.
    static func endsParagraph(_ line: PDFLine, next: PDFLine?, fullLength: Int) -> Bool {
        guard let next, !next.text.isEmpty else { return true }
        let text = line.text
        if text.hasSuffix("-") || text.hasSuffix("\u{00AD}") || text.hasSuffix("\u{2010}") { return false }
        // Короткая строка: конец абзаца, строка стиха или пункт списка.
        if Double(text.count) < Double(fullLength) * 0.8 { return true }
        let terminal = text.last.map { ".!?…:;»\"”)".contains($0) } ?? false
        if terminal, let first = next.text.first, "—–•·▪".contains(first) { return true }
        // Другой размер шрифта: сноска, подпись или заголовок.
        if line.size > 0, next.size > 0, abs(line.size - next.size) > 1.5 { return true }
        return false
    }

    /// Длина полной строки текста: так видно, где строка кончилась раньше, то есть кончился абзац.
    static func typicalLineLength(_ pages: [[PDFLine]]) -> Int {
        let lengths = pages.flatMap { $0.map(\.text.count) }.filter { $0 >= 12 }.sorted()
        guard !lengths.isEmpty else { return 60 }
        return lengths[min(Int(Double(lengths.count) * 0.7), lengths.count - 1)]
    }

    /// Размер шрифта основного текста: им набрано больше всего символов.
    static func bodySize(_ pages: [[PDFLine]]) -> Double {
        var weights: [Double: Int] = [:]
        for lines in pages {
            for line in lines where line.size > 0 {
                weights[(line.size * 2).rounded() / 2, default: 0] += line.text.count
            }
        }
        return weights.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? 0
    }

    // MARK: Колонтитулы и номера страниц

    private static let pageNumberPattern = try! NSRegularExpression(pattern:
        #"^[\s\-–—\[\(\.\|•·]*(?:(?:[Сс]тр|[Сс]траница|[Pp]age|[Pp]|[Сс])\.?\s*)?(?:\d{1,4}|[ivxlcdm]{1,7})(?:\s*(?:из|of|/)\s*\d{1,4})?[\s\-–—\]\)\.\|•·]*$"#
    )

    /// Строка, в которой нет ничего, кроме номера страницы: «12», «— 12 —», «стр. 12», «xiv».
    static func isPageNumber(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 24 else { return false }
        return pageNumberPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Ключ колонтитула: без цифр, регистра и знаков, ведь номер страницы в нём каждый раз свой.
    static func runningKey(_ text: String) -> String {
        guard text.count <= 90 else { return "" }
        let letters = text.lowercased().unicodeScalars.map { CharacterSet.letters.contains($0) ? Character($0) : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    /// Слова, с которых начинаются названия глав: такие строки повторяются, но это не колонтитулы.
    private static let chapterWords: Set<String> = ["глава", "часть", "раздел", "лекция", "урок", "chapter", "part", "section", "lesson"]

    /// Убирает сверху и снизу каждой страницы номера страниц и строки, которые повторяются
    /// у края многих страниц: название книги, имя автора, название главы.
    static func stripRunningLines(_ pages: [[PDFLine]], bodySize: Double) -> [[PDFLine]] {
        let edge = 2
        func edgeLines(_ lines: [PDFLine]) -> [PDFLine] {
            let filled = lines.filter { !$0.text.isEmpty }
            return Array(filled.prefix(edge)) + Array(filled.dropFirst(edge).suffix(edge))
        }
        var counts: [String: Int] = [:]
        for lines in pages {
            for key in Set(edgeLines(lines).map { runningKey($0.text) }) where !key.isEmpty {
                counts[key, default: 0] += 1
            }
        }
        let threshold = max(3, min(Int((Double(pages.count) * 0.1).rounded(.up)), 8))
        func removable(_ line: PDFLine) -> Bool {
            // Крупный шрифт это заголовок, даже если он похож на номер.
            if bodySize > 0, line.size > bodySize * 1.15 { return false }
            if isPageNumber(line.text) { return true }
            let key = runningKey(line.text)
            guard !key.isEmpty, pages.count >= 4, (counts[key] ?? 0) >= threshold else { return false }
            return !chapterWords.contains(key) && !chapterWords.contains(String(key.prefix { $0 != " " }))
        }
        return pages.map { original in
            var lines = original
            var removed = 0
            var index = 0
            while index < lines.count, removed < edge {
                if lines[index].text.isEmpty { index += 1; continue }
                guard removable(lines[index]) else { break }
                lines.remove(at: index)
                removed += 1
            }
            removed = 0
            index = lines.count - 1
            while index >= 0, removed < edge {
                if lines[index].text.isEmpty { index -= 1; continue }
                guard removable(lines[index]) else { break }
                lines.remove(at: index)
                removed += 1
                index -= 1
            }
            return lines
        }
    }

    // MARK: Главы

    /// Только буквы и цифры в нижнем регистре: так название из закладок узнаётся в тексте страницы.
    static func squeeze(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Строки страницы, которыми набрано название: оно бывает разбито на две-три строки.
    static func findTitle(_ title: String, in lines: [PDFLine], from start: Int) -> (line: Int, length: Int)? {
        let target = squeeze(title)
        guard !target.isEmpty, start < lines.count else { return nil }
        for first in start..<lines.count {
            let head = squeeze(lines[first].text)
            guard !head.isEmpty else { continue }
            // «1 Введение» на странице при закладке «Введение».
            if head.count > target.count, head.hasSuffix(target), head.count <= target.count + 4 {
                return (first, 1)
            }
            var joined = ""
            var end = first
            while end < lines.count, end - first < 4 {
                let part = squeeze(lines[end].text)
                guard !part.isEmpty else { break }
                let candidate = joined + part
                guard target.hasPrefix(candidate) else { break }
                joined = candidate
                end += 1
                if joined == target { return (first, end - first) }
            }
        }
        return nil
    }

    /// Главы по закладкам PDF. Если закладка верхнего уровня одна (название книги), главы на уровень ниже.
    static func outlineBreaks(_ outline: [PDFOutlineItem], pages: [[PDFLine]]) -> [Break] {
        let tops = outline.filter { $0.level == 0 }
        let chapterLevel = tops.count == 1 && outline.contains { $0.level == 1 } ? 1 : 0
        var used: [Int: Int] = [:]
        var breaks: [Break] = []
        for item in outline where item.level >= chapterLevel && pages.indices.contains(item.page) {
            let lines = pages[item.page]
            let start = used[item.page] ?? 0
            let level = min(item.level - chapterLevel, 2)
            if let found = findTitle(item.title, in: lines, from: start) {
                breaks.append(Break(page: item.page, line: found.line, length: found.length, title: item.title, level: level))
                used[item.page] = found.line + found.length
            } else {
                breaks.append(Break(page: item.page, line: start, length: 0, title: item.title, level: level))
            }
        }
        return breaks
    }

    /// Главы по заголовкам, если закладок нет: строки, набранные крупнее основного текста.
    /// Самый крупный размер, который встречается хотя бы дважды, это главы, мельче подзаголовки.
    static func headingBreaks(_ pages: [[PDFLine]], bodySize: Double) -> [Break] {
        guard bodySize > 0 else { return [] }
        struct Heading { var page: Int; var line: Int; var length: Int; var title: String; var size: Double }
        var headings: [Heading] = []
        for (pageIndex, lines) in pages.enumerated() {
            var index = 0
            while index < lines.count {
                let line = lines[index]
                guard line.size >= bodySize * 1.25, (2...150).contains(line.text.count),
                      line.text.contains(where: { $0.isLetter || $0.isNumber }) else {
                    index += 1
                    continue
                }
                var heading = Heading(page: pageIndex, line: index, length: 1, title: line.text, size: line.size)
                while index + heading.length < lines.count, heading.length < 4 {
                    let next = lines[index + heading.length]
                    guard !next.text.isEmpty, abs(next.size - line.size) <= 0.5 else { break }
                    heading.title += " " + next.text
                    heading.length += 1
                }
                headings.append(heading)
                index += heading.length
            }
        }
        let sizes = Dictionary(grouping: headings) { ($0.size * 2).rounded() / 2 }
        guard let chapterSize = sizes.keys.sorted(by: >).first(where: { (sizes[$0]?.count ?? 0) >= 2 }) else { return [] }
        let smaller = sizes.keys.filter { $0 < chapterSize }.sorted(by: >)
        let breaks = headings.map { heading -> Break in
            let size = (heading.size * 2).rounded() / 2
            let level = size >= chapterSize ? 0 : (size == smaller.first ? 1 : 2)
            return Break(page: heading.page, line: heading.line, length: heading.length, title: heading.title, level: level)
        }
        // Сотни «глав» значат, что крупным набрано что-то другое: тогда это просто подзаголовки.
        if breaks.filter({ $0.level == 0 }).count > 400 {
            return breaks.map { var item = $0; item.level = max(item.level, 1); return item }
        }
        return breaks
    }

    /// Книга без глав режется на куски по страницам, чтобы длинный PDF не открывался одной огромной главой.
    static func chunkBreaks(pageCount: Int) -> [Break] {
        guard pageCount > chunkPages + 5 else { return [] }
        return stride(from: 0, to: pageCount, by: chunkPages).map { first in
            let last = min(first + chunkPages, pageCount)
            return Break(page: first, line: 0, length: 0, title: "Стр. \(first + 1)–\(last)", level: 0, showsHeading: false)
        }
    }

    // MARK: Запись

    /// Собирает главы и запоминает, где в тексте начинается каждая страница.
    struct Writer {
        var sections: [Section] = []
        var sectionStarts: [Int] = []
        var toc: [TocEntry] = []
        var pageStarts: [Int] = []
        /// Сколько страниц уже начались, но ещё не дали ни строки: их начало это следующий символ текста.
        var pendingPages = 0
        var title: String
        var isChapter = false
        var html = ""
        /// Символов в главе, без недописанного абзаца.
        var length = 0
        /// Символов в прошлых главах.
        var base = 0
        var paragraph = ""
        var headingCount = 0

        init(title: String) {
            self.title = title
        }

        /// Сквозной номер символа, который будет записан следующим.
        private var position: Int {
            base + length + (paragraph.isEmpty ? 0 : paragraph.utf16.count + 1)
        }

        private mutating func resolvePages() {
            guard pendingPages > 0 else { return }
            pageStarts += Array(repeating: position, count: pendingPages)
            pendingPages = 0
        }

        mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph
            paragraph = ""
            // Пробел в конце абзаца не виден, зато выделение через два абзаца совпадает с текстом PDF.
            html += "<p>\(HTML.escape(text)) </p>"
            length += text.utf16.count + 1
        }

        mutating func append(_ line: String, breakAfter: Bool) {
            resolvePages()
            paragraph = paragraph.isEmpty ? line : PDFTextLayout.join(paragraph, line)
            if breakAfter { flushParagraph() }
        }

        mutating func heading(_ text: String, level: Int) {
            flushParagraph()
            resolvePages()
            headingCount += 1
            let id = "pdf-h\(headingCount)"
            let tag = "h\(min(level, 2) + 1)"
            html += "<\(tag) id=\"\(id)\">\(HTML.escape(text)) </\(tag)>"
            length += text.utf16.count + 1
            if level > 0 {
                toc.append(TocEntry(title: text, section: sections.count, anchor: id, level: level))
            }
        }

        mutating func startSection(_ newTitle: String, showsHeading: Bool) {
            flushParagraph()
            // Глава без текста не нужна: её заголовки (если были) уходят в следующую.
            if length > 0 { closeSection() }
            title = newTitle
            isChapter = true
            toc.append(TocEntry(title: newTitle, section: sections.count, level: 0))
            if showsHeading { heading(newTitle, level: 0) }
        }

        private mutating func closeSection() {
            sections.append(Section(title: title, html: html))
            sectionStarts.append(base)
            base += length
            length = 0
            html = ""
        }

        mutating func finish() -> Book {
            flushParagraph()
            resolvePages()
            if length > 0 || sections.isEmpty { closeSection() }
            // Текст до первой главы (титул, предисловие без закладки) тоже есть в оглавлении.
            if sections.count > 1, toc.first?.section != 0 {
                toc.insert(TocEntry(title: sections[0].title, section: 0), at: 0)
            }
            // Заголовки после последней главы с текстом указывают на неё.
            let last = sections.count - 1
            toc = toc.map { var entry = $0; entry.section = min(entry.section, last); return entry }
            let index = PDFTextIndex(pages: pageStarts.map { min($0, base) }, sections: sectionStarts, length: base)
            return Book(sections: sections, toc: toc, index: index)
        }
    }
}
