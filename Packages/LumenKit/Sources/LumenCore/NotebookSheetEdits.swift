import CoreGraphics
import Foundation

/// Лист тетради, на котором нашлись слова, и кусок текста вокруг них.
public struct SheetMatch: Equatable, Sendable, Identifiable {
    public var sheet: Int
    public var snippet: String

    public var id: Int { sheet }

    public init(sheet: Int, snippet: String) {
        self.sheet = sheet
        self.snippet = snippet
    }
}

/// Перестановка листов и поиск по ним. Всё по номерам листов, без штрихов.
extension NotebookSheets {
    // MARK: Списки по листам

    /// Любой список «по номеру листа» после вставки листов `added` после листа `index` (или в конец).
    public static func insertingSheets<Value: Equatable>(
        _ added: [Value?],
        after index: Int?,
        into list: [Value?]?,
        sheetCount: Int
    ) -> [Value?]? {
        insertingValues(added, after: index, into: list, sheetCount: sheetCount)
    }

    /// Любой список «по номеру листа» без листа `index`.
    public static func removingSheet<Value: Equatable>(_ index: Int, from list: [Value?]?) -> [Value?]? {
        removingValue(index, from: list)
    }

    /// Любой список «по номеру листа» после того, как лист `from` переставили на место `to`.
    public static func movingSheet<Value>(_ list: [Value?]?, from: Int, to: Int, sheetCount: Int) -> [Value?]? {
        guard list != nil, (0..<sheetCount).contains(from), (0..<sheetCount).contains(to), from != to else { return list }
        var full = padded(list, to: sheetCount)
        let moved = full.remove(at: from)
        full.insert(moved, at: to)
        return normalized(full)
    }

    /// Новый номер каждого листа после того, как лист `from` переставили на место `to`.
    public static func sheetMapping(movingFrom from: Int, to: Int, count: Int) -> [Int] {
        var order = Array(0..<count)
        guard order.indices.contains(from), order.indices.contains(to) else { return order }
        let moved = order.remove(at: from)
        order.insert(moved, at: to)
        // `order[new] = old`, а нужно наоборот.
        var mapping = Array(0..<count)
        for (new, old) in order.enumerated() {
            mapping[old] = new
        }
        return mapping
    }

    // MARK: Текст листов

    /// Всё, что на листе можно прочитать: распознанный почерк и тексты на листе.
    public static func text(of content: BlockContent, sheet: Int) -> String {
        var parts: [String] = []
        if let texts = content.sheetTexts, texts.indices.contains(sheet), let ink = texts[sheet], !ink.isEmpty {
            parts.append(ink)
        }
        let count = NotebookLayout.sheetCount(of: content)
        for item in content.items ?? [] where item.kind == .text && !item.isEmpty {
            if NotebookLayout.sheetIndex(at: item.frame.midY, sheets: count) == sheet {
                parts.append(item.text)
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Листы, на которых есть все слова запроса (без учёта регистра и «ё»), с куском текста вокруг первого слова.
    public static func matches(_ query: String, in content: BlockContent, snippetRadius: Int = 32) -> [SheetMatch] {
        let words = query
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var result: [SheetMatch] = []
        for sheet in 0..<NotebookLayout.sheetCount(of: content) {
            let text = text(of: content, sheet: sheet)
            guard !text.isEmpty else { continue }
            let found = words.map { text.range(of: $0, options: options) }
            guard found.allSatisfy({ $0 != nil }), let first = found.first ?? nil else { continue }
            result.append(SheetMatch(sheet: sheet, snippet: snippet(of: text, around: first, radius: snippetRadius)))
        }
        return result
    }

    /// Кусок текста в одну строку вокруг найденного, с многоточиями по краям, если текст обрезан.
    static func snippet(of text: String, around range: Range<String.Index>, radius: Int) -> String {
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var piece = text[start..<end]
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { piece = "…" + piece }
        if end < text.endIndex { piece += "…" }
        return piece
    }
}
