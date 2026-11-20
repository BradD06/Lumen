import CoreGraphics
import Foundation

/// Страница PDF под листом тетради: на ней пишут от руки, как в Goodnotes.
public struct SheetBackground: Codable, Hashable, Sendable {
    /// PDF во вложениях.
    public var attachment: String
    /// Номер страницы в этом PDF, с нуля.
    public var page: Int

    public init(attachment: String, page: Int) {
        self.attachment = attachment
        self.page = page
    }
}

/// Листы тетради с PDF: какая страница под каким листом и что с ними, когда листы
/// добавляют и удаляют. Список хранится по номерам листов, без хвоста из пустых.
public enum NotebookSheets {
    public static func background(of content: BlockContent, sheet: Int) -> SheetBackground? {
        guard let list = content.sheetBackgrounds, list.indices.contains(sheet) else { return nil }
        return list[sheet]
    }

    /// Новые листы `added` (у чистого листа `nil`) после листа `index`, а если его нет, в конец.
    /// Страницы листов ниже уезжают вместе со своими листами.
    public static func inserting(
        _ added: [SheetBackground?],
        after index: Int?,
        into list: [SheetBackground?]?,
        sheetCount: Int
    ) -> [SheetBackground?]? {
        insertingValues(added, after: index, into: list, sheetCount: sheetCount)
    }

    /// Без листа `index`: страницы листов ниже поднимаются на его место.
    public static func removing(_ index: Int, from list: [SheetBackground?]?) -> [SheetBackground?]? {
        removingValue(index, from: list)
    }

    // MARK: Шаблоны листов

    /// Шаблон листа: свой, если его выбрали для этого листа, иначе шаблон всей тетради.
    public static func paper(of content: BlockContent, sheet: Int) -> PaperPattern {
        if let list = content.sheetPapers, list.indices.contains(sheet), let own = list[sheet] {
            return own
        }
        return content.paper ?? .lined
    }

    /// Свой шаблон листа `sheet`. Шаблон, равный шаблону всей тетради, не хранится.
    public static func settingPaper(_ pattern: PaperPattern, sheet: Int, in content: BlockContent) -> [PaperPattern?]? {
        let count = NotebookLayout.sheetCount(of: content)
        guard (0..<count).contains(sheet) else { return content.sheetPapers }
        var full = padded(content.sheetPapers, to: count)
        full[sheet] = pattern == (content.paper ?? .lined) ? nil : pattern
        return normalized(full)
    }

    /// Шаблоны листов после вставки листов `added` после листа `index` (или в конец).
    public static func insertingPapers(
        _ added: [PaperPattern?],
        after index: Int?,
        into list: [PaperPattern?]?,
        sheetCount: Int
    ) -> [PaperPattern?]? {
        insertingValues(added, after: index, into: list, sheetCount: sheetCount)
    }

    public static func removingPaper(_ index: Int, from list: [PaperPattern?]?) -> [PaperPattern?]? {
        removingValue(index, from: list)
    }

    // MARK: Списки по номерам листов

    static func insertingValues<Value: Equatable>(
        _ added: [Value?],
        after index: Int?,
        into list: [Value?]?,
        sheetCount: Int
    ) -> [Value?]? {
        var full = padded(list, to: sheetCount)
        let position = index.map { min(max($0 + 1, 0), full.count) } ?? full.count
        full.insert(contentsOf: added, at: position)
        return normalized(full)
    }

    static func removingValue<Value: Equatable>(_ index: Int, from list: [Value?]?) -> [Value?]? {
        guard var full = list, full.indices.contains(index) else { return list }
        full.remove(at: index)
        return normalized(full)
    }

    /// Страница целиком на листе, без искажения, по центру. Листы A4, поэтому страница A4
    /// занимает весь лист, а другие форматы оставляют поля.
    public static func fit(pageSize: CGSize, in sheet: CGRect) -> CGRect {
        guard pageSize.width > 0, pageSize.height > 0 else { return sheet }
        let scale = min(sheet.width / pageSize.width, sheet.height / pageSize.height)
        let size = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        return CGRect(
            x: sheet.midX - size.width / 2,
            y: sheet.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Пустая тетрадь: один чистый лист, на котором ничего нет. PDF встаёт вместо него.
    public static func isBlank(_ content: BlockContent, hasInk: Bool) -> Bool {
        NotebookLayout.sheetCount(of: content) == 1 && !hasInk
            && (content.items ?? []).isEmpty && background(of: content, sheet: 0) == nil
    }

    public static func padded<Value>(_ list: [Value?]?, to count: Int) -> [Value?] {
        var full = list ?? []
        if full.count < count {
            full += Array(repeating: nil, count: count - full.count)
        }
        return full
    }

    public static func normalized<Value>(_ list: [Value?]) -> [Value?]? {
        var list = list
        while let last = list.last, last == nil {
            list.removeLast()
        }
        return list.isEmpty ? nil : list
    }
}
