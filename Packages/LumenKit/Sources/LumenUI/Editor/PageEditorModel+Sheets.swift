import Foundation
import LumenCore
import LumenStorage

/// Листы заметки: заметка не бесконечная, это листы A4. Под последним листом кнопка
/// «Добавить лист»; переполненный лист переносит лишнее на новый; листы переставляют,
/// соединяют и прикалывают к полке. Лист начинается с границы `sheetBreak` верхнего уровня.
extension PageEditorModel {
    /// Листы заметки по порядку. Лист есть всегда хотя бы один.
    var sheets: [NoteSheets.Sheet] {
        NoteSheets.split(children(of: nil))
    }

    var sheetCount: Int {
        NoteSheets.count(children(of: nil))
    }

    /// Какую долю листа занимают его блоки: больше 1 значит, что они не помещаются.
    func fillShare(of sheet: NoteSheets.Sheet) -> Double {
        NoteSheets.share(of: sheet.blocks, isFirst: sheet.isFirst) { children(of: $0) }
    }

    /// Первый блок листа, который не поместился и уедет на новый лист.
    func overflowIndex(of sheet: NoteSheets.Sheet) -> Int? {
        NoteSheets.overflowIndex(sheet.blocks, isFirst: sheet.isFirst) { children(of: $0) }
    }

    /// Есть ли в заметке лист, на который не помещается текст.
    var hasOverfullSheets: Bool {
        sheets.contains { overflowIndex(of: $0) != nil }
    }

    /// Новый пустой лист после последнего, курсор сразу на нём.
    func addSheet() {
        recordUndo()
        let topLevel = children(of: nil)
        let sheetBreak = insertBlock(in: nil, after: topLevel.last?.id, type: .sheetBreak)
        let first = insertBlock(in: nil, after: sheetBreak.id, type: .paragraph)
        focusRequest = first.id
        sheetScrollRequest = sheetCount - 1
    }

    /// Курсор на лист без блоков: на нём появляется пустой абзац.
    func startWriting(on sheet: NoteSheets.Sheet) {
        if let first = sheet.blocks.first {
            focusRequest = first.id
            return
        }
        recordUndo()
        let after = sheet.breakId
        focusRequest = insertBlock(in: nil, after: after, type: .paragraph).id
    }

    /// Блоки, которые не поместились на лист, уезжают на новый лист сразу после него.
    func moveOverflowToNewSheet(_ index: Int) {
        let all = sheets
        guard all.indices.contains(index), let overflow = overflowIndex(of: all[index]) else { return }
        recordUndo()
        insertSheetBreak(before: all[index].blocks[overflow].id)
        sheetScrollRequest = index + 1
    }

    /// Раскладывает всю заметку по листам: лишнее с каждого листа переезжает на следующий.
    /// Так длинная заметка из прежних версий, где листов не было, становится стопкой листов.
    func paginateAll() {
        let breaks = NoteSheets.paginate(children(of: nil)) { children(of: $0) }
        guard !breaks.isEmpty else { return }
        recordUndo()
        for id in breaks {
            insertSheetBreak(before: id)
        }
    }

    /// Граница листа перед блоком верхнего уровня.
    private func insertSheetBreak(before id: UUID) {
        let block = Block(
            pageId: pageId,
            type: .sheetBreak,
            sortKey: sortKey(in: nil, before: id)
        )
        appendBlocks([block])
        reorder()
    }

    /// Лист соединяется с предыдущим: граница между ними пропадает, блоки остаются.
    func mergeSheetWithPrevious(_ index: Int) {
        let all = sheets
        guard index > 0, all.indices.contains(index), let breakId = all[index].breakId else { return }
        recordUndo()
        removeBlocks([breakId])
    }

    /// Лист убирается вместе с тем, что на нём написано. Отменяется ⌘Z.
    func deleteSheet(_ index: Int) {
        let all = sheets
        guard all.count > 1, all.indices.contains(index) else { return }
        recordUndo()
        var removed = Set(all[index].blocks.flatMap { subtree(of: $0.id) })
        if let breakId = all[index].breakId {
            removed.insert(breakId)
        } else if let nextBreak = all[1].breakId {
            // Первый лист: следующий становится первым, его граница больше не нужна.
            removed.insert(nextBreak)
        }
        removeBlocks(removed)
        normalizeColumns()
        if blocks.isEmpty {
            insertBlock(in: nil, after: nil, type: .paragraph)
        }
        sheetScrollRequest = max(index - 1, 0)
    }

    /// Лист меняется местами с соседним: `-1` выше, `+1` ниже.
    func moveSheet(_ index: Int, by offset: Int) {
        var all = sheets
        let target = index + offset
        guard all.indices.contains(index), all.indices.contains(target) else { return }
        recordUndo()
        // Границы остаются на своих местах по счёту, переезжает только содержимое листов.
        let breaks = all.compactMap(\.breakId)
        all.swapAt(index, target)
        var order: [UUID] = []
        for (number, sheet) in all.enumerated() {
            if number > 0 { order.append(breaks[number - 1]) }
            order += sheet.blocks.map(\.id)
        }
        let keys = SortKey.sequence(count: order.count)
        for (id, key) in zip(order, keys) {
            update(id) { $0.sortKey = key }
        }
        reorder()
        sheetScrollRequest = target
    }

    // MARK: Полка

    /// Номер листа, приколотого к полке, или `nil`.
    var pinnedSheet: Int? {
        page?.shelfPin.map { min(max($0, 0), sheetCount - 1) }
    }

}

