import Foundation
import LumenCore
import LumenStorage

/// Синхронные блоки: оригинал хранит общее содержимое в детях, копии на других страницах
/// показывают и правят его (см. `SyncedReference`, `SyncedBlockViews`).
extension PageEditorModel {
    /// Пустой синхронный блок на месте блока (slash-меню): курсор в первый абзац внутри.
    /// Блок с текстом, картинкой или вложенными блоками не стирается, а становится содержимым синхронного.
    func makeSynced(_ id: UUID) {
        guard let block = findBlock(id), block.type != .synced else { return }
        let isEmpty = block.type.hasText && block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isEmpty || !children(of: id).isEmpty {
            wrapInSynced([id])
            focusRequest = id
            return
        }
        recordUndo()
        update(id) {
            $0.type = .synced
            $0.text = ""
            $0.content.syncedFrom = nil
        }
        let inside = insertBlock(in: id, after: nil, type: .paragraph)
        insertBlock(after: id, type: .paragraph)
        focusRequest = inside.id
    }

    /// Блоки становятся содержимым нового синхронного блока, который встаёт на место первого.
    @discardableResult
    func wrapInSynced(_ ids: [UUID]) -> UUID? {
        let roots = BlockSelection.roots(Set(ids), in: blocks).filter { findBlock($0).map { !$0.type.isLayout && $0.type != .sheetBreak } ?? false }
        guard let first = roots.first.flatMap({ findBlock($0) }) else { return nil }
        recordUndo()
        let container = Block(
            pageId: pageId,
            parentBlockId: first.parentBlockId,
            type: .synced,
            sortKey: sortKey(in: first.parentBlockId, before: first.id)
        )
        appendBlocks([container])
        let keys = SortKey.sequence(count: roots.count)
        for (id, key) in zip(roots, keys) {
            update(id) {
                $0.parentBlockId = container.id
                $0.sortKey = key
            }
        }
        reorder()
        scheduleSave()
        clearSelection()
        return container.id
    }

    func wrapSelectionInSynced() {
        wrapInSynced(selectionRoots)
    }

    /// Синхронный блок в буфер обмена. Вставленный на другой странице, он станет его копией.
    func copySyncedBlock(_ id: UUID) {
        guard let block = findBlock(id), block.type == .synced else { return }
        let clipboard = BlockClipboard.make(roots: [id], from: blocks)
        BlockPasteboard.write(clipboard, text: markdown(of: clipboard))
        NoticeCenter.shared.show("Синхронный блок скопирован: вставьте его на любую страницу")
    }

    /// Оригинал перестаёт быть синхронным: его содержимое остаётся обычными блоками на месте,
    /// копии на других страницах покажут, что оригинала больше нет.
    func dissolveSynced(_ id: UUID) {
        guard let block = findBlock(id), block.isSyncedOriginal else { return }
        recordUndo()
        let inside = children(of: id)
        let siblings = children(of: block.parentBlockId)
        let index = siblings.firstIndex { $0.id == id }
        let upper = index.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1].sortKey : nil }
        let keys = SortKey.sequence(count: inside.count, after: block.sortKey, before: upper)
        for (child, key) in zip(inside, keys) {
            update(child.id) {
                $0.parentBlockId = block.parentBlockId
                $0.sortKey = key
            }
        }
        removeBlocks([id])
        reorder()
        scheduleSave()
    }

    /// Копия становится обычными блоками: содержимое оригинала, какое оно сейчас, встаёт
    /// на её место и дальше живёт само по себе.
    func unsyncCopy(_ id: UUID) async {
        guard let block = findBlock(id), var reference = block.content.syncedFrom else { return }
        reference.pageId = await syncedSourcePage(reference)
        let sourceBlocks: [Block]
        if reference.pageId == pageId {
            sourceBlocks = blocks
        } else {
            await OpenPageEditors.shared.model(for: reference.pageId)?.flush()
            sourceBlocks = (try? await database.blocks(of: reference.pageId)) ?? []
        }
        let inside = sourceBlocks
            .filter { $0.parentBlockId == reference.blockId }
            .sorted { ($0.sortKey, $0.id.uuidString) < ($1.sortKey, $1.id.uuidString) }
        // В порядке документа: родитель раньше детей.
        let ordered = BlockClipboard.make(roots: inside.map(\.id), from: Self.documentOrder(sourceBlocks))
        guard findBlock(id) != nil else { return }
        recordUndo()
        if !ordered.blocks.isEmpty {
            insertClipboard(ordered.referencingSynced(), after: id)
        }
        removeBlocks([id])
        reorder()
        scheduleSave()
    }

    /// Блоки страницы из базы в порядке документа.
    static func documentOrder(_ blocks: [Block]) -> [Block] {
        let grouped = Dictionary(grouping: blocks, by: \.parentBlockId).mapValues { siblings in
            siblings.sorted { ($0.sortKey, $0.id.uuidString) < ($1.sortKey, $1.id.uuidString) }
        }
        var result: [Block] = []
        func walk(_ parent: UUID?) {
            for block in grouped[parent] ?? [] {
                result.append(block)
                walk(block.id)
            }
        }
        walk(nil)
        return result
    }
}

extension PageEditorModel {
    /// Вырезанные оригиналы синхронных блоков в буфере вместе с содержимым. Они переезжают
    /// с прежними id, чтобы копии на других страницах их нашли. Вставить так можно один раз,
    /// следующая вставка того же буфера даёт обычную копию.
    func movingSyncedIds(in clipboard: BlockClipboard) -> Set<UUID> {
        let cut = BlockPasteboard.cutSyncedIds
        guard !cut.isEmpty else { return [] }
        BlockPasteboard.cutSyncedIds = []
        var moving = Set(clipboard.blocks.filter { cut.contains($0.id) && findBlock($0.id) == nil }.map(\.id))
        guard !moving.isEmpty else { return [] }
        var added = true
        while added {
            let next = clipboard.blocks.filter { block in
                !moving.contains(block.id) && block.parentBlockId.map(moving.contains) == true
            }
            added = !next.isEmpty
            moving.formUnion(next.map(\.id))
        }
        // Удаление вырезанного ещё могло не дойти до базы: оно отменяется, иначе стёрло бы переехавшее.
        cancelDeletes(moving)
        for pageId in Set(clipboard.blocks.map(\.pageId)) where pageId != self.pageId {
            OpenPageEditors.shared.model(for: pageId)?.cancelDeletes(moving)
        }
        return moving
    }

    /// Страница, где сейчас лежит оригинал: его могли перенести на другую страницу.
    func syncedSourcePage(_ reference: SyncedReference) async -> UUID {
        if findBlock(reference.blockId) != nil { return pageId }
        if let open = OpenPageEditors.shared.model(for: reference.pageId), open.findBlock(reference.blockId) != nil {
            return reference.pageId
        }
        return (try? await database.block(reference.blockId))?.pageId ?? reference.pageId
    }

    /// Копия запоминает новую страницу оригинала. Не правка человека, поэтому без отмены.
    func updateSyncedReference(_ id: UUID, to reference: SyncedReference) {
        guard findBlock(id)?.content.syncedFrom != reference else { return }
        update(id) { $0.content.syncedFrom = reference }
    }
}
