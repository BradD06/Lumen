import Foundation
import LumenCore

/// Строка текста со страницы PDF и размер её шрифта (0, если он неизвестен).
/// Картинка со страницы тоже строка: без текста, с путём к файлу картинки.
struct PDFLine: Hashable, Sendable {
    var text: String
    var size: Double
    var image: String?
    /// Где строка на странице, в координатах страницы (ось Y вверх). По нему видно,
    /// где кончился абзац: строка оборвалась раньше края, следующая с отступом или ниже обычного.
    var frame: LineFrame?

    init(_ text: String, size: Double = 0, image: String? = nil, frame: LineFrame? = nil) {
        self.text = text
        self.size = size
        self.image = image
        self.frame = frame
    }
}

struct LineFrame: Hashable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var midX: Double { (minX + maxX) / 2 }
    var midY: Double { (minY + maxY) / 2 }
    var height: Double { maxY - minY }
}

/// Поля и шаг строк основного текста страницы.
struct PageMetrics: Hashable, Sendable {
    var left: Double
    var right: Double
    /// Обычное расстояние между строками одного абзаца.
    var spacing: Double
    /// Обычный просвет между строками абзаца (от низа строки до верха следующей) и обычная высота строки.
    var gap: Double = 0
    var lineHeight: Double = 0

    var width: Double { right - left }

    /// Строки с краями текста: самый частый левый край, правый край длинных строк, обычный шаг.
    static func of(_ lines: [PDFLine]) -> PageMetrics? {
        let frames = lines.filter { !$0.text.isEmpty }.compactMap(\.frame)
        guard frames.count >= 3 else { return nil }
        let rights = frames.map(\.maxX).sorted()
        let right = rights[min(Int(Double(rights.count) * 0.9), rights.count - 1)]
        let lefts = Dictionary(grouping: frames.map { ($0.minX).rounded() }, by: { $0 })
        guard let left = lefts.max(by: { $0.value.count < $1.value.count || ($0.value.count == $1.value.count && $0.key > $1.key) })?.key,
              right - left > 40 else { return nil }
        let steps = zip(frames, frames.dropFirst()).map { $0.midY - $1.midY }.filter { $0 > 0 }.sorted()
        let spacing = steps.isEmpty ? 0 : steps[steps.count / 2]
        let gaps = zip(frames, frames.dropFirst()).filter { $0.midY > $1.midY }.map { $0.minY - $1.maxY }.sorted()
        let heights = frames.map(\.height).sorted()
        return PageMetrics(
            left: left, right: right, spacing: spacing,
            gap: gaps.isEmpty ? 0 : gaps[gaps.count / 2],
            lineHeight: heights[heights.count / 2]
        )
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
        let cleaned = raw.map { $0.map { PDFLine(clean($0.text), size: $0.size, image: $0.image, frame: $0.frame) } }
        let body = bodySize(cleaned)
        let pages = stripRunningLines(cleaned, bodySize: body)
        var breaks = outline.isEmpty ? headingBreaks(pages, bodySize: body) : outlineBreaks(outline, pages: pages)
        if !breaks.contains(where: { $0.level == 0 }) {
            breaks += chunkBreaks(pageCount: pages.count)
        }
        breaks.sort { ($0.page, $0.line, $0.level) < ($1.page, $1.line, $1.level) }
        let full = typicalLineLength(pages)

        let allMetrics = pages.map(PageMetrics.of)
        let lefts = textLefts(allMetrics)
        var writer = Writer(title: frontTitle)
        var nextBreak = 0
        /// Открытая выноска: где начинаются её строки и последняя строка в ней (`nil` в начале выноски и страницы).
        var box: (left: Double, last: LineFrame?)?
        for (pageIndex, lines) in pages.enumerated() {
            writer.pendingPages += 1
            let metrics = allMetrics[pageIndex]
            let textLeft = lefts[pageIndex]
            var index = 0
            if let open = box {
                // Выноска с прошлой страницы продолжается, только если и здесь первые строки с тем же отступом.
                let shift = open.left - (pageIndex > 0 ? lefts[pageIndex - 1] ?? open.left : open.left)
                let first = lines.filter { !$0.text.isEmpty }.prefix(2)
                let continues = first.count == 2 && first.allSatisfy { line in
                    guard let frame = line.frame, let textLeft else { return false }
                    return abs(frame.minX - (textLeft + shift)) <= 3
                }
                if continues, let frame = first.first?.frame {
                    box = (frame.minX, nil)
                } else {
                    writer.closeBox()
                    box = nil
                }
            }
            func applyBreaks(upTo line: Int) -> Int {
                var consumed = 0
                while nextBreak < breaks.count,
                      breaks[nextBreak].page < pageIndex || (breaks[nextBreak].page == pageIndex && breaks[nextBreak].line <= line) {
                    let item = breaks[nextBreak]
                    nextBreak += 1
                    if item.level == 0, !item.showsHeading {
                        writer.startChunk(item.title)
                    } else if item.level == 0 {
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
                // Заголовок закрывает выноску.
                if writer.openBoxEnd == nil { box = nil }
                if consumed > 0 {
                    index += consumed
                    continue
                }
                let line = lines[index]
                if let open = box, !line.text.isEmpty {
                    // Выноска кончается, когда строки вернулись к краю текста или после неё просвет.
                    let inside = line.frame.map { frame in
                        guard abs(frame.minX - open.left) <= 3 else { return false }
                        guard let last = open.last, let spacing = metrics?.spacing, spacing > 0 else { return true }
                        return last.midY - frame.midY <= spacing * 1.8
                    } ?? false
                    if inside, let frame = line.frame {
                        box = (open.left, frame)
                    } else {
                        writer.closeBox()
                        box = nil
                    }
                }
                if box == nil, !line.text.isEmpty, let opened = boxStart(lines, at: index, textLeft: textLeft, metrics: metrics) {
                    writer.openBox(opened.kind, label: line.text)
                    box = (opened.left, nil)
                    index += 1
                    continue
                }
                if box == nil, writer.paragraph.isEmpty, inlineNote(line.text) {
                    writer.paragraphClass = "note"
                }
                if line.text.isEmpty {
                    if let image = line.image {
                        writer.image(image)
                    } else {
                        writer.flushParagraph()
                    }
                    index += 1
                    continue
                }
                // Картинка посреди предложения его не рвёт: она встанет после абзаца.
                let following = lines[(index + 1)...].firstIndex { $0.image == nil }
                let onThisPage = following != nil
                // Последняя строка страницы: абзац может продолжиться на следующей, тогда он склеивается.
                let nextPage = onThisPage ? nil : pages.indices.dropFirst(pageIndex + 1).first { later in pages[later].contains { !$0.text.isEmpty } }
                let next = following.map { lines[$0] } ?? nextPage.flatMap { later in pages[later].first { !$0.text.isEmpty } }
                let acrossPicture = (following ?? lines.count) > index + 1
                let breaksNext = nextBreak < breaks.count && breaks[nextBreak].page == pageIndex && breaks[nextBreak].line == index + 1
                let ends = endsParagraph(
                    line, next: next, edge: pictureEdge(lines, beside: line), sameColumn: onThisPage,
                    acrossPicture: acrossPicture, metrics: metrics, nextMetrics: nextPage.flatMap { allMetrics[$0] }, fullLength: full
                )
                writer.append(line.text, breakAfter: breaksNext || ends)
                index += 1
            }
            _ = applyBreaks(upTo: Int.max)
        }
        return writer.finish()
    }

    // MARK: Выноски

    /// Выноска: примечание, предупреждение или врезка с заголовком (в книгах её часто печатают на сером фоне).
    enum BoxKind: String {
        case note
        case warning
        case aside

        /// Как выноска выглядит в HTML: открывающий и закрывающий теги.
        var tags: (open: String, close: String) {
            switch self {
            case .note: ("<div class=\"note\">", "</div>")
            case .warning: ("<div class=\"note warning\">", "</div>")
            case .aside: ("<aside class=\"box\">", "</aside>")
            }
        }
    }

    private static let noteWords: [String: BoxKind] = [
        "примечание": .note, "замечание": .note, "заметка": .note, "на заметку": .note, "совет": .note, "подсказка": .note,
        "note": .note, "tip": .note, "hint": .note,
        "внимание": .warning, "предупреждение": .warning, "важно": .warning, "осторожно": .warning,
        "warning": .warning, "caution": .warning, "important": .warning,
    ]

    /// Строка, в которой только метка выноски: «ПРИМЕЧАНИЕ», «Внимание!», «Совет:».
    static func noteLabel(_ text: String) -> BoxKind? {
        guard text.count <= 30 else { return nil }
        let word = text.trimmingCharacters(in: CharacterSet(charactersIn: " :.!—–-•")).lowercased()
        return noteWords[word]
    }

    /// Абзац начинается с метки: «Примечание: ...», «Внимание. ...».
    static func inlineNote(_ text: String) -> Bool {
        guard let separator = text.firstIndex(where: { ":.".contains($0) }) else { return false }
        let rest = text[text.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        return !rest.isEmpty && noteLabel(String(text[..<separator])) != nil
    }

    /// Заголовок врезки: короткая строка заглавными буквами.
    static func isCapsTitle(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 6 && text.count <= 90 && text.contains(" ") && !letters.contains(where: \.isLowercase)
    }

    /// Обычный левый край текста на каждой странице. Берётся по всем страницам той же чётности:
    /// на странице с большой врезкой самый частый край это край врезки, а не текста.
    static func textLefts(_ metrics: [PageMetrics?]) -> [Double?] {
        var byParity: [[Double]] = [[], []]
        for (index, page) in metrics.enumerated() {
            if let left = page?.left { byParity[index % 2].append(left.rounded()) }
        }
        let usual = byParity.map { values -> Double? in
            Dictionary(grouping: values, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        }
        return metrics.indices.map { index in
            guard let page = metrics[index] else { return nil }
            guard let typical = usual[index % 2] ?? usual[1 - index % 2] else { return page.left }
            // Страница с другими полями (вставка, разворот) остаётся со своим краем.
            return abs(page.left - typical) <= max(page.width * 0.08, 20) ? min(typical, page.left) : page.left
        }
    }

    /// Начинается ли со строки `index` выноска: метка («ПРИМЕЧАНИЕ») или заголовок заглавными,
    /// а под ними строки с отступом от края текста. Возвращает вид выноски и где начинаются её строки.
    static func boxStart(_ lines: [PDFLine], at index: Int, textLeft: Double?, metrics: PageMetrics?) -> (kind: BoxKind, left: Double)? {
        guard let textLeft, let metrics else { return nil }
        let line = lines[index]
        let kind: BoxKind
        var needed = 1
        if let label = noteLabel(line.text) {
            kind = label
        } else if isCapsTitle(line.text) {
            kind = .aside
            needed = 2
        } else {
            return nil
        }
        let indent = max(metrics.width * 0.025, 6)
        let following = lines[(index + 1)...].filter { !$0.text.isEmpty }.prefix(needed)
        guard following.count == needed, let first = following.first?.frame,
              first.minX > textLeft + indent, first.minX < textLeft + metrics.width * 0.25,
              following.allSatisfy({ ($0.frame.map { abs($0.minX - first.minX) <= 3 }) ?? false }) else { return nil }
        return (kind, first.minX)
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
            } else if character == "\u{00AD}" || character == "\u{FFFC}" || character == "\u{FFFD}"
                        || character.unicodeScalars.allSatisfy({ [.control, .privateUse].contains($0.properties.generalCategory) }) {
                // Значок вместо картинки (￼) и символы из личной области шрифта в тексте не нужны.
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
    /// Без положения строк на странице абзацы угадываются по длине строки в буквах.
    /// С положением точнее: в выровненном тексте строки разной длины в буквах, но одной ширины.
    static func endsParagraph(
        _ line: PDFLine,
        next: PDFLine?,
        edge localEdge: Double? = nil,
        sameColumn: Bool = true,
        acrossPicture: Bool = false,
        metrics: PageMetrics? = nil,
        nextMetrics: PageMetrics? = nil,
        fullLength: Int
    ) -> Bool {
        guard let next, !next.text.isEmpty else { return true }
        let text = line.text
        if text.hasSuffix("-") || text.hasSuffix("\u{00AD}") || text.hasSuffix("\u{2010}") || text.hasSuffix("\u{2011}") { return false }
        if !sameColumn {
            return endsBeforePage(line, next: next, edge: localEdge, metrics: metrics, nextMetrics: nextMetrics, fullLength: fullLength)
        }
        // Перед картинкой кончилось предложение: скорее всего, кончился и абзац.
        if acrossPicture, let last = text.last, ".!?…:".contains(last) { return true }
        if let metrics, let frame = line.frame {
            // Строка кончилась заметно раньше соседних. Край берётся по соседним строкам, а не по странице:
            // рядом с картинкой текст идёт узкой колонкой, и её строки не короткие, а полные.
            let edge = min(metrics.right, localEdge ?? metrics.right)
            if frame.maxX < edge - max((edge - metrics.left) * 0.1, 12) { return true }
            guard let following = next.frame else { return false }
            // Следующая строка начинается со значка списка.
            if let first = next.text.first, "•·▪◦●■–—".contains(first) { return true }
            let indent = max(metrics.width * 0.025, 6)
            // Красная строка: эта строка от левого края, следующая с отступом.
            if frame.minX <= metrics.left + indent, following.minX > metrics.left + indent, following.minX < metrics.left + metrics.width * 0.3 {
                return true
            }
            // Просвет между строками больше обычного. Считается от низа строки до верха следующей:
            // значок посреди строки делает её выше, но просвет от этого не растёт.
            if !acrossPicture, metrics.lineHeight > 0, frame.minY - following.maxY > metrics.gap + max(metrics.lineHeight * 0.5, 3) { return true }
            // Следующая строка выше этой: другая колонка или текст не по порядку.
            if following.midY > frame.maxY { return true }
            return false
        }
        // Короткая строка: конец абзаца, строка стиха или пункт списка.
        if Double(text.count) < Double(fullLength) * 0.8 { return true }
        let terminal = text.last.map { ".!?…:;»\"”)".contains($0) } ?? false
        if terminal, let first = next.text.first, "—–•·▪".contains(first) { return true }
        // Другой размер шрифта: сноска, подпись или заголовок.
        if line.size > 0, next.size > 0, abs(line.size - next.size) > 1.5 { return true }
        return false
    }

    /// Кончается ли абзац на последней строке страницы. Строка с маленькой буквы на следующей
    /// странице продолжает предложение. Иначе абзац кончился, если последняя строка короткая
    /// или следующая страница начинается с красной строки или пункта списка.
    static func endsBeforePage(
        _ line: PDFLine, next: PDFLine, edge localEdge: Double? = nil,
        metrics: PageMetrics?, nextMetrics: PageMetrics?, fullLength: Int
    ) -> Bool {
        let text = line.text
        let terminal = text.last.map { ".!?…:;»\"”)".contains($0) } ?? false
        if !terminal, next.text.first?.isLowercase == true { return false }
        if let first = next.text.first, "•·▪◦●■".contains(first) { return true }
        if terminal, let first = next.text.first, "—–".contains(first) { return true }
        if let metrics, let frame = line.frame {
            let edge = min(metrics.right, localEdge ?? metrics.right)
            if frame.maxX < edge - max((edge - metrics.left) * 0.1, 12) { return true }
        } else if Double(text.count) < Double(fullLength) * 0.8 {
            return true
        }
        if let nextMetrics, let following = next.frame {
            let indent = max(nextMetrics.width * 0.025, 6)
            if following.minX > nextMetrics.left + indent, following.minX < nextMetrics.left + nextMetrics.width * 0.3 { return true }
        }
        // Другой размер шрифта: сноска, подпись или заголовок.
        if line.size > 0, next.size > 0, abs(line.size - next.size) > 1.5 { return true }
        return false
    }

    /// Где кончается строка, если справа от неё картинка: текст обтекает картинку узкой колонкой,
    /// и такие строки не короткие, а полные.
    static func pictureEdge(_ lines: [PDFLine], beside line: PDFLine) -> Double? {
        guard let frame = line.frame else { return nil }
        return lines.compactMap { picture -> Double? in
            guard picture.image != nil, let rect = picture.frame,
                  rect.minY < frame.maxY, rect.maxY > frame.minY, rect.minX >= frame.maxX - 4 else { return nil }
            return rect.minX
        }.min()
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
        #"^[\s\-–—\[\(\.\|•·]*(?:(?:[Сс]тр|[Сс]траница|[Pp]age|[Pp]|[Сс])\.?\s*)?(?:\d{1,4}|[ivxlcdm]{1,7}|[IVXLCDM]{2,7})(?:\s*(?:из|of|/)\s*\d{1,4})?[\s\-–—\]\)\.\|•·]*$"#
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

    /// Слова, с которых начинаются названия глав и пронумерованные подписи. Такие строки повторяются
    /// у края страниц и сами по себе («Глава 1», «Глава 2»), поэтому колонтитулом считаются, только
    /// если повторяется та же строка с тем же номером: «Глава 3. Тайна» вверху страниц третьей главы.
    private static let labelWords: Set<String> = [
        "глава", "часть", "раздел", "лекция", "урок", "задача", "упражнение", "пример", "рисунок", "таблица", "теорема",
        "chapter", "part", "section", "lesson", "exercise", "example", "figure", "table", "problem", "theorem",
    ]

    /// Ключ строки, которая начинается со слова из `labelWords`: буквы и цифры. Номер страницы
    /// у края колонтитула («Глава 3. Тайна 47») отбрасывается, номер главы остаётся.
    /// `nil`, если строка начинается с другого слова.
    static func labelKey(_ text: String) -> String? {
        guard text.count <= 90 else { return nil }
        let characters = text.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var words = String(characters).split(separator: " ").map(String.init)
        guard let first = words.first, labelWords.contains(first) else { return nil }
        func isNumber(_ word: String) -> Bool { word.allSatisfy(\.isNumber) }
        while words.filter(isNumber).count >= 2 {
            if let last = words.last, isNumber(last) { words.removeLast() } else { break }
        }
        return words.joined(separator: " ")
    }

    /// Число в начале или в конце короткой строки: так рядом с колонтитулом печатают номер страницы
    /// («Предварительные условия 23», «22 Введение»). `nil`, если числа там нет.
    static func edgeNumber(_ text: String) -> Int? {
        guard text.count <= 90 else { return nil }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2 else { return nil }
        for word in [words.last!, words.first!] {
            let digits = word.trimmingCharacters(in: CharacterSet(charactersIn: "|•·–—-()[]."))
            if (1...4).contains(digits.count), digits.allSatisfy(\.isASCII), let number = Int(digits) { return number }
        }
        return nil
    }

    /// Сдвиги между номером, напечатанным у края страницы, и её номером в файле, которые повторяются
    /// на многих страницах. Так узнаётся колонтитул с номером страницы, даже если текст в нём
    /// на каждой странице свой (название раздела).
    static func pageNumberOffsets(_ pages: [[PDFLine]], edges: [(top: [Int], bottom: [Int])]) -> Set<Int> {
        var counts: [Int: Int] = [:]
        for (pageIndex, lines) in pages.enumerated() {
            let indices = edges[pageIndex].top + edges[pageIndex].bottom
            let offsets = Set(indices.filter { labelKey(lines[$0].text) == nil }.compactMap { index in
                (edgeNumber(lines[index].text) ?? (isPageNumber(lines[index].text) ? Int(lines[index].text.filter(\.isNumber)) : nil))
                    .map { $0 - pageIndex }
            })
            for offset in offsets { counts[offset, default: 0] += 1 }
        }
        let needed = max(5, Int((Double(pages.count) * 0.1).rounded(.up)))
        return Set(counts.filter { $0.value >= needed }.map(\.key))
    }

    /// Есть ли среди страниц `pages` три в пределах шести подряд, считая страницу `page`.
    /// Так повторяется колонтитул даже короткой главы, а заголовок или фраза почти никогда.
    static func repeatsNearby(_ pages: [Int], around page: Int) -> Bool {
        let near = pages.filter { abs($0 - page) <= 5 }
        guard near.count >= 3 else { return false }
        return (page - 5...page).contains { start in near.filter { (start...start + 5).contains($0) }.count >= 3 }
    }

    /// Строки у верхнего и нижнего края страницы: сверху вниз и снизу вверх. Если места строк известны,
    /// край берётся по ним, а не по порядку строк: PDF часто хранит колонтитул после текста страницы.
    static func edgeLines(_ lines: [PDFLine], edge: Int) -> (top: [Int], bottom: [Int]) {
        let filled = lines.indices.filter { !lines[$0].text.isEmpty }
        var ordered = filled
        if filled.count > 1, filled.allSatisfy({ lines[$0].frame != nil }) {
            ordered = filled.sorted {
                let first = lines[$0].frame!.midY, second = lines[$1].frame!.midY
                return first != second ? first > second : $0 < $1
            }
        }
        let top = Array(ordered.prefix(edge))
        let bottom = Array(ordered.dropFirst(top.count).suffix(edge).reversed())
        return (top, bottom)
    }

    /// Убирает сверху и снизу каждой страницы номера страниц и строки, которые повторяются
    /// у края многих страниц: название книги, имя автора, название главы.
    static func stripRunningLines(_ pages: [[PDFLine]], bodySize: Double) -> [[PDFLine]] {
        let edge = 2
        let edges = pages.map { edgeLines($0, edge: edge) }
        var counts: [String: Int] = [:]
        var loosePages: [String: [Int]] = [:]
        var labelPages: [String: [Int]] = [:]
        for (pageIndex, lines) in pages.enumerated() {
            let indices = edges[pageIndex].top + edges[pageIndex].bottom
            for key in Set(indices.map { runningKey(lines[$0].text) }) where !key.isEmpty {
                counts[key, default: 0] += 1
                loosePages[key, default: []].append(pageIndex)
            }
            for key in Set(indices.compactMap { labelKey(lines[$0].text) }) where !key.isEmpty {
                labelPages[key, default: []].append(pageIndex)
            }
        }
        let threshold = max(3, min(Int((Double(pages.count) * 0.1).rounded(.up)), 8))
        let numberOffsets = pages.count >= 8 ? pageNumberOffsets(pages, edges: edges) : []

        /// Строка отделена от текста страницы просветом больше обычного, как колонтитул на поле.
        /// `nil`, если мест строк нет.
        func standsApart(_ line: PDFLine, from inner: PDFLine?, above: Bool, metrics: PageMetrics?) -> Bool? {
            guard let frame = line.frame, let metrics, metrics.lineHeight > 0 else { return nil }
            guard let other = inner?.frame else { return true }
            let gap = above ? frame.minY - other.maxY : other.minY - frame.maxY
            return gap > metrics.gap + max(metrics.lineHeight * 0.5, 3)
        }

        func removable(_ line: PDFLine, page: Int, apart: Bool?) -> Bool {
            // Крупный шрифт это заголовок, даже если он похож на номер.
            if bodySize > 0, line.size > bodySize * 1.15 { return false }
            if isPageNumber(line.text) { return true }
            guard pages.count >= 4 else { return false }
            // Колонтитул с номером этой страницы: название раздела меняется, номер идёт по порядку.
            if let number = edgeNumber(line.text), numberOffsets.contains(number - page) { return true }
            if let label = labelKey(line.text) {
                return apart != false && repeatsNearby(labelPages[label] ?? [], around: page)
            }
            let key = runningKey(line.text)
            guard !key.isEmpty else { return false }
            if (counts[key] ?? 0) >= threshold { return true }
            // Колонтитул короткой главы встречается реже, но на соседних страницах. Чтобы не убрать
            // повторившуюся реплику («— Да.»), он должен стоять на поле или быть хотя бы из двух слов.
            let separated = apart ?? key.contains(" ")
            return separated && repeatsNearby(loosePages[key] ?? [], around: page)
        }

        return pages.enumerated().map { pageIndex, original in
            let metrics = PageMetrics.of(original)
            var removed: Set<Int> = []
            /// Две строки на одной высоте: PDFKit иногда отдаёт номер страницы и название раздела отдельно.
            func sameBaseline(_ first: Int, _ second: Int) -> Bool {
                guard let one = original[first].frame, let two = original[second].frame else { return false }
                return abs(one.midY - two.midY) < min(one.height, two.height) * 0.5
            }
            func short(_ index: Int) -> Bool {
                original[index].text.count <= 90 && !(bodySize > 0 && original[index].size > bodySize * 1.15)
            }
            for (side, above) in [(edges[pageIndex].top, true), (edges[pageIndex].bottom, false)] {
                for index in side where !removed.contains(index) {
                    // Соседняя строка ближе к середине страницы. Номер страницы в той же строке не в счёт.
                    let neighbour = nearestInner(original, to: index, above: above, skipping: removed)
                    let apart = standsApart(original[index], from: neighbour, above: above, metrics: metrics)
                    let partners = side.filter { $0 != index && !removed.contains($0) && sameBaseline(index, $0) }
                    if removable(original[index], page: pageIndex, apart: apart) {
                        removed.insert(index)
                        // Остальное в строке колонтитула уходит вместе с ним.
                        for partner in partners where short(partner) { removed.insert(partner) }
                    } else if short(index), let partner = partners.first(where: { removable(original[$0], page: pageIndex, apart: apart) }) {
                        removed.insert(index)
                        removed.insert(partner)
                    } else {
                        break
                    }
                }
            }
            var lines = original.indices.filter { !removed.contains($0) }.map { original[$0] }
            // Пустые строки у краёв страницы не конец абзаца: текст продолжается на следующей.
            while let first = lines.first, first.text.isEmpty, first.image == nil { lines.removeFirst() }
            while let last = lines.last, last.text.isEmpty, last.image == nil { lines.removeLast() }
            return lines
        }
    }

    /// Ближайшая к строке `index` строка текста ближе к середине страницы (по месту, а если его нет, по порядку).
    private static func nearestInner(_ lines: [PDFLine], to index: Int, above: Bool, skipping: Set<Int>) -> PDFLine? {
        let others = lines.indices.filter { $0 != index && !skipping.contains($0) && !lines[$0].text.isEmpty }
        guard let frame = lines[index].frame else {
            return (above ? others.first { $0 > index } : others.last { $0 < index }).map { lines[$0] }
        }
        let inner = others.compactMap { other -> (Int, Double)? in
            guard let second = lines[other].frame else { return nil }
            let distance = above ? frame.midY - second.midY : second.midY - frame.midY
            return distance > min(frame.height, second.height) * 0.5 ? (other, distance) : nil
        }
        return inner.min { $0.1 < $1.1 }.map { lines[$0.0] }
    }

    // MARK: Главы

    /// Только буквы и цифры в нижнем регистре: так название из закладок узнаётся в тексте страницы.
    static func squeeze(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Строки страницы, которыми набрано название: оно бывает разбито на две-три строки.
    static func findTitle(_ title: String, in lines: [PDFLine], from start: Int) -> (line: Int, length: Int)? {
        let targets = titleVariants(title)
        guard !targets.isEmpty, start < lines.count else { return nil }
        for first in start..<lines.count {
            let head = squeeze(lines[first].text)
            guard !head.isEmpty else { continue }
            for target in targets {
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
        }
        return nil
    }

    /// Как название из закладок может быть набрано на странице. «Глава 1. Что такое оболочка»
    /// на первой странице главы часто стоит без слова «Глава»: большая цифра и название
    /// («1Что такое оболочка») или одно название.
    static func titleVariants(_ title: String) -> [String] {
        let full = squeeze(title)
        guard !full.isEmpty else { return [] }
        var variants = [full]
        let words = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 3, labelWords.contains(String(words[0])), words[1].allSatisfy(\.isNumber) || words[1].allSatisfy({ "ivxlcdm".contains($0) }) {
            let rest = squeeze(words.dropFirst(2).joined(separator: " "))
            if rest.count >= 4 {
                variants.append(squeeze(String(words[1])) + rest)
                variants.append(rest)
            }
        }
        return variants
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
        /// Класс следующего абзаца в HTML, например «note» у абзаца «Примечание: ...».
        var paragraphClass: String?
        /// Закрывающий тег открытой выноски.
        var openBoxEnd: String?
        var headingCount = 0
        /// Картинки, которые встретились посреди абзаца: они встанут сразу после него.
        var waitingImages: [String] = []
        /// Кусок книги без глав, который начнётся, когда кончится абзац: абзац не режется пополам.
        var waitingChunk: String?

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
            let style = paragraphClass.map { " class=\"\($0)\"" } ?? ""
            paragraphClass = nil
            html += "<p\(style)>\(HTML.escape(text)) </p>"
            length += text.utf16.count + 1
            for path in waitingImages { writeImage(path) }
            waitingImages = []
            if let chunk = waitingChunk {
                waitingChunk = nil
                startSection(chunk, showsHeading: false)
            }
        }

        /// Начинает выноску: метка или заголовок врезки отдельным абзацем, дальше её текст.
        mutating func openBox(_ kind: BoxKind, label: String) {
            closeBox()
            flushParagraph()
            resolvePages()
            let tags = kind.tags
            html += tags.open
            openBoxEnd = tags.close
            html += "<p class=\"label\">\(HTML.escape(label)) </p>"
            length += label.utf16.count + 1
        }

        /// Закрывает выноску, дописав её последний абзац.
        mutating func closeBox() {
            guard let end = openBoxEnd else { return }
            // Кусок книги, который ждёт конца абзаца, начнётся уже после выноски.
            let chunk = waitingChunk
            waitingChunk = nil
            flushParagraph()
            html += end
            openBoxEnd = nil
            if let chunk { startSection(chunk, showsHeading: false) }
        }

        /// Новый кусок книги без глав. Если абзац с прошлой страницы не кончился, кусок начнётся после него.
        mutating func startChunk(_ newTitle: String) {
            if paragraph.isEmpty {
                startSection(newTitle, showsHeading: false)
            } else {
                waitingChunk = newTitle
            }
        }

        mutating func append(_ line: String, breakAfter: Bool) {
            resolvePages()
            paragraph = paragraph.isEmpty ? line : PDFTextLayout.join(paragraph, line)
            if breakAfter { flushParagraph() }
        }

        /// Картинка со страницы. Текста в ней нет, поэтому места в тексте она не сдвигает.
        /// Посреди абзаца картинка ждёт его конца, чтобы не разорвать предложение.
        mutating func image(_ path: String) {
            if paragraph.isEmpty {
                resolvePages()
                writeImage(path)
            } else {
                waitingImages.append(path)
            }
        }

        private mutating func writeImage(_ path: String) {
            html += "<p class=\"image\"><img src=\"\(HTML.escape(path))\" alt=\"\"></p>"
        }

        mutating func heading(_ text: String, level: Int) {
            closeBox()
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
            closeBox()
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
            waitingChunk = nil
            closeBox()
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
