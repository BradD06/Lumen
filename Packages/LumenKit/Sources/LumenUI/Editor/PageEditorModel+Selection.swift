import Foundation
import LumenCore
import LumenStorage

/// Редактор, в котором сейчас выделены блоки. Выделение бывает только в одном: клавиши
/// Delete и ⌘C в разделённом окне не должны трогать блоки соседней панели.
@MainActor
enum BlockSelectionOwner {
    static weak var current: PageEditorModel?
}

/// Координаты, в которых строки блоков сообщают свои рамки и рисуется рамка выделения.
enum EditorSpace {
    static let blocks = "lumen.editor.blocks"
}

/// Выделение нескольких блоков и правки сразу над всеми: удалить, скопировать,
/// переместить, вложить, поменять тип и цвет.
extension PageEditorModel {
    var hasBlockSelection: Bool { !selectedBlockIds.isEmpty }

    func isSelected(_ id: UUID) -> Bool { selectedBlockIds.contains(id) }

    /// Выделенные блоки без тех, чей предок тоже выделен, в порядке документа.
    var selectionRoots: [UUID] { BlockSelection.roots(selectedBlockIds, in: blocks) }

    /// Блоки, видные на экране, сверху вниз: без служебных колонок, границ листов и детей свёрнутых блоков.
    var visibleBlockIds: [UUID] {
        var result: [UUID] = []
        func walk(_ parent: UUID?) {
            for block in children(of: parent) where block.type != .sheetBreak {
                if !block.type.isLayout { result.append(block.id) }
                if block.type == .toggle, block.content.isCollapsed { continue }
                walk(block.id)
            }
        }
        walk(nil)
        return result
    }

    // MARK: Выделение

    func selectBlocks(_ ids: some Sequence<UUID>, anchor: UUID? = nil) {
        let wanted = Set(ids)
        let selectable = Set(blocks.lazy.filter { wanted.contains($0.id) && !$0.type.isLayout && $0.type != .sheetBreak }.map(\.id))
        guard !selectable.isEmpty else {
            clearSelection()
            return
        }
        if BlockSelectionOwner.current !== self {
            BlockSelectionOwner.current?.clearSelection()
            BlockSelectionOwner.current = self
        }
        if selectedBlockIds != selectable { selectedBlockIds = selectable }
        if let anchor { selectionAnchor = anchor }
        if textSelection != nil { textSelection = nil }
    }

    func clearSelection() {
        if !selectedBlockIds.isEmpty { selectedBlockIds = [] }
        selectionAnchor = nil
        selectionHead = nil
        if BlockSelectionOwner.current === self { BlockSelectionOwner.current = nil }
    }

    /// Нажатие на ручку блока: выделен только он; с ⇧ диапазон от начала выделения
    /// (или от блока с курсором), с ⌘ блок добавляется или убирается.
    func clickHandle(_ id: UUID, extend: Bool, toggle: Bool) {
        if extend, let anchor = selectionAnchor ?? focusedBlockId ?? selectionRoots.first, findBlock(anchor) != nil {
            selectBlocks(BlockSelection.range(from: anchor, to: id, in: visibleBlockIds), anchor: anchor)
        } else if toggle {
            var ids = selectedBlockIds
            if ids.contains(id) {
                ids.remove(id)
            } else {
                ids.insert(id)
            }
            selectBlocks(ids, anchor: id)
        } else {
            selectBlocks([id], anchor: id)
        }
        selectionHead = id
    }

    /// Esc в тексте: выделяется блок, в котором стоял курсор.
    @discardableResult
    func selectFocusedBlock() -> Bool {
        guard let id = focusedBlockId, findBlock(id) != nil else { return false }
        selectBlocks([id], anchor: id)
        selectionHead = id
        return true
    }

    /// ⌘A второй раз: все блоки страницы (вложенные идут со своими родителями).
    func selectAllBlocks() {
        var ids: [UUID] = []
        func walk(_ parent: UUID?) {
            for block in children(of: parent) where block.type != .sheetBreak {
                if block.type.isLayout {
                    walk(block.id)
                } else {
                    ids.append(block.id)
                }
            }
        }
        walk(nil)
        selectBlocks(ids, anchor: ids.first)
        selectionHead = ids.last
    }

    /// Стрелки при выделенных блоках: выделение переходит на соседний блок, с ⇧ растёт.
    func moveSelectionCursor(by offset: Int, extend: Bool) {
        let order = visibleBlockIds
        guard !order.isEmpty else { return }
        let selectedInOrder = order.filter { selectedBlockIds.contains($0) }
        let head = selectionHead.flatMap { order.contains($0) ? $0 : nil }
            ?? (offset < 0 ? selectedInOrder.first : selectedInOrder.last)
        guard let head, let index = order.firstIndex(of: head) else { return }
        let target = order[min(max(index + offset, 0), order.count - 1)]
        if extend {
            let anchor = selectionAnchor.flatMap { order.contains($0) ? $0 : nil } ?? head
            selectBlocks(BlockSelection.range(from: anchor, to: target, in: order), anchor: anchor)
        } else {
            selectBlocks([target], anchor: target)
        }
        selectionHead = target
    }

    /// Return при выделенных блоках: курсор в первый из них.
    func editSelection() {
        let target = selectionRoots.first { findBlock($0)?.type.hasText == true }
        clearSelection()
        if let target { focusRequest = target }
    }

    // MARK: Правки выделенного

    func deleteSelection() {
        let roots = selectionRoots
        guard let first = roots.first, let firstIndex = position(of: first) else { return }
        recordUndo()
        let removed = Set(roots.flatMap { subtree(of: $0) })
        let previous = blocks[..<firstIndex].last { $0.type.hasText && !removed.contains($0.id) }
        clearSelection()
        removeBlocks(removed)
        normalizeColumns()
        if blocks.isEmpty {
            insertBlock(in: nil, after: nil, type: .paragraph)
        }
        focusRequest = previous?.id ?? blocks.first { $0.type.hasText }?.id
    }

    /// Выделенные блоки с потомками для буфера обмена.
    var selectionClipboard: BlockClipboard {
        BlockClipboard.make(roots: selectionRoots, from: blocks)
    }

    /// Копия в буфер обмена: блоки целиком для вставки в Lumen и Markdown для других программ.
    func copySelection() {
        let clipboard = selectionClipboard
        guard !clipboard.blocks.isEmpty else { return }
        BlockPasteboard.write(clipboard, text: markdown(of: clipboard))
    }

    func cutSelection() {
        copySelection()
        BlockPasteboard.cutSyncedIds = Set(selectionClipboard.blocks.filter(\.isSyncedOriginal).map(\.id))
        deleteSelection()
    }

    /// Копии выделенных блоков сразу под последним из них. Выделенными становятся копии.
    func duplicateSelection() {
        let roots = selectionRoots
        guard let last = roots.last else { return }
        recordUndo()
        let copies = insertClipboard(BlockClipboard.make(roots: roots, from: blocks), after: last)
        selectBlocks(copies, anchor: copies.first)
        selectionHead = copies.last
    }

    /// Блоки из буфера обмена под `anchorId`. Пустой абзац, в котором стоял курсор, они заменяют.
    /// Возвращает `false`, если в буфере нет блоков Lumen.
    @discardableResult
    func pasteBlocks(after anchorId: UUID?) -> Bool {
        guard let clipboard = BlockPasteboard.read(), !clipboard.blocks.isEmpty else { return false }
        recordUndo()
        var anchor = anchorId.flatMap { findBlock($0) }
            ?? children(of: nil).last { $0.type != .sheetBreak }
        if anchor == nil {
            anchor = insertBlock(in: nil, after: children(of: nil).last?.id, type: .paragraph)
        }
        guard let anchor else { return false }
        // Скопированный синхронный блок вставляется его копией; вырезанный переезжает целиком.
        let moving = movingSyncedIds(in: clipboard)
        let pasted = insertClipboard(clipboard.referencingSynced(except: moving), after: anchor.id, keepingIds: moving)
        if anchor.type == .paragraph, anchor.text.isEmpty, children(of: anchor.id).isEmpty {
            removeBlocks([anchor.id])
        }
        clearSelection()
        // Курсор в конец последнего вставленного текста, как в Notion.
        let pastedIds = Set(pasted.flatMap { subtree(of: $0) })
        focusRequest = blocks.last { pastedIds.contains($0.id) && $0.type.hasText }?.id
        return true
    }

    /// Вставляет копии блоков сразу после `anchorId` на его уровне. Возвращает id новых корней.
    @discardableResult
    func insertClipboard(_ clipboard: BlockClipboard, after anchorId: UUID, keepingIds: Set<UUID> = []) -> [UUID] {
        guard let anchor = findBlock(anchorId) else { return [] }
        let siblings = children(of: anchor.parentBlockId)
        let index = siblings.firstIndex { $0.id == anchorId }
        let upper = index.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1].sortKey : nil }
        let keys = SortKey.sequence(count: clipboard.rootIds.count, after: anchor.sortKey, before: upper)
        let copies = clipboard.copies(pageId: pageId, parentId: anchor.parentBlockId, rootKeys: keys, keepingIds: keepingIds)
        appendBlocks(copies.blocks)
        reorder()
        scheduleSave()
        return copies.roots
    }

    /// Ставит блоки рядом с `targetId` на его уровне, по порядку и вплотную друг к другу.
    func moveBlocks(_ ids: [UUID], nextTo targetId: UUID, after: Bool) {
        let roots = BlockSelection.roots(Set(ids), in: blocks)
        guard !roots.isEmpty, let target = findBlock(targetId) else { return }
        let moving = Set(roots.flatMap { subtree(of: $0) })
        guard !moving.contains(targetId) else { return }
        let parent = target.parentBlockId
        let siblings = children(of: parent).filter { !moving.contains($0.id) }
        guard let index = siblings.firstIndex(where: { $0.id == targetId }) else { return }
        recordUndo()
        let lower = after ? siblings[index].sortKey : (index > 0 ? siblings[index - 1].sortKey : nil)
        let upper = after ? (index + 1 < siblings.count ? siblings[index + 1].sortKey : nil) : siblings[index].sortKey
        let keys = SortKey.sequence(count: roots.count, after: lower, before: upper)
        for (id, key) in zip(roots, keys) {
            update(id) {
                $0.parentBlockId = parent
                $0.sortKey = key
            }
        }
        reorder()
        normalizeColumns()
    }

    /// ⌥⌘↑ и ⌥⌘↓ при выделенных блоках одного уровня: вся группа сдвигается на одного соседа.
    func moveSelection(by offset: Int) {
        let roots = selectionRoots
        guard let first = roots.first, let block = findBlock(first) else { return }
        let parent = block.parentBlockId
        guard roots.allSatisfy({ findBlock($0)?.parentBlockId == parent }) else { return }
        let siblings = children(of: parent)
        let indices = roots.compactMap { id in siblings.firstIndex { $0.id == id } }
        guard let low = indices.min(), let high = indices.max() else { return }
        if offset < 0 {
            guard low > 0 else { return }
            moveBlocks(roots, nextTo: siblings[low - 1].id, after: false)
        } else {
            guard high + 1 < siblings.count else { return }
            moveBlocks(roots, nextTo: siblings[high + 1].id, after: true)
        }
    }

    /// Tab: выделенные блоки уровня первого из них уходят внутрь блока над ним.
    func indentSelection() {
        let roots = selectionRoots
        guard let first = roots.first, let firstBlock = findBlock(first) else { return }
        let parent = firstBlock.parentBlockId
        let siblings = children(of: parent)
        guard let index = siblings.firstIndex(where: { $0.id == first }), index > 0, siblings[index - 1].type.canNest else {
            return
        }
        let newParent = siblings[index - 1]
        let moving = roots.filter { findBlock($0)?.parentBlockId == parent }
        recordUndo()
        if newParent.content.isCollapsed {
            update(newParent.id) { $0.content.isCollapsed = false }
        }
        let keys = SortKey.sequence(count: moving.count, after: children(of: newParent.id).last?.sortKey)
        for (id, key) in zip(moving, keys) {
            update(id) {
                $0.parentBlockId = newParent.id
                $0.sortKey = key
            }
        }
        reorder()
    }

    /// ⇧Tab: вложенные выделенные блоки выходят на уровень выше, сразу за бывшим родителем.
    /// Блоки из колонки встают под рядом колонок на всю ширину листа.
    func outdentSelection() {
        let roots = selectionRoots.filter { outdentAnchor(of: $0) != nil }
        guard !roots.isEmpty else { return }
        recordUndo()
        var leftColumns = false
        // С конца: каждый следующий встаёт сразу за родителем, перед уже вынесенными.
        for id in roots.reversed() {
            guard let anchor = outdentAnchor(of: id) else { continue }
            let key = sortKey(in: anchor.parentBlockId, after: anchor.id, excluding: id)
            update(id) {
                $0.parentBlockId = anchor.parentBlockId
                $0.sortKey = key
            }
            reorder()
            leftColumns = leftColumns || anchor.type == .columnList
        }
        if leftColumns {
            normalizeColumns()
        }
    }

    /// «Превратить в» для всех выделенных блоков с текстом.
    func setTypeForSelection(_ type: BlockType) {
        guard type.hasText else { return }
        let targets = selectionRoots.filter { id in
            guard let block = findBlock(id) else { return false }
            return block.type.isConvertible && block.type != type
        }
        guard !targets.isEmpty else { return }
        recordUndo()
        for id in targets {
            update(id) { $0.type = type }
        }
    }

    func setSelectionTextColor(_ color: BlockColor?) {
        let targets = selectionRoots.filter { findBlock($0)?.type.hasText == true }
        guard !targets.isEmpty else { return }
        recordUndo()
        for id in targets {
            update(id) { $0.content.textColor = color }
        }
    }

    func setSelectionBackgroundColor(_ color: BlockColor?) {
        let targets = selectionRoots.filter { findBlock($0)?.type.hasText == true }
        guard !targets.isEmpty else { return }
        recordUndo()
        for id in targets {
            update(id) { $0.content.backgroundColor = color }
        }
    }

    /// Markdown скопированных блоков: корни идут подряд на верхнем уровне в порядке документа.
    func markdown(of clipboard: BlockClipboard) -> String {
        guard let page else { return clipboard.blocks.map(\.text).joined(separator: "\n") }
        let flat = clipboard.copies(pageId: pageId, parentId: nil, rootKeys: SortKey.sequence(count: clipboard.rootIds.count))
        let export = PageExport(
            page: page,
            blocks: flat.blocks,
            pageTitles: Dictionary(links.pages.map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { first, _ in first }),
            sourceTitles: Dictionary(links.sources.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        )
        return export.markdown(includesTitle: false).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
