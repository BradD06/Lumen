import Foundation
import Testing
@testable import LumenCore

struct SyncedBlockTests {
    private let pageId = UUID()

    private func block(_ text: String, parent: UUID? = nil, key: String, type: BlockType = .paragraph) -> Block {
        Block(pageId: pageId, parentBlockId: parent, type: type, content: BlockContent(text: text), sortKey: key)
    }

    @Test func copiedOriginalBecomesReferenceWithoutChildren() throws {
        let synced = block("", key: "a", type: .synced)
        let inside = block("общий текст", parent: synced.id, key: "a")
        let deeper = block("ещё глубже", parent: inside.id, key: "a")
        let other = block("рядом", key: "b")
        let clipboard = BlockClipboard.make(roots: [synced.id, other.id], from: [synced, inside, deeper, other])

        let pasted = clipboard.referencingSynced()
        #expect(pasted.blocks.map(\.id) == [synced.id, other.id], "Содержимое остаётся только в оригинале")
        let reference = try #require(pasted.blocks.first?.content.syncedFrom)
        #expect(reference == SyncedReference(pageId: pageId, blockId: synced.id))
        #expect(pasted.blocks.first?.isSyncedCopy == true)
        #expect(synced.isSyncedOriginal)
    }

    @Test func cutOriginalStaysOriginal() {
        let synced = block("", key: "a", type: .synced)
        let inside = block("текст", parent: synced.id, key: "a")
        let clipboard = BlockClipboard.make(roots: [synced.id], from: [synced, inside])
        #expect(clipboard.referencingSynced(except: [synced.id]) == clipboard)
    }

    @Test func copyOfCopyKeepsSameOriginal() {
        var copy = block("", key: "a", type: .synced)
        let reference = SyncedReference(pageId: UUID(), blockId: UUID())
        copy.content.syncedFrom = reference
        let pasted = BlockClipboard.make(roots: [copy.id], from: [copy]).referencingSynced()
        #expect(pasted.blocks.first?.content.syncedFrom == reference)
    }

    @Test func movedBlocksKeepTheirIds() {
        let synced = block("", key: "a", type: .synced)
        let inside = block("текст", parent: synced.id, key: "a")
        let clipboard = BlockClipboard.make(roots: [synced.id], from: [synced, inside])
        let target = UUID()
        let moved = clipboard.copies(pageId: target, parentId: nil, rootKeys: ["m"], keepingIds: [synced.id, inside.id])
        #expect(moved.blocks.map(\.id) == [synced.id, inside.id])
        #expect(moved.blocks.allSatisfy { $0.pageId == target })
        #expect(moved.blocks[1].parentBlockId == synced.id)

        let copied = clipboard.copies(pageId: target, parentId: nil, rootKeys: ["m"])
        #expect(Set(copied.blocks.map(\.id)).isDisjoint(with: [synced.id, inside.id]))
    }

    @Test func referenceSurvivesEncoding() throws {
        var content = BlockContent()
        content.syncedFrom = SyncedReference(pageId: UUID(), blockId: UUID())
        let decoded = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.syncedFrom == content.syncedFrom)
        let plain = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(BlockContent()))
        #expect(plain.syncedFrom == nil)
    }
}
