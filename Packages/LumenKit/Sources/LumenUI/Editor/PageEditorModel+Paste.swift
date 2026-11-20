import Foundation
import LumenCore

/// Вставка Markdown: заголовки, списки, задачи, цитаты, код, разделители и таблицы
/// из вставленного текста становятся блоками.
extension PageEditorModel {
    /// Поле блока получило вставку из нескольких строк (`old` → `new`, в разметке `InlineMarkup`).
    /// Возвращает true, если в ней нашёлся Markdown и она разложена по блокам.
    /// Простые строки без Markdown обрабатывает обычное деление блока по строкам.
    func pasteMarkdown(_ id: UUID, old: String, new: String) -> Bool {
        guard let block = findBlock(id), !block.type.isPlainText else { return false }
        let change = MarkdownPaste.difference(old: old, new: new)
        guard change.inserted.count > 1, change.inserted.contains("\n") else { return false }
        let parsed = MarkdownPaste.blocks(from: change.inserted)
        guard !parsed.isEmpty, MarkdownPaste.hasStructure(parsed) else { return false }
        recordUndo()
        // Пробелы по краям вставки остаются при тексте вокруг неё.
        let trailing = String(change.inserted.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
        let endsWithLine = change.inserted.dropLast(trailing.count).hasSuffix("\n")
        insertMarkdown(
            parsed,
            into: id,
            prefix: change.prefix,
            suffix: endsWithLine ? change.suffix : trailing + change.suffix,
            suffixOnNewLine: endsWithLine
        )
        return true
    }

    /// Первый блок вставки сливается с текущим (пустой абзац просто становится им),
    /// остальные встают ниже с вложенностью из отступов. Текст после курсора уходит в конец вставки.
    /// `suffixOnNewLine`: вставка кончалась переводом строки, и текст за курсором встаёт отдельным абзацем.
    func insertMarkdown(_ parsed: [MarkdownBlock], into id: UUID, prefix: String, suffix: String, suffixOnNewLine: Bool = false) {
        guard let block = findBlock(id), let first = parsed.first else { return }
        var pending = parsed[...]
        let minDepth = parsed.map(\.depth).min() ?? 0

        let takesOverBlock = block.type == .paragraph && prefix.trimmingCharacters(in: .whitespaces).isEmpty
        if takesOverBlock {
            pending.removeFirst()
            update(id) {
                $0.type = first.type
                let content = first.content
                $0.content.runs = content.runs
                $0.content.isChecked = content.isChecked
                $0.content.table = content.table
            }
        } else if first.type.hasText, !first.type.isPlainText {
            pending.removeFirst()
            update(id) { $0.content.runs = InlineMarkup.runs(from: prefix + first.source) }
        } else {
            update(id) { $0.content.runs = InlineMarkup.runs(from: prefix) }
        }

        // Последний вставленный блок на каждом уровне вложенности.
        var chain: [UUID] = [id]
        var lastId = id
        for item in pending {
            let depth = min(max(item.depth - minDepth, 0), chain.count)
            let parentId = depth == 0 ? block.parentBlockId : chain[depth - 1]
            let afterId: UUID? = depth < chain.count ? chain[depth] : nil
            let inserted = insertBlock(in: parentId, after: afterId, type: item.type, content: item.content)
            chain = Array(chain.prefix(depth)) + [inserted.id]
            lastId = inserted.id
        }

        // Текст, что стоял за курсором, дописывается к концу вставки.
        if !suffix.isEmpty, let last = findBlock(lastId) {
            if last.type.hasText, !last.type.isPlainText, !suffixOnNewLine {
                update(lastId) { $0.content.runs = InlineMarkup.runs(from: InlineMarkup.source($0.content.runs) + suffix) }
            } else {
                lastId = insertBlock(after: lastId, type: .paragraph, content: BlockContent(runs: InlineMarkup.runs(from: suffix))).id
            }
        }

        if let last = findBlock(lastId), last.type.hasText {
            focusRequest = lastId
        } else {
            focusRequest = insertBlock(after: lastId, type: .paragraph).id
        }
    }
}
