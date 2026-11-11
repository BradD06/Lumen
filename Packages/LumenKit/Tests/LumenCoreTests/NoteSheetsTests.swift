import Foundation
import LumenCore
import Testing

struct NoteSheetsTests {
    private let pageId = UUID()

    private func blocks(_ items: [(BlockType, String)]) -> [Block] {
        let keys = SortKey.sequence(count: items.count)
        return zip(items, keys).map { item, key in
            Block(pageId: pageId, type: item.0, content: BlockContent(text: item.1), sortKey: key)
        }
    }

    private func noChildren(_: UUID) -> [Block] { [] }

    @Test func notesWithoutBreaksAreOneSheet() {
        let list = blocks([(.paragraph, "Один"), (.paragraph, "Два")])
        let sheets = NoteSheets.split(list)
        #expect(sheets.count == 1)
        #expect(sheets[0].blocks.map(\.text) == ["Один", "Два"])
        #expect(sheets[0].breakId == nil)
        #expect(NoteSheets.count(list) == 1)
        // Пустая заметка тоже один лист.
        #expect(NoteSheets.split([]).count == 1)
    }

    @Test func breaksSplitBlocksIntoSheets() {
        let list = blocks([(.paragraph, "А"), (.sheetBreak, ""), (.paragraph, "Б"), (.sheetBreak, "")])
        let sheets = NoteSheets.split(list)
        #expect(sheets.count == 3)
        #expect(sheets.map(\.index) == [0, 1, 2])
        #expect(sheets[1].breakId == list[1].id)
        #expect(sheets[1].blocks.map(\.text) == ["Б"])
        // Последний лист пустой: на нём ещё ничего не написали.
        #expect(sheets[2].blocks.isEmpty)
        #expect(NoteSheets.count(list) == 3)
    }

    @Test func shortNoteFitsAndLongNoteOverflows() {
        let short = blocks([(.heading1, "Лекция"), (.paragraph, "Немного текста")])
        #expect(NoteSheets.overflowIndex(short, isFirst: true, children: noChildren) == nil)
        #expect(NoteSheets.share(of: short, isFirst: true, children: noChildren) < 0.3)

        let paragraph = String(repeating: "Длинное предложение о реформах. ", count: 12)
        let long = blocks(Array(repeating: (.paragraph, paragraph), count: 20))
        let overflow = NoteSheets.overflowIndex(long, isFirst: true, children: noChildren)
        #expect(overflow != nil)
        #expect((overflow ?? 0) > 0)
        #expect(NoteSheets.share(of: long, isFirst: true, children: noChildren) > 1)
    }

    @Test func oneHugeBlockCannotBeMoved() {
        // Блок длиннее листа нельзя разрезать: лист просто вытягивается.
        let huge = blocks([(.paragraph, String(repeating: "слово ", count: 3000))])
        #expect(NoteSheets.overflowIndex(huge, isFirst: false, children: noChildren) == nil)
        #expect(NoteSheets.paginate(huge, children: noChildren).isEmpty)
    }

    @Test func paginateKeepsEverySheetWithinA4() {
        let paragraph = String(repeating: "Текст конспекта ", count: 20)
        let long = blocks(Array(repeating: (.paragraph, paragraph), count: 40))
        let breaks = NoteSheets.paginate(long, children: noChildren)
        #expect(!breaks.isEmpty)

        // Ставим границы туда, куда сказали, и проверяем, что все листы помещаются.
        var withBreaks: [Block] = []
        for block in long {
            if breaks.contains(block.id) {
                withBreaks.append(Block(pageId: pageId, type: .sheetBreak, sortKey: "a"))
            }
            withBreaks.append(block)
        }
        let sheets = NoteSheets.split(withBreaks)
        #expect(sheets.count == breaks.count + 1)
        for sheet in sheets {
            #expect(NoteSheets.overflowIndex(sheet.blocks, isFirst: sheet.isFirst, children: noChildren) == nil)
            #expect(!sheet.blocks.isEmpty)
        }
    }

    @Test func collapsedToggleHidesItsChildrenFromTheCount() {
        var toggle = Block(pageId: pageId, type: .toggle, content: BlockContent(text: "Раздел"), sortKey: "a")
        let child = Block(pageId: pageId, parentBlockId: toggle.id, content: BlockContent(text: String(repeating: "x ", count: 400)), sortKey: "a")
        let children: (UUID) -> [Block] = { $0 == toggle.id ? [child] : [] }
        let open = NoteSheets.height(of: toggle, children: children)
        toggle.content.isCollapsed = true
        let closed = NoteSheets.height(of: toggle, children: children)
        #expect(closed < open)
    }

    @Test func notesStandOnTheShelfOfTheirFolder() {
        let shelf = Folder(name: "Учёба", isShelf: true)
        let single = ShelfNote(id: UUID(), title: "Список литературы")
        let binder = ShelfNote(id: UUID(), title: "Конспекты", folderId: shelf.id, sheetCount: 12, shelfPin: 3)
        let groups = ShelfGroup.make(books: [], shelves: [shelf], notes: [single, binder])
        #expect(groups.count == 2)
        #expect(groups[0].singleSheets.map(\.id) == [single.id])
        #expect(groups[0].folders.isEmpty)
        #expect(groups[1].folders.map(\.id) == [binder.id])
        #expect(groups[1].pinned.map(\.id) == [binder.id])
        #expect(binder.pinnedSheet == 3)
        // Листы удалили: приколотый номер не выходит за последний лист.
        #expect(ShelfNote(id: UUID(), title: "", sheetCount: 2, shelfPin: 7).pinnedSheet == 1)
    }

    @Test func sheetWordsAgreeWithTheNumber() {
        #expect(ShelfNote.sheetsLabel(1) == "1 лист")
        #expect(ShelfNote.sheetsLabel(3) == "3 листа")
        #expect(ShelfNote.sheetsLabel(5) == "5 листов")
        #expect(ShelfNote.sheetsLabel(11) == "11 листов")
        #expect(ShelfNote.sheetsLabel(21) == "21 лист")
        #expect(ShelfNote.sheetsLabel(24) == "24 листа")
    }
}
