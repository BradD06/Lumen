import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct SyncedBlockModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func open(_ text: String) async throws -> PageEditorModel {
        let page = try await db.createQuickNote(text)
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        return model
    }

    @Test func emptyBlockBecomesEmptySynced() async throws {
        let model = try await open("Страница")
        let id = try #require(model.blocks.first?.id)
        model.setType(id, .synced)
        let synced = try #require(model.findBlock(id))
        #expect(synced.isSyncedOriginal)
        #expect(model.children(of: id).map(\.type) == [.paragraph], "Внутри сразу абзац для текста")
        #expect(model.focusRequest == model.children(of: id).first?.id)
    }

    @Test func textBlockIsWrappedNotErased() async throws {
        let model = try await open("Страница\nОбщий абзац\nДругой")
        let first = model.children(of: nil)[0]
        model.setType(first.id, .synced)
        let top = model.children(of: nil)
        #expect(top.count == 2)
        #expect(top[0].isSyncedOriginal)
        #expect(model.children(of: top[0].id).map(\.text) == ["Общий абзац"])
        #expect(top[1].text == "Другой")
        model.undo()
        #expect(model.children(of: nil).map(\.text) == ["Общий абзац", "Другой"])
    }

    @Test func selectionWrapsAndDissolves() async throws {
        let model = try await open("Страница\nа\nб\nв")
        let top = model.children(of: nil)
        let container = try #require(model.wrapInSynced([top[1].id, top[0].id]))
        #expect(model.children(of: nil).map(\.id) == [container, top[2].id])
        #expect(model.children(of: container).map(\.text) == ["а", "б"])

        model.dissolveSynced(container)
        #expect(model.findBlock(container) == nil)
        #expect(model.children(of: nil).map(\.text) == ["а", "б", "в"])
        await model.flush()
        let saved = try await db.blocks(of: model.pageId)
        #expect(saved.contains { $0.type == .synced } == false)
    }

    @Test func copyShowsOriginalAndUnsyncsIntoPlainBlocks() async throws {
        let source = try await open("Источник\nобщий текст")
        let container = try #require(source.wrapInSynced([source.children(of: nil)[0].id]))
        await source.flush()

        let target = try await open("Цель\nабзац")
        let clipboard = BlockClipboard.make(roots: [container], from: source.blocks).referencingSynced()
        let pasted = target.insertClipboard(clipboard, after: target.children(of: nil)[0].id)
        let copyId = try #require(pasted.first)
        let copy = try #require(target.findBlock(copyId))
        let reference = try #require(copy.content.syncedFrom)
        #expect(reference == SyncedReference(pageId: source.pageId, blockId: container))
        #expect(target.children(of: copyId).isEmpty)
        let sourcePage = await target.syncedSourcePage(reference)
        #expect(sourcePage == source.pageId)

        // Правка в оригинале: отвязанная копия берёт текст, какой он сейчас.
        let inside = try #require(source.children(of: container).first)
        source.updateText(inside.id, to: "исправленный текст")
        await source.flush()
        await target.unsyncCopy(copyId)
        #expect(target.findBlock(copyId) == nil)
        #expect(target.children(of: nil).map(\.text) == ["абзац", "исправленный текст"])
        #expect(target.blocks.contains { $0.type == .synced } == false)
    }

    @Test func cutOriginalMovesWithItsIds() async throws {
        let source = try await open("Источник\nобщий")
        let container = try #require(source.wrapInSynced([source.children(of: nil)[0].id]))
        let insideId = try #require(source.children(of: container).first?.id)
        let clipboard = BlockClipboard.make(roots: [container], from: source.blocks)
        source.removeBlocks(Set([container, insideId]))
        await source.flush()

        let target = try await open("Цель\nабзац")
        BlockPasteboard.cutSyncedIds = [container]
        let moving = target.movingSyncedIds(in: clipboard)
        #expect(moving == [container, insideId])
        #expect(BlockPasteboard.cutSyncedIds.isEmpty, "Переезжает только первая вставка")
        target.insertClipboard(clipboard.referencingSynced(except: moving), after: target.children(of: nil)[0].id, keepingIds: moving)
        #expect(target.findBlock(container)?.isSyncedOriginal == true)
        await target.flush()
        let moved = try await db.block(container)
        #expect(moved?.pageId == target.pageId)

        // Старая копия находит оригинал на новой странице.
        let reader = try await open("Читатель\nx")
        let found = await reader.syncedSourcePage(SyncedReference(pageId: source.pageId, blockId: container))
        #expect(found == target.pageId)
    }
}
