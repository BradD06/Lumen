import Foundation

/// Строки блока «Оглавление» (`BlockType.tableOfContents`; в читалке своё `TableOfContents` для книг): заголовки страницы по порядку с отступом по уровню.
public enum PageContents {
    public struct Entry: Hashable, Sendable {
        public var id: UUID
        public var title: String
        /// 1, 2 или 3, как у заголовка.
        public var level: Int
        /// Отступ в шагах. Самый крупный заголовок на странице стоит без отступа:
        /// если на странице нет «Заголовка 1», вторые уровни не уезжают вправо.
        public var indent: Int

        public init(id: UUID, title: String, level: Int, indent: Int) {
            self.id = id
            self.title = title
            self.level = level
            self.indent = indent
        }
    }

    /// Подпись заголовка без текста.
    public static let untitled = "Без названия"

    /// Уровень заголовка или `nil` для остальных блоков.
    public static func level(of type: BlockType) -> Int? {
        switch type {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        default: nil
        }
    }

    /// Отступ уровня `level`, когда самый крупный заголовок на странице `topLevel`.
    public static func indent(level: Int, topLevel: Int) -> Int {
        max(level - topLevel, 0)
    }

    /// Строки оглавления из блоков в порядке чтения (как `PageExport.items`).
    public static func entries(_ blocks: [Block]) -> [Entry] {
        let headings = blocks.compactMap { block -> (Block, Int)? in
            level(of: block.type).map { (block, $0) }
        }
        let top = headings.map(\.1).min() ?? 1
        return headings.map { block, level in
            let title = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Entry(
                id: block.id,
                title: title.isEmpty ? untitled : title,
                level: level,
                indent: indent(level: level, topLevel: top)
            )
        }
    }
}
