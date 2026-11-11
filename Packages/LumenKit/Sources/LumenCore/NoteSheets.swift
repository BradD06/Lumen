import Foundation

/// Заметка из листов. Заметка не бесконечная: это листы A4, блоки верхнего уровня делятся
/// на листы границами `BlockType.sheetBreak`. Сколько помещается на лист, считается приблизительно
/// по тексту блоков на листе условной ширины: так «лист заполнен» одинаков на Mac, iPad и iPhone,
/// как бы ни переносились строки в окне.
public enum NoteSheets {
    /// Условный лист A4 в пунктах: по нему считается, сколько текста помещается.
    public static let width: Double = 640
    public static let height: Double = (width * 297 / 210).rounded()
    /// Поля листа на широком экране.
    public static let margin: Double = 44
    /// Шапка первого листа: значок, кнопки оформления и название.
    public static let headerHeight: Double = 120
    /// С этой доли лист считается заполненным: под ним предлагают новый.
    public static let fullShare: Double = 0.9

    static let blockSpacing: Double = 6
    static let nestIndent: Double = 26
    static let columnGap: Double = 16

    /// Ширина текста на условном листе.
    public static var textWidth: Double { width - 2 * margin }

    /// Место под блоки на листе: у первого часть занимает шапка с названием.
    public static func capacity(isFirst: Bool) -> Double {
        height - 2 * margin - (isFirst ? headerHeight : 0)
    }

    /// Один лист заметки.
    public struct Sheet: Identifiable, Equatable, Sendable {
        /// Номер листа с нуля.
        public var index: Int
        /// Граница, с которой начинается лист. У первого листа её нет.
        public var breakId: UUID?
        /// Блоки верхнего уровня на листе, без границы.
        public var blocks: [Block]

        public var id: UUID? { breakId }
        public var isFirst: Bool { index == 0 }

        public init(index: Int, breakId: UUID?, blocks: [Block]) {
            self.index = index
            self.breakId = breakId
            self.blocks = blocks
        }
    }

    /// Делит блоки верхнего уровня (в порядке документа) на листы. Лист есть всегда хотя бы один.
    public static func split(_ topLevel: [Block]) -> [Sheet] {
        var sheets = [Sheet(index: 0, breakId: nil, blocks: [])]
        for block in topLevel {
            if block.type == .sheetBreak {
                sheets.append(Sheet(index: sheets.count, breakId: block.id, blocks: []))
            } else {
                sheets[sheets.count - 1].blocks.append(block)
            }
        }
        return sheets
    }

    /// Сколько листов в заметке.
    public static func count(_ topLevel: [Block]) -> Int {
        1 + topLevel.reduce(0) { $0 + ($1.type == .sheetBreak ? 1 : 0) }
    }

    // MARK: Сколько места занимает текст

    /// Примерная высота блока вместе с вложенными на листе шириной `width`.
    public static func height(of block: Block, width: Double = textWidth, children: (UUID) -> [Block]) -> Double {
        let own: Double
        switch block.type {
        case .paragraph:
            own = textHeight(block.text, size: 17, width: width) + 4
        case .heading1:
            own = textHeight(block.text, size: 30, width: width) + 20
        case .heading2:
            own = textHeight(block.text, size: 24, width: width) + 16
        case .heading3:
            own = textHeight(block.text, size: 19, width: width) + 12
        case .bulletedList, .numberedList, .todo, .toggle:
            own = textHeight(block.text, size: 17, width: width - 28) + 4
        case .quote:
            own = textHeight(block.text, size: 17, width: width - 15) + 4
        case .callout:
            own = textHeight(block.text, size: 17, width: width - 56) + 28
        case .code:
            own = textHeight(block.text, size: 14, width: width - 24, charShare: 0.6, lineShare: 1.35) + 28
        case .divider:
            own = 22
        case .page:
            own = 30
        case .image:
            own = 280
        case .excerpt:
            own = textHeight(block.text, size: 17, width: width - 40) + 56
        case .drawing:
            own = DrawingArea.height(of: block.content) + 8
        case .columnList:
            return columnsHeight(block, width: width, children: children)
        case .column:
            return stackHeight(children(block.id), width: width, children: children)
        case .sheetBreak:
            return 0
        }
        if block.type == .toggle, block.content.isCollapsed { return own }
        let nested = children(block.id)
        guard !nested.isEmpty else { return own }
        return own + blockSpacing + stackHeight(nested, width: width - nestIndent, children: children)
    }

    /// Высота блоков, стоящих друг под другом.
    public static func stackHeight(_ blocks: [Block], width: Double = textWidth, children: (UUID) -> [Block]) -> Double {
        guard !blocks.isEmpty else { return 0 }
        let heights = blocks.map { height(of: $0, width: width, children: children) }
        return heights.reduce(0, +) + blockSpacing * Double(blocks.count - 1)
    }

    /// Какую долю листа занимают блоки: больше 1 значит, что они не помещаются.
    public static func share(of blocks: [Block], isFirst: Bool, children: (UUID) -> [Block]) -> Double {
        stackHeight(blocks, children: children) / capacity(isFirst: isFirst)
    }

    /// Первый блок листа, который уже не помещается. `nil`, если всё помещается
    /// или не помещается даже первый блок: его не перенести, лист просто длиннее.
    public static func overflowIndex(_ blocks: [Block], isFirst: Bool, children: (UUID) -> [Block]) -> Int? {
        let limit = capacity(isFirst: isFirst)
        var used = 0.0
        for (index, block) in blocks.enumerated() {
            let next = used + (index > 0 ? blockSpacing : 0) + height(of: block, children: children)
            if next > limit {
                return index > 0 ? index : nil
            }
            used = next
        }
        return nil
    }

    /// Блоки, перед которыми нужно поставить границы листов, чтобы каждый лист поместился.
    /// Уже стоящие границы остаются, новые встают только внутри переполненных листов.
    public static func paginate(_ topLevel: [Block], children: (UUID) -> [Block]) -> [UUID] {
        var breaks: [UUID] = []
        for sheet in split(topLevel) {
            var limit = capacity(isFirst: sheet.isFirst)
            var used = 0.0
            var isEmpty = true
            for block in sheet.blocks {
                let blockHeight = height(of: block, children: children)
                let next = used + (isEmpty ? 0 : blockSpacing) + blockHeight
                if next > limit, !isEmpty {
                    breaks.append(block.id)
                    limit = capacity(isFirst: false)
                    used = blockHeight
                } else {
                    used = next
                }
                isEmpty = false
            }
        }
        return breaks
    }

    // MARK: Внутреннее

    /// Высота текста: строки переносятся по примерной ширине буквы, пустая строка тоже строка.
    static func textHeight(_ text: String, size: Double, width: Double, charShare: Double = 0.52, lineShare: Double = 1.3) -> Double {
        let perLine = max(1, Int(max(width, 40) / (size * charShare)))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { total, line in
            total + max(1, (line.count + perLine - 1) / perLine)
        }
        return Double(max(lines, 1)) * size * lineShare
    }

    /// Колонки стоят рядом: высота ряда это высота самой длинной колонки.
    private static func columnsHeight(_ row: Block, width: Double, children: (UUID) -> [Block]) -> Double {
        let columns = children(row.id)
        guard !columns.isEmpty else { return 0 }
        let available = max(width - columnGap * Double(columns.count - 1), 40)
        let given = columns.compactMap(\.content.columnWidth).reduce(0, +)
        let free = columns.filter { $0.content.columnWidth == nil }.count
        let rest = free > 0 ? max(1 - given, 0) / Double(free) : 0
        return columns.map { column in
            let share = column.content.columnWidth ?? rest
            return stackHeight(children(column.id), width: available * max(share, 0.12), children: children)
        }.max() ?? 0
    }
}
