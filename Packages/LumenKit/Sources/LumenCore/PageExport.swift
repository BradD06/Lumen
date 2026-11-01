import Foundation

/// Страница со всем, что нужно для экспорта в Markdown или PDF: блоки по порядку и названия,
/// на которые ссылаются блоки (подстраницы, книги выписок).
public struct PageExport: Sendable {
    public var page: Page
    public var blocks: [Block]
    /// Названия страниц, на которые ссылаются блоки «Страница».
    public var pageTitles: [UUID: String]
    /// Названия книг, из которых сделаны выписки.
    public var sourceTitles: [UUID: String]

    public init(page: Page, blocks: [Block], pageTitles: [UUID: String] = [:], sourceTitles: [UUID: String] = [:]) {
        self.page = page
        self.blocks = blocks
        self.pageTitles = pageTitles
        self.sourceTitles = sourceTitles
    }

    /// Блок в порядке чтения.
    public struct Item: Hashable, Sendable {
        public var block: Block
        /// Глубина вложенности внутри списков и сворачиваемых блоков: в Markdown это отступ пункта.
        public var listDepth: Int
        /// Номер пункта нумерованного списка среди соседей.
        public var number: Int?
    }

    /// Все блоки страницы сверху вниз, как их видно в редакторе. Свёрнутые блоки раскрыты,
    /// колонки идут одна за другой, сами блоки-колонки пропускаются.
    public var items: [Item] {
        let ids = Set(blocks.map(\.id))
        var children: [UUID?: [Block]] = [:]
        for block in blocks {
            // Блок с потерянным родителем показывается на верхнем уровне, а не пропадает.
            let parent = block.parentBlockId.flatMap { ids.contains($0) ? $0 : nil }
            children[parent, default: []].append(block)
        }
        for key in children.keys {
            children[key]?.sort { ($0.sortKey, $0.createdAt) < ($1.sortKey, $1.createdAt) }
        }

        var result: [Item] = []
        var visited: Set<UUID> = []
        func walk(_ parent: UUID?, listDepth: Int) {
            var number = 0
            for block in children[parent] ?? [] where visited.insert(block.id).inserted {
                if block.type.isLayout {
                    walk(block.id, listDepth: listDepth)
                    number = 0
                    continue
                }
                number = block.type == .numberedList ? number + 1 : 0
                result.append(Item(block: block, listDepth: listDepth, number: block.type == .numberedList ? number : nil))
                walk(block.id, listDepth: block.type.isListLike ? listDepth + 1 : listDepth)
            }
        }
        walk(nil, listDepth: 0)
        return result
    }

    /// Картинки страницы: блоки-картинки по порядку, без повторов.
    public var imageNames: [String] {
        var seen: Set<String> = []
        return items.compactMap { item in
            guard item.block.type == .image, let name = item.block.content.attachment, seen.insert(name).inserted
            else { return nil }
            return name
        }
    }

    /// Имя файла по названию страницы: без символов, которые нельзя использовать в именах файлов.
    public var fileName: String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let cleaned = page.displayTitle.unicodeScalars
            .map { forbidden.contains($0) ? "-" : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Без названия" : String(cleaned.prefix(120))
    }

    /// Подпись выписки: книга и место в ней.
    public func excerptCaption(_ block: Block) -> String? {
        guard let excerpt = block.content.excerpt else { return nil }
        let parts = [sourceTitles[excerpt.sourceId], excerpt.label.isEmpty ? nil : excerpt.label].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    public func linkedTitle(_ block: Block) -> String {
        block.content.pageId.flatMap { pageTitles[$0] } ?? "Без названия"
    }
}

extension BlockType {
    /// Блоки, дети которых в Markdown становятся вложенными пунктами.
    var isListLike: Bool {
        switch self {
        case .bulletedList, .numberedList, .todo, .toggle: true
        default: false
        }
    }
}

// MARK: - Markdown

extension PageExport {
    /// Страница в Markdown. Картинки ссылаются на файлы по `imagePath`, по умолчанию `images/<имя>`.
    public func markdown(imagePath: (String) -> String = { "images/\($0)" }) -> String {
        var parts: [(text: String, isListItem: Bool)] = []
        // Иконка бывает эмодзи или именем системного значка: в файл попадает только эмодзи.
        let icon = page.icon.flatMap { $0.unicodeScalars.first.map(\.isASCII) == false ? "\($0) " : nil } ?? ""
        parts.append(("# \(icon)\(Self.escape(page.displayTitle))", false))

        for item in items {
            let block = item.block
            let indent = String(repeating: "    ", count: item.listDepth)
            let text = Self.inline(block.content.runs, continuation: indent)
            var line: String
            var isListItem = false
            switch block.type {
            case .paragraph:
                guard !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                line = Self.protectLineStart(text)
            case .heading1:
                line = "## \(text)"
            case .heading2:
                line = "### \(text)"
            case .heading3:
                line = "#### \(text)"
            case .bulletedList, .toggle:
                line = "- \(text)"
                isListItem = true
            case .numberedList:
                line = "\(item.number ?? 1). \(text)"
                isListItem = true
            case .todo:
                line = "- [\(block.content.isChecked ? "x" : " ")] \(text)"
                isListItem = true
            case .quote:
                line = Self.quoted(Self.inline(block.content.runs, continuation: ""), indent: indent)
            case .callout:
                line = Self.quoted("💡 " + Self.inline(block.content.runs, continuation: ""), indent: indent)
            case .code:
                let code = block.text
                let fence = code.contains("```") ? "~~~~" : "```"
                line = ([fence] + code.components(separatedBy: "\n") + [fence])
                    .joined(separator: "\n" + indent)
            case .divider:
                line = "---"
            case .page:
                line = "📄 \(Self.escape(linkedTitle(block)))"
            case .image:
                guard let name = block.content.attachment else { continue }
                line = "![](\(imagePath(name).replacingOccurrences(of: " ", with: "%20")))"
            case .excerpt:
                var quote = Self.inline(block.content.runs, continuation: "")
                if let caption = excerptCaption(block) {
                    quote += "\n\n— \(Self.escape(caption))"
                }
                line = Self.quoted(quote, indent: indent)
            case .drawing:
                // Штрихи в текст не перевести: в Markdown остаётся пометка, сам рисунок есть в PDF.
                guard block.drawing?.isEmpty == false else { continue }
                line = "_✍️ Рисунок от руки_"
            case .columnList, .column:
                continue
            }
            parts.append((indent + line, isListItem))
        }

        var result = ""
        for (index, part) in parts.enumerated() {
            if index > 0 {
                result += part.isListItem && parts[index - 1].isListItem ? "\n" : "\n\n"
            }
            result += part.text
        }
        return result + "\n"
    }

    /// Фрагменты текста с жирным, курсивом, кодом и ссылками.
    static func inline(_ runs: [TextRun], continuation: String) -> String {
        let text = runs.map { run -> String in
            var body = run.marks.contains(.code) ? Self.codeSpan(run.text) : Self.escape(run.text)
            // Пробелы по краям выносятся за знаки разметки, иначе Markdown её не узнает.
            let leading = String(body.prefix { $0 == " " })
            let trailing = String(body.reversed().prefix { $0 == " " })
            var core = String(body.dropFirst(leading.count).dropLast(trailing.count))
            guard !core.isEmpty else { return body }
            if run.marks.contains(.bold) { core = "**\(core)**" }
            if run.marks.contains(.italic) { core = "*\(core)*" }
            if run.marks.contains(.strikethrough) { core = "~~\(core)~~" }
            if run.marks.contains(.underline) { core = "<u>\(core)</u>" }
            if let link = run.link, !link.isEmpty {
                core = "[\(core)](\(link.replacingOccurrences(of: " ", with: "%20")))"
            }
            body = leading + core + trailing
            return body
        }
        .joined()
        // Перенос строки внутри блока остаётся переносом, а не склеивается в одну строку.
        return text.replacingOccurrences(of: "\n", with: "  \n" + continuation)
    }

    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]<".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    private static func codeSpan(_ text: String) -> String {
        text.contains("`") ? "`` \(text) ``" : "`\(text)`"
    }

    /// Абзац, который начинается как заголовок, цитата или пункт списка, не должен им стать.
    private static func protectLineStart(_ text: String) -> String {
        guard let first = text.first else { return text }
        if "#>-+".contains(first) {
            return "\\" + text
        }
        if let dot = text.firstIndex(of: "."), text[..<dot].allSatisfy(\.isNumber), dot != text.startIndex {
            return String(text[..<dot]) + "\\" + String(text[dot...])
        }
        return text
    }

    private static func quoted(_ text: String, indent: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n" + indent)
    }
}
