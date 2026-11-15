import Foundation
import LumenCore
import LumenStorage

/// Структура страницы: вложенность, перемещение блоков и колонки.
extension PageEditorModel {
    // MARK: Вложенность

    /// Вложен ли блок в обычный блок (а не лежит на верхнем уровне или прямо в колонке).
    func isNested(_ block: Block) -> Bool {
        guard let parent = self.findBlock(block.parentBlockId) else { return false }
        return !parent.type.isLayout
    }

    func canIndent(_ id: UUID) -> Bool {
        guard let block = findBlock(id) else { return false }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }), index > 0 else { return false }
        return siblings[index - 1].type.canNest
    }

    func canOutdent(_ id: UUID) -> Bool {
        outdentAnchor(of: id) != nil
    }

    /// Ряд колонок, в колонке которого блок лежит прямо. `nil`, если блок не в колонке.
    func columnRow(of id: UUID) -> Block? {
        guard let block = findBlock(id), let column = findBlock(block.parentBlockId), column.type == .column else {
            return nil
        }
        return findBlock(column.parentBlockId)
    }

    /// За чем блок встанет после ⇧Tab: за бывшим родителем, а из колонки за всем рядом колонок
    /// (так блок выходит из колонки на всю ширину листа, как в Notion).
    func outdentAnchor(of id: UUID) -> Block? {
        guard let block = findBlock(id) else { return nil }
        if isNested(block) {
            return findBlock(block.parentBlockId)
        }
        return columnRow(of: id)
    }

    /// Tab: блок становится последним ребёнком предыдущего соседа.
    func indent(_ id: UUID) {
        guard canIndent(id), let block = findBlock(id) else { return }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return }
        let newParent = siblings[index - 1]
        recordUndo()
        if newParent.content.isCollapsed {
            update(newParent.id) { $0.content.isCollapsed = false }
        }
        let key = SortKey.between(children(of: newParent.id).last?.sortKey, nil)
        update(id) {
            $0.parentBlockId = newParent.id
            $0.sortKey = key
        }
        reorder()
        focusRequest = id
    }

    /// ⇧Tab: блок выходит на уровень выше и встаёт сразу после бывшего родителя.
    func outdent(_ id: UUID) {
        outdent(id, recording: true)
    }

    func outdent(_ id: UUID, recording: Bool) {
        guard let anchor = outdentAnchor(of: id) else { return }
        if recording {
            recordUndo()
        }
        let key = sortKey(in: anchor.parentBlockId, after: anchor.id, excluding: id)
        update(id) {
            $0.parentBlockId = anchor.parentBlockId
            $0.sortKey = key
        }
        reorder()
        // Опустевшая колонка исчезает, ряд из одной колонки снова становится обычными блоками.
        if anchor.type == .columnList {
            normalizeColumns()
        }
        focusRequest = id
    }

    /// Пункт меню «Вынести из колонки»: блок встаёт под рядом колонок на всю ширину листа.
    func moveOutOfColumn(_ id: UUID) {
        guard columnRow(of: id) != nil else { return }
        outdent(id)
    }

    // MARK: Перемещение

    /// Ставит блок рядом с другим на его уровне: перед ним или после него.
    func moveBlock(_ id: UUID, nextTo targetId: UUID, after: Bool) {
        guard id != targetId, let target = findBlock(targetId), findBlock(id) != nil,
              !subtree(of: id).contains(targetId) else { return }
        recordUndo()
        let key = after
            ? sortKey(in: target.parentBlockId, after: targetId, excluding: id)
            : sortKey(in: target.parentBlockId, before: targetId, excluding: id)
        update(id) {
            $0.parentBlockId = target.parentBlockId
            $0.sortKey = key
        }
        reorder()
        normalizeColumns()
    }

    /// Ставит блок на место другого: при перетаскивании вниз он встаёт после цели, вверх перед ней.
    func moveBlock(_ id: UUID, onto targetId: UUID) {
        guard let from = position(of: id), let to = position(of: targetId) else { return }
        moveBlock(id, nextTo: targetId, after: from < to)
    }

    /// Сдвигает блок на одну позицию среди соседей вверх (`-1`) или вниз (`+1`).
    func moveBlock(_ id: UUID, by offset: Int) {
        guard let block = findBlock(id) else { return }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }), siblings.indices.contains(index + offset) else {
            return
        }
        moveBlock(id, nextTo: siblings[index + offset].id, after: offset > 0)
        focusRequest = id
    }

    // MARK: Колонки

    /// Ставит блок в колонку рядом с другим блоком, как при перетаскивании к правому краю в Notion.
    func placeBeside(_ id: UUID, _ targetId: UUID) {
        guard id != targetId, let target = findBlock(targetId), let moving = findBlock(id), !moving.type.isLayout,
              !subtree(of: id).contains(targetId) else { return }
        recordUndo()

        if let column = findBlock(target.parentBlockId), column.type == .column {
            // Цель уже в колонке: добавляем новую колонку справа от неё.
            let newColumn = insertBlock(in: column.parentBlockId, after: column.id, type: .column)
            update(id) {
                $0.parentBlockId = newColumn.id
                $0.sortKey = SortKey.between(nil, nil)
            }
        } else {
            // Ряд колонок встаёт на место цели, цель уходит в левую колонку, блок в правую.
            let row = Block(pageId: pageId, parentBlockId: target.parentBlockId, type: .columnList, sortKey: target.sortKey)
            let keys = SortKey.sequence(count: 2)
            let left = Block(pageId: pageId, parentBlockId: row.id, type: .column, sortKey: keys[0])
            let right = Block(pageId: pageId, parentBlockId: row.id, type: .column, sortKey: keys[1])
            appendBlocks([row, left, right])
            update(targetId) { $0.parentBlockId = left.id }
            update(id) {
                $0.parentBlockId = right.id
                $0.sortKey = SortKey.between(nil, nil)
            }
        }
        reorder()
        normalizeColumns()
        focusRequest = id
    }

    /// Блок выше на том же уровне: рядом с ним встанет новая колонка из меню блока.
    func previousSibling(of id: UUID) -> Block? {
        guard let block = findBlock(id) else { return nil }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        let previous = siblings[index - 1]
        return previous.type.isLayout ? nil : previous
    }

    /// Пункт меню «Поставить в колонку рядом»: блок встаёт справа от блока выше.
    func placeBesidePrevious(_ id: UUID) {
        guard let previous = previousSibling(of: id) else { return }
        placeBeside(id, previous.id)
    }

    /// Доли ширины колонок ряда, в сумме 1. Колонка без сохранённой ширины получает среднюю долю.
    func columnFractions(_ rowId: UUID) -> [Double] {
        let columns = children(of: rowId)
        guard !columns.isEmpty else { return [] }
        let saved = columns.compactMap(\.content.columnWidth).filter { $0 > 0 }
        let fallback = saved.isEmpty ? 1 : saved.reduce(0, +) / Double(saved.count)
        let raw = columns.map { column -> Double in
            guard let width = column.content.columnWidth, width > 0 else { return fallback }
            return width
        }
        let total = raw.reduce(0, +)
        return raw.map { $0 / total }
    }

    /// Сохраняет ширины колонок после перетаскивания разделителя.
    func setColumnFractions(_ rowId: UUID, _ fractions: [Double]) {
        let columns = children(of: rowId)
        guard columns.count == fractions.count, fractions != columnFractions(rowId) else { return }
        recordUndo()
        for (column, fraction) in zip(columns, fractions) {
            update(column.id) { $0.content.columnWidth = fraction }
        }
    }

    /// Убирает пустые колонки, а ряд из одной колонки разворачивает обратно в обычные блоки.
    func normalizeColumns() {
        var changed = true
        while changed {
            changed = false
            for column in blocks where column.type == .column && children(of: column.id).isEmpty {
                removeLayoutBlock(column.id)
                changed = true
                break
            }
            if changed { continue }
            for row in blocks where row.type == .columnList {
                let columns = children(of: row.id)
                guard columns.count <= 1 else { continue }
                let contents = columns.first.map { children(of: $0.id) } ?? []
                let siblings = children(of: row.parentBlockId)
                let index = siblings.firstIndex { $0.id == row.id }
                let lower = index.flatMap { $0 > 0 ? siblings[$0 - 1].sortKey : nil }
                let upper = index.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1].sortKey : nil }
                let keys = SortKey.sequence(count: contents.count, after: lower, before: upper)
                for (block, key) in zip(contents, keys) {
                    update(block.id) {
                        $0.parentBlockId = row.parentBlockId
                        $0.sortKey = key
                    }
                }
                for column in columns {
                    removeLayoutBlock(column.id)
                }
                removeLayoutBlock(row.id)
                reorder()
                changed = true
                break
            }
        }
    }

    /// Удаляет пустой служебный блок колонок. Детей у него к этому моменту уже нет.
    private func removeLayoutBlock(_ id: UUID) {
        removeBlocks([id])
    }
}
