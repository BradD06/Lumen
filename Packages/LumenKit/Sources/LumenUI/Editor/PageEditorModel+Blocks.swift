import Foundation
import LumenCore
import LumenStorage

/// Правки блоков: текст, Return и Backspace, тип, цвет, удаление и копия.
extension PageEditorModel {
    // MARK: Блоки

    func focusFirstBlock() {
        focusRequest = blocks.first { $0.type.hasText }?.id ?? blocks.first?.id
    }

    /// Нажатие на пустое место под блоками: фокус в последний пустой абзац или новый абзац в конце.
    func focusEnd() {
        let topLevel = children(of: nil)
        if let last = topLevel.last, last.type == .paragraph, last.text.isEmpty {
            focusRequest = last.id
        } else {
            focusRequest = insertBlock(in: nil, after: topLevel.last?.id, type: .paragraph).id
        }
    }

    func updateText(_ id: UUID, to newText: String) {
        guard let block = findBlock(id) else { return }

        if newText.contains("\n"), block.type != .code {
            recordUndo()
            split(id, text: newText)
            return
        }

        // В коде Return переносит строку. Return на пустой последней строке выходит из блока.
        if block.type == .code, newText.hasSuffix("\n\n"), newText.count > block.text.count {
            recordUndo()
            leaveCodeBlock(id, text: String(newText.dropLast(2)))
            return
        }

        if block.type == .paragraph, let shortcut = MarkdownShortcut.match(newText) {
            recordUndo()
            update(id) {
                $0.type = shortcut.type
                $0.text = shortcut.remainder
            }
            if shortcut.type == .divider {
                focusRequest = insertBlock(after: id, type: .paragraph).id
            } else {
                // Блок другого типа рисуется новым полем: курсор нужно вернуть в него.
                focusRequest = id
            }
            return
        }

        guard block.text != newText else { return }
        recordUndo(typing: .block(id))
        update(id) { $0.text = newText }
    }

    /// Return в конце блока (на macOS приходит как submit, а не как перевод строки).
    func submit(_ id: UUID) {
        guard let block = findBlock(id) else { return }
        recordUndo()
        if block.type == .code {
            if block.text.hasSuffix("\n") {
                leaveCodeBlock(id, text: String(block.text.dropLast()))
            } else {
                update(id) { $0.text += "\n" }
                // Курсор переходит на новую строку в конце блока.
                focusRequest = id
            }
            return
        }
        split(id, text: block.text + "\n")
    }

    /// Второй Return подряд в блоке кода: лишняя пустая строка убирается, ниже появляется абзац.
    private func leaveCodeBlock(_ id: UUID, text: String) {
        update(id) { $0.text = text }
        focusRequest = insertBlock(after: id, type: .paragraph).id
    }

    /// Делит блок по переводам строки: первая строка остаётся, остальные становятся новыми блоками.
    /// Return в пустом пункте списка выходит из списка (или из вложенности), как в Notion.
    /// В раскрытом сворачиваемом блоке новые строки становятся его первыми детьми.
    private func split(_ id: UUID, text: String) {
        guard let block = findBlock(id) else { return }
        let lines = text.components(separatedBy: "\n")

        if block.type.continuation != .paragraph, lines.allSatisfy(\.isEmpty) {
            if isNested(block) {
                outdent(id, recording: false)
            } else {
                update(id) {
                    $0.type = .paragraph
                    $0.text = ""
                }
            }
            focusRequest = id
            return
        }

        update(id) { $0.text = lines[0] }

        let opensInside = block.type == .toggle && !block.content.isCollapsed
        var lastId = id
        for (offset, line) in lines.dropFirst().enumerated() {
            let content = BlockContent(text: line)
            if opensInside && offset == 0 {
                lastId = insertBlock(in: id, after: nil, type: .paragraph, content: content).id
            } else {
                let type = opensInside ? BlockType.paragraph : block.type.continuation
                lastId = insertBlock(after: lastId, type: type, content: content).id
            }
        }
        focusRequest = lastId
    }

    /// Меняет тип блока (из slash-меню или контекстного меню).
    /// «Страница» создаёт новую подстраницу и сразу открывает её, как в Notion.
    func setType(_ id: UUID, _ type: BlockType) {
        guard let block = findBlock(id) else { return }
        if type == .page {
            createSubpage(from: id, title: "", open: true)
            return
        }
        if type == .drawing {
            recordUndo()
            update(id) {
                $0.type = .drawing
                $0.text = ""
            }
            // Рисовать можно сразу. Абзац ниже нужен, чтобы продолжить писать текстом.
            insertBlock(after: id, type: .paragraph)
            focusRequest = nil
            activeDrawingId = id
            return
        }
        recordUndo()
        update(id) {
            $0.type = type
            if !type.hasText || block.text.hasPrefix("/") {
                $0.text = ""
            }
        }
        if type.hasText {
            focusRequest = id
        } else {
            focusRequest = insertBlock(after: id, type: .paragraph).id
        }
    }

    func toggleChecked(_ id: UUID) {
        recordUndo()
        update(id) { $0.content.isChecked.toggle() }
    }

    /// Свернуть или раскрыть сворачиваемый блок. Это не правка текста, поэтому в историю отмены не попадает.
    func toggleCollapsed(_ id: UUID) {
        update(id) { $0.content.isCollapsed.toggle() }
    }

    /// Пустой раскрытый сворачиваемый блок: первый абзац внутри него.
    func addFirstChild(to id: UUID) {
        recordUndo()
        update(id) { $0.content.isCollapsed = false }
        focusRequest = insertBlock(in: id, after: nil, type: .paragraph).id
    }

    func setTextColor(_ id: UUID, _ color: BlockColor?) {
        recordUndo()
        update(id) {
            $0.content.textColor = color
        }
    }

    func setBackgroundColor(_ id: UUID, _ color: BlockColor?) {
        recordUndo()
        update(id) {
            $0.content.backgroundColor = color
        }
    }

    /// Backspace в пустом блоке: особый блок сначала становится абзацем, вложенный абзац
    /// поднимается на уровень выше, пустой абзац удаляется. Возвращает `true`, если нажатие обработано.
    func backspaceInEmptyBlock(_ id: UUID) -> Bool {
        guard let block = findBlock(id), block.text.isEmpty else { return false }
        if block.type != .paragraph {
            recordUndo()
            update(id) { $0.type = .paragraph }
            return true
        }
        if isNested(block) {
            outdent(id)
            return true
        }
        // Пустой блок удаляется, курсор встаёт в конец блока выше. Единственный блок на странице остаётся.
        guard children(of: id).isEmpty, blocks.contains(where: { $0.id != id && $0.type.hasText }) else {
            return false
        }
        let isFirst = blocks.first { $0.type.hasText }?.id == id
        deleteBlock(id)
        if isFirst {
            // Выше блоков нет: как в Notion, курсор уходит в заголовок.
            focusRequest = nil
            focusTitleRequest = true
        }
        return true
    }

    /// Удаляет блок вместе со всеми вложенными.
    func deleteBlock(_ id: UUID) {
        guard let index = position(of: id) else { return }
        recordUndo()
        let removed = Set(subtree(of: id))
        let previous = blocks[..<index].last { $0.type.hasText && !removed.contains($0.id) }
        removeBlocks(removed)
        normalizeColumns()
        if blocks.isEmpty {
            insertBlock(in: nil, after: nil, type: .paragraph)
        }
        focusRequest = previous?.id ?? blocks.first?.id
    }

    /// Копия блока со всеми вложенными сразу под оригиналом.
    func duplicateBlock(_ id: UUID) {
        guard let original = findBlock(id), !original.type.isLayout else { return }
        recordUndo()
        var newIds: [UUID: UUID] = [:]
        for blockId in subtree(of: id) {
            newIds[blockId] = UUID()
        }
        var copies: [Block] = []
        for blockId in subtree(of: id) {
            guard var copy = findBlock(blockId), let newId = newIds[blockId] else { continue }
            copy.id = newId
            copy.createdAt = Date()
            copy.updatedAt = copy.createdAt
            if blockId == id {
                copy.sortKey = sortKey(in: original.parentBlockId, after: id)
            } else {
                copy.parentBlockId = copy.parentBlockId.flatMap { newIds[$0] }
            }
            copies.append(copy)
        }
        appendBlocks(copies)
        reorder()
        scheduleSave()
        focusRequest = newIds[id]
    }

    /// Номер пункта в нумерованном списке: считаются подряд идущие нумерованные соседи.
    func listNumber(for id: UUID) -> Int {
        guard let block = findBlock(id) else { return 1 }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return 1 }
        var number = 1
        var current = index - 1
        while current >= 0, siblings[current].type == .numberedList {
            number += 1
            current -= 1
        }
        return number
    }
}
