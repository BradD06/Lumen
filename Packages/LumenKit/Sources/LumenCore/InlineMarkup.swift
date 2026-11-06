import Foundation

/// Разметка текста блока на время правки: **жирный**, *курсив*, ++подчёркнутый++, ~~зачёркнутый~~,
/// `код` и [ссылка](адрес). В поле ввода видна сама разметка, а когда курсор уходит из блока,
/// текст рисуется уже оформленным. В базе хранятся фрагменты `TextRun`, разметка из них
/// собирается заново, поэтому старые блоки без оформления выглядят в поле как раньше.
public enum InlineMarkup {
    /// Разобранная разметка: фрагменты и где каждый символ текста стоит в разметке.
    public struct Parsed: Equatable, Sendable {
        public var runs: [TextRun]
        /// Для каждого символа текста без разметки: его место в разметке, в символах.
        public var sourceOffsets: [Int]
        /// Длина разметки в символах.
        public var sourceLength: Int

        public var plainText: String { runs.map(\.text).joined() }

        /// Место в разметке → место в тексте без неё (сколько символов текста стоит раньше).
        public func plainOffset(forSource offset: Int) -> Int {
            var low = 0
            var high = sourceOffsets.count
            while low < high {
                let middle = (low + high) / 2
                if sourceOffsets[middle] < offset { low = middle + 1 } else { high = middle }
            }
            return low
        }

        /// Выделение в тексте без разметки → выделение в разметке, без самих значков по краям.
        public func sourceRange(forPlain range: Range<Int>) -> Range<Int> {
            let count = sourceOffsets.count
            let lower = min(max(range.lowerBound, 0), count)
            let upper = min(max(range.upperBound, lower), count)
            let start = lower < count ? sourceOffsets[lower] : sourceLength
            guard upper > lower else { return start..<start }
            return start..<(sourceOffsets[upper - 1] + 1)
        }
    }

    // MARK: Разбор

    public static func parse(_ source: String) -> Parsed {
        let characters = Array(source)
        var builder = Builder()
        parse(characters, 0, characters.count, marks: [], link: nil, into: &builder)
        return Parsed(runs: builder.runs, sourceOffsets: builder.offsets, sourceLength: characters.count)
    }

    public static func runs(from source: String) -> [TextRun] {
        parse(source).runs
    }

    private struct Builder {
        var runs: [TextRun] = []
        var offsets: [Int] = []

        mutating func append(_ character: Character, at offset: Int, marks: Set<TextMark>, link: String?) {
            offsets.append(offset)
            if let last = runs.last, last.marks == marks, last.link == link {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append(TextRun(String(character), marks: marks, link: link))
            }
        }
    }

    /// Символы, которые снимают с себя смысл обратной косой чертой.
    private static let escapable: Set<Character> = ["*", "~", "+", "`", "[", "]", "(", ")", "\\"]

    private static func parse(
        _ c: [Character], _ start: Int, _ end: Int,
        marks: Set<TextMark>, link: String?, into builder: inout Builder
    ) {
        var i = start
        while i < end {
            let character = c[i]
            if character == "\\", i + 1 < end, escapable.contains(c[i + 1]) {
                builder.append(c[i + 1], at: i + 1, marks: marks, link: link)
                i += 2
                continue
            }
            if character == "`", !marks.contains(.code),
               let close = firstIndex(of: "`", in: c, from: i + 1, to: end), close > i + 1 {
                for k in (i + 1)..<close {
                    builder.append(c[k], at: k, marks: marks.union([.code]), link: link)
                }
                i = close + 1
                continue
            }
            if character == "[", link == nil, let found = linkAt(c, i, end) {
                parse(c, i + 1, found.textEnd, marks: marks, link: found.url, into: &builder)
                i = found.end + 1
                continue
            }
            if let (mark, width) = delimiter(c, i, end), !marks.contains(mark),
               i + width < end, !c[i + width].isWhitespace,
               let close = closing(mark, width: width, in: c, from: i + width + 1, to: end) {
                parse(c, i + width, close, marks: marks.union([mark]), link: link, into: &builder)
                i = close + width
                continue
            }
            builder.append(character, at: i, marks: marks, link: link)
            i += 1
        }
    }

    private static func firstIndex(of character: Character, in c: [Character], from start: Int, to end: Int) -> Int? {
        var j = start
        while j < end {
            if c[j] == character { return j }
            j += 1
        }
        return nil
    }

    /// Открывающий значок оформления в этом месте и его длина.
    private static func delimiter(_ c: [Character], _ i: Int, _ end: Int) -> (TextMark, Int)? {
        let next: Character? = i + 1 < end ? c[i + 1] : nil
        switch c[i] {
        case "*": return next == "*" ? (.bold, 2) : (.italic, 1)
        case "~" where next == "~": return (.strikethrough, 2)
        case "+" where next == "+": return (.underline, 2)
        default: return nil
        }
    }

    /// Закрывающий значок: перед ним не пробел и не обратная косая черта.
    /// У `**` и `*` берётся последняя пара в ряду звёздочек: `***x***` это жирный курсив.
    private static func closing(_ mark: TextMark, width: Int, in c: [Character], from start: Int, to end: Int) -> Int? {
        var j = start
        while j + width <= end {
            defer { j += 1 }
            let previous = c[j - 1]
            guard !previous.isWhitespace, previous != "\\" else { continue }
            switch mark {
            case .bold:
                guard c[j] == "*", c[j + 1] == "*", j + 2 >= end || c[j + 2] != "*" else { continue }
            case .italic:
                guard c[j] == "*", j + 1 >= end || c[j + 1] != "*", previous != "*" || j - 1 < start else { continue }
            case .strikethrough:
                guard c[j] == "~", c[j + 1] == "~", j + 2 >= end || c[j + 2] != "~" else { continue }
            case .underline:
                guard c[j] == "+", c[j + 1] == "+", j + 2 >= end || c[j + 2] != "+" else { continue }
            case .code:
                continue
            }
            return j
        }
        return nil
    }

    /// `[текст](адрес)`: где кончается текст, где закрывающая скобка и сам адрес без пробелов.
    private static func linkAt(_ c: [Character], _ i: Int, _ end: Int) -> (textEnd: Int, end: Int, url: String)? {
        var j = i + 1
        while j + 1 < end {
            if c[j] == "]", c[j - 1] != "\\", c[j + 1] == "(" { break }
            j += 1
        }
        guard j + 1 < end, j > i + 1 else { return nil }
        var k = j + 2
        while k < end, c[k] != ")" {
            if c[k].isWhitespace { return nil }
            k += 1
        }
        guard k < end, k > j + 2 else { return nil }
        return (j, k, String(c[(j + 2)..<k]))
    }

    // MARK: Сборка

    /// Разметка для фрагментов. Особые символы экранируются, только если без этого текст
    /// прочитался бы иначе: «2*3» остаётся «2*3», а «C++» не превращается в «C\+\+».
    public static func source(_ runs: [TextRun]) -> String {
        let target = normalized(runs)
        guard target.contains(where: { !$0.marks.isEmpty || $0.link != nil }) || target.contains(where: { needsEscaping($0.text) }) else {
            return target.map(\.text).joined()
        }
        let plain = render(target, escaping: false)
        if parse(plain).runs == target { return plain }
        let escaped = render(target, escaping: true)
        if parse(escaped).runs == target { return escaped }
        // Пробелы по краям оформленного куска разметка не держит: «** x**» не читается.
        return render(trimmingEdges(target), escaping: true)
    }

    private static func needsEscaping(_ text: String) -> Bool {
        text.contains { escapable.contains($0) }
    }

    private enum Token: Equatable {
        case link(String)
        case mark(TextMark)

        var open: String {
            switch self {
            case .link: "["
            case .mark(let mark): InlineMarkup.delimiter(for: mark)
            }
        }

        var close: String {
            switch self {
            case .link(let url): "](\(url))"
            case .mark(let mark): InlineMarkup.delimiter(for: mark)
            }
        }
    }

    public static func delimiter(for mark: TextMark) -> String {
        switch mark {
        case .bold: "**"
        case .italic: "*"
        case .underline: "++"
        case .strikethrough: "~~"
        case .code: "`"
        }
    }

    /// Порядок вложенности: ссылка снаружи, код внутри.
    private static let markOrder: [TextMark] = [.strikethrough, .underline, .bold, .italic, .code]

    private static func tokens(for run: TextRun) -> [Token] {
        var result: [Token] = []
        if let link = run.link, !link.isEmpty { result.append(.link(link)) }
        result += markOrder.filter(run.marks.contains).map(Token.mark)
        return result
    }

    private static func render(_ runs: [TextRun], escaping: Bool) -> String {
        var output = ""
        var open: [Token] = []
        for run in runs {
            let wanted = tokens(for: run)
            var common = 0
            while common < open.count, common < wanted.count, open[common] == wanted[common] { common += 1 }
            for token in open[common...].reversed() { output += token.close }
            for token in wanted[common...] { output += token.open }
            open = wanted
            if run.marks.contains(.code) || !escaping {
                output += run.text
            } else {
                for character in run.text {
                    if escapable.contains(character) { output.append("\\") }
                    output.append(character)
                }
            }
        }
        for token in open.reversed() { output += token.close }
        return output
    }

    /// Пробелы по краям оформленных кусков становятся обычным текстом.
    private static func trimmingEdges(_ runs: [TextRun]) -> [TextRun] {
        var result: [TextRun] = []
        for run in runs {
            guard !run.marks.isEmpty, !run.marks.contains(.code) else {
                result.append(run)
                continue
            }
            let core = run.text.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else {
                result.append(TextRun(run.text, link: run.link))
                continue
            }
            let leading = run.text.prefix { $0 == " " || $0 == "\t" }
            let trailing = String(run.text.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
            if !leading.isEmpty { result.append(TextRun(String(leading), link: run.link)) }
            result.append(TextRun(core, marks: run.marks, link: run.link))
            if !trailing.isEmpty { result.append(TextRun(trailing, link: run.link)) }
        }
        return normalized(result)
    }

    // MARK: Правка фрагментов

    /// Без пустых кусков, соседние с одинаковым оформлением склеены.
    public static func normalized(_ runs: [TextRun]) -> [TextRun] {
        var result: [TextRun] = []
        for run in runs where !run.text.isEmpty {
            let link = run.link?.isEmpty == true ? nil : run.link
            if let last = result.last, last.marks == run.marks, last.link == link {
                result[result.count - 1].text += run.text
            } else {
                result.append(TextRun(run.text, marks: run.marks, link: link))
            }
        }
        return result
    }

    private struct Letter {
        var character: Character
        var marks: Set<TextMark>
        var link: String?
    }

    private static func letters(_ runs: [TextRun]) -> [Letter] {
        runs.flatMap { run in run.text.map { Letter(character: $0, marks: run.marks, link: run.link) } }
    }

    private static func runs(_ letters: [Letter]) -> [TextRun] {
        normalized(letters.map { TextRun(String($0.character), marks: $0.marks, link: $0.link) })
    }

    /// Выделение без пробелов по краям: «жирный » делает жирным только слово.
    private static func trimmed(_ range: Range<Int>, in letters: [Letter]) -> Range<Int> {
        var lower = min(max(range.lowerBound, 0), letters.count)
        var upper = min(max(range.upperBound, lower), letters.count)
        while lower < upper, letters[lower].character.isWhitespace { lower += 1 }
        while upper > lower, letters[upper - 1].character.isWhitespace { upper -= 1 }
        return lower..<upper
    }

    /// Есть ли оформление у всего выделения (пробелы не в счёт).
    public static func hasMark(_ mark: TextMark, in runs: [TextRun], range: Range<Int>) -> Bool {
        let all = letters(runs)
        let range = trimmed(range, in: all)
        guard !range.isEmpty else { return false }
        return all[range].allSatisfy { $0.marks.contains(mark) || $0.character.isWhitespace }
    }

    /// Включает оформление на выделении, а если оно уже всё такое, снимает.
    public static func toggling(_ mark: TextMark, in runs: [TextRun], range: Range<Int>) -> [TextRun] {
        var all = letters(runs)
        let range = trimmed(range, in: all)
        guard !range.isEmpty else { return normalized(runs) }
        let removes = hasMark(mark, in: runs, range: range)
        for index in range {
            if removes {
                all[index].marks.remove(mark)
            } else {
                all[index].marks.insert(mark)
            }
        }
        return self.runs(all)
    }

    /// Ссылка на выделении. `nil` убирает её.
    public static func settingLink(_ url: String?, in runs: [TextRun], range: Range<Int>) -> [TextRun] {
        var all = letters(runs)
        let range = trimmed(range, in: all)
        guard !range.isEmpty else { return normalized(runs) }
        let link = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in range {
            all[index].link = link?.isEmpty == false ? link : nil
        }
        return self.runs(all)
    }

    /// Ссылка, на которой стоит выделение, если она одна на всём выделении.
    public static func link(in runs: [TextRun], range: Range<Int>) -> String? {
        let all = letters(runs)
        guard !all.isEmpty else { return nil }
        let range = trimmed(range, in: all)
        if range.isEmpty {
            let index = min(max(range.lowerBound - 1, 0), all.count - 1)
            return all[index].link
        }
        let links = Set(all[range].map(\.link))
        return links.count == 1 ? links.first ?? nil : nil
    }

    /// Всё оформление снято, текст остаётся.
    public static func clearingFormatting(in runs: [TextRun], range: Range<Int>) -> [TextRun] {
        var all = letters(runs)
        let range = trimmed(range, in: all)
        for index in range {
            all[index].marks = []
            all[index].link = nil
        }
        return self.runs(all)
    }

    /// Есть ли у фрагментов хоть какое-то оформление.
    public static func hasFormatting(_ runs: [TextRun]) -> Bool {
        runs.contains { !$0.marks.isEmpty || ($0.link?.isEmpty == false) }
    }
}
