import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct BlockSelectionModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func open(_ lines: String) async throws -> (PageEditorModel, UUID, [UUID]) {
        let page = try await db.createQuickNote("Страница\n" + lines)
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        return (model, page.id, model.blocks.map(\.id))
    }

    private func texts(_ model: PageEditorModel, in parent: UUID? = nil) -> [String] {
        model.children(of: parent).map(\.text)
    }

    @Test func handleClicksSelectRangeAndToggle() async throws {
        let (model, _, ids) = try await open("а\nб\nв\nг")
        model.clickHandle(ids[1], extend: false, toggle: false)
        #expect(model.selectedBlockIds == [ids[1]])
        model.clickHandle(ids[3], extend: true, toggle: false)
        #expect(model.selectedBlockIds == Set(ids[1...3]))
        model.clickHandle(ids[2], extend: false, toggle: true)
        #expect(model.selectedBlockIds == [ids[1], ids[3]])
        model.clearSelection()
        #expect(!model.hasBlockSelection)
    }

    @Test func onlyOneEditorKeepsSelection() async throws {
        let (first, _, firstIds) = try await open("а")
        let (second, _, secondIds) = try await open("б")
        first.selectBlocks([firstIds[0]])
        second.selectBlocks([secondIds[0]])
        #expect(!first.hasBlockSelection, "Выделение в другом редакторе снимает это")
        #expect(second.hasBlockSelection)
        second.clearSelection()
    }

    @Test func deleteSelectionRemovesAllAndUndoes() async throws {
        let (model, pageId, ids) = try await open("а\nб\nв\nг")
        model.selectBlocks([ids[1], ids[2]])
        model.deleteSelection()
        #expect(texts(model) == ["а", "г"])
        #expect(!model.hasBlockSelection)
        await model.flush()
        #expect(try await db.blocks(of: pageId).map(\.text).sorted() == ["а", "г"])

        model.undo()
        #expect(texts(model) == ["а", "б", "в", "г"])
    }

    @Test func duplicateSelectionPlacesCopiesAfterLast() async throws {
        let (model, _, ids) = try await open("а\nб\nв")
        model.indent(ids[1])
        model.selectBlocks([ids[0], ids[2]])
        model.duplicateSelection()
        #expect(texts(model) == ["а", "в", "а", "в"])
        let copyOfA = model.children(of: nil)[2]
        #expect(texts(model, in: copyOfA.id) == ["б"], "Копия берёт вложенные блоки")
        #expect(model.selectionRoots.count == 2)
        #expect(!model.isSelected(ids[0]), "Выделены копии")
        model.clearSelection()
    }

    @Test func moveSelectionKeepsGroupTogether() async throws {
        let (model, _, ids) = try await open("а\nб\nв\nг\nд")
        model.selectBlocks([ids[1], ids[3]])
        model.moveBlocks(model.selectionRoots, nextTo: ids[4], after: true)
        #expect(texts(model) == ["а", "в", "д", "б", "г"])

        model.moveSelection(by: -1)
        #expect(texts(model) == ["а", "в", "б", "г", "д"])
        model.moveSelection(by: -1)
        model.moveSelection(by: -1)
        #expect(texts(model) == ["б", "г", "а", "в", "д"])
        model.moveSelection(by: -1)
        #expect(texts(model) == ["б", "г", "а", "в", "д"], "Выше двигать некуда")
        model.clearSelection()
    }

    @Test func indentAndOutdentSelection() async throws {
        let (model, _, ids) = try await open("а\nб\nв")
        model.selectBlocks([ids[1], ids[2]])
        model.indentSelection()
        #expect(texts(model) == ["а"])
        #expect(texts(model, in: ids[0]) == ["б", "в"])
        model.outdentSelection()
        #expect(texts(model) == ["а", "б", "в"])
        model.clearSelection()
    }

    @Test func turnIntoAndColorForSelection() async throws {
        let (model, _, ids) = try await open("а\nб")
        model.selectAllBlocks()
        model.setTypeForSelection(.todo)
        #expect(model.blocks.map(\.type) == [.todo, .todo])
        model.setSelectionBackgroundColor(.yellow)
        #expect(model.blocks.allSatisfy { $0.content.backgroundColor == .yellow })
        model.undo()
        #expect(model.findBlock(ids[0])?.content.backgroundColor == nil)
        model.clearSelection()
    }

    @Test func arrowsMoveAndExtendSelection() async throws {
        let (model, _, ids) = try await open("а\nб\nв")
        model.clickHandle(ids[0], extend: false, toggle: false)
        model.moveSelectionCursor(by: 1, extend: false)
        #expect(model.selectedBlockIds == [ids[1]])
        model.moveSelectionCursor(by: 1, extend: true)
        #expect(model.selectedBlockIds == [ids[1], ids[2]])
        model.moveSelectionCursor(by: -1, extend: true)
        model.moveSelectionCursor(by: -1, extend: true)
        #expect(model.selectedBlockIds == [ids[0], ids[1]])
        model.clearSelection()
    }

    @Test func imageSizeIsUndoable() async throws {
        let (model, _, ids) = try await open("а")
        model.update(ids[0]) {
            $0.type = .image
            $0.content.attachment = "photo.png"
        }
        model.setImageSize(ids[0], widthShare: 0.5, aspect: 1)
        #expect(model.findBlock(ids[0])?.content.imageWidth == 0.5)
        #expect(model.findBlock(ids[0])?.content.imageAspect == 1)
        model.undo()
        #expect(model.findBlock(ids[0])?.content.imageWidth == nil)
    }
}
