import Foundation

/// Блок, разобранный из вставленного Markdown. Текст хранится разметкой `InlineMarkup`.
public struct MarkdownBlock: Equatable, Sendable {
    public var type: BlockType
    /// Текст с разметкой (`**жирный**`, `[ссылка](адрес)`); у кода это сам код.
    public var source: String
    public var isChecked: Bool
    /// Вложенность: 0 верхний уровень, 1 пункт внутри пункта выше и так далее.
    public var depth: Int
    public var table: TableData?

    public init(type: BlockType, source: String = "", isChecked: Bool = false, depth: Int = 0, table: TableData? = nil) {
        self.type = type
        self.source = source
        self.isChecked = isChecked
        self.depth = depth
        self.table = table
    }

    /// Содержимое нового блока.
    public var content: BlockContent {
        var content = BlockContent(runs: type == .code ? (source.isEmpty ? [] : [TextRun(source)]) : InlineMarkup.runs(from: source))
        content.isChecked = isChecked
        content.table = table
        return content
    }
}

/// Вставка Markdown в заметку: заголовки, списки (с вложенностью), задачи, цитаты, код,
/// разделители и таблицы становятся блоками, как в Notion.
public enum MarkdownPaste {
    /// Что изменилось в тексте поля: общий начало и конец и вставленный кусок между ними.
    public static func difference(old: String, new: String) -> (prefix: String, inserted: String, suffix: String) {
        let oldChars = Array(old)
        let newChars = Array(new)
        var start = 0
        while start < oldChars.count, start < newChars.count, oldChars[start] == newChars[start] {
            start += 1
        }
        var oldEnd = oldChars.count
        var newEnd = newChars.count
        while oldEnd > start, newEnd > start, oldChars[oldEnd - 1] == newChars[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        return (String(newChars[..<start]), String(newChars[start..<newEnd]), String(newChars[newEnd...]))
    }

    /// Есть ли в разобранном что-то кроме простых строк. Простые строки вставляются как раньше:
    /// каждая строка новым блоком того же типа (в списке новыми пунктами).
    public static func hasStructure(_ blocks: [MarkdownBlock]) -> Bool {
        blocks.contains { $0.type != .paragraph || $0.depth > 0 }
    }

    public static func blocks(from text: String) -> [MarkdownBlock] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var result: [MarkdownBlock] = []
        // Отступы открытых уровней вложенности, по возрастанию.
        var indents: [Int] = []
        var index = 0
        // Разбирается пункт списка: его отступ всегда считается.
        var pendingList = false

        func depth(for indent: Int) -> Int {
            // Вложенными бывают только пункты списков и то, что стоит с отступом под ними.
            let underList = result.last.map { $0.type.isListItem || $0.depth > 0 } ?? false
            guard indent == 0 || underList || pendingList else {
                indents = [indent]
                return 0
            }
            while let last = indents.last, last > indent { indents.removeLast() }
            if let last = indents.last, last == indent { return indents.count - 1 }
            if indents.isEmpty, indent == 0 {
                indents = [0]
                return 0
            }
            indents.append(indent)
            return indents.count - 1
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            index += 1
            guard !trimmed.isEmpty else { continue }
            let indent = indentation(of: line)

            // Блок кода до закрывающих ```.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                while index < lines.count {
                    let codeLine = lines[index]
                    index += 1
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix(fence) { break }
                    code.append(String(codeLine.dropFirst(min(indent, indentation(of: codeLine)))))
                }
                let level = depth(for: indent)
                result.append(MarkdownBlock(type: .code, source: code.joined(separator: "\n"), depth: level))
                continue
            }

            // Таблица: строка с `|` и под ней строка-разделитель `|---|---|`.
            if trimmed.hasPrefix("|"), index < lines.count, isTableSeparator(lines[index]) {
                var rows = [cells(of: trimmed)]
                index += 1
                while index < lines.count {
                    let rowLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard rowLine.hasPrefix("|") else { break }
                    rows.append(cells(of: rowLine))
                    index += 1
                }
                let width = rows.map(\.count).max() ?? 1
                let table = TableData(rows: rows.map { row in
                    (row + Array(repeating: "", count: width - row.count)).map { TableCell(runs: InlineMarkup.runs(from: $0)) }
                })
                let level = depth(for: indent)
                result.append(MarkdownBlock(type: .table, depth: level, table: table))
                continue
            }

            var block = parseLine(trimmed)
            pendingList = block.type.isListItem
            block.depth = depth(for: indent)
            pendingList = false
            result.append(block)
        }
        // Вложенность не глубже, чем на уровень под предыдущим блоком.
        var previous = -1
        for i in result.indices {
            result[i].depth = min(result[i].depth, previous + 1)
            previous = result[i].depth
        }
        return result
    }

    // MARK: Строка

    static func parseLine(_ line: String) -> MarkdownBlock {
        if isDivider(line) { return MarkdownBlock(type: .divider) }

        if line.hasPrefix("#") {
            let level = line.prefix { $0 == "#" }.count
            let rest = line.dropFirst(level)
            if level <= 6, rest.first == " " {
                let type: BlockType = level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3
                return MarkdownBlock(type: type, source: inline(rest.trimmingCharacters(in: .whitespaces).trimmingTrailingHashes))
            }
        }

        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let rest = String(line.dropFirst(2))
            for (box, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where rest.hasPrefix(box) {
                return MarkdownBlock(type: .todo, source: inline(String(rest.dropFirst(4))), isChecked: checked)
            }
            if rest == "[ ]" || rest == "[x]" || rest == "[X]" {
                return MarkdownBlock(type: .todo, isChecked: rest != "[ ]")
            }
            return MarkdownBlock(type: .bulletedList, source: inline(rest))
        }

        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return MarkdownBlock(type: .numberedList, source: inline(String(rest.dropFirst(2))))
            }
        }

        if line.hasPrefix(">") {
            let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
            return MarkdownBlock(type: .quote, source: inline(rest))
        }

        return MarkdownBlock(type: .paragraph, source: inline(line))
    }

    /// `![подпись](адрес)` становится ссылкой, `__жирный__` знакомым `**жирный**`.
    static func inline(_ text: String) -> String {
        var text = text
        if let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[$1]($2)")
            text = text.replacingOccurrences(of: "[](", with: "[картинка](")
        }
        if let regex = try? NSRegularExpression(pattern: #"(?<![\w_])__(?=\S)(.+?)(?<=\S)__(?![\w_])"#) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "**$1**")
        }
        return text
    }

    static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    // MARK: Таблица

    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") || trimmed.hasPrefix("-") || trimmed.hasPrefix(":") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    /// Ячейки строки `| a | b |`: `\|` внутри ячейки это сам знак, `<br>` перевод строки.
    static func cells(of line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line {
            if escaped {
                current.append(character == "|" ? "|" : "\\")
                if character != "|" { current.append(character) }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current)
        // Внешние `|` дают пустые края.
        if line.hasPrefix("|") { cells.removeFirst() }
        if line.hasSuffix("|"), !line.hasSuffix("\\|"), !cells.isEmpty { cells.removeLast() }
        return cells.map {
            inline($0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "<br>", with: "\n")
                .replacingOccurrences(of: "<br/>", with: "\n")
                .replacingOccurrences(of: "<br />", with: "\n"))
        }
    }

    /// Ширина отступа строки: табуляция за четыре пробела.
    static func indentation(of line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 } else if character == "\t" { width += 4 } else { break }
        }
        return width
    }
}

extension BlockType {
    /// Пункт списка или задача: в Markdown они вкладываются отступом.
    var isListItem: Bool {
        self == .bulletedList || self == .numberedList || self == .todo
    }
}

private extension String {
    /// `## Заголовок ##` без закрывающих решёток.
    var trimmingTrailingHashes: String {
        guard hasSuffix("#") else { return self }
        let stripped = String(reversed().drop { $0 == "#" }.reversed())
        guard stripped.hasSuffix(" ") || stripped.isEmpty else { return self }
        return stripped.trimmingCharacters(in: .whitespaces)
    }
}
