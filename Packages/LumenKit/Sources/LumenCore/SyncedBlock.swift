import Foundation

/// Откуда синхронный блок берёт содержимое: блок-оригинал на странице.
/// Оригинал это блок `.synced` без `syncedFrom`, его дети и есть общее содержимое.
/// Копия (`.synced` с `syncedFrom`) своих детей не имеет и показывает детей оригинала:
/// правка в любой копии сразу правит оригинал, как в Notion.
public struct SyncedReference: Hashable, Codable, Sendable {
    public var pageId: UUID
    public var blockId: UUID

    public init(pageId: UUID, blockId: UUID) {
        self.pageId = pageId
        self.blockId = blockId
    }
}

extension Block {
    /// Оригинал синхронного блока (не копия).
    public var isSyncedOriginal: Bool { type == .synced && content.syncedFrom == nil }
    /// Копия синхронного блока.
    public var isSyncedCopy: Bool { type == .synced && content.syncedFrom != nil }
}

extension BlockClipboard {
    /// Вставка скопированного синхронного блока даёт его копию, а не второй оригинал:
    /// оригинал становится ссылкой на себя, его дети не вставляются.
    /// `except`: вырезанные оригиналы, они переезжают как есть.
    public func referencingSynced(except kept: Set<UUID> = []) -> BlockClipboard {
        let originals = blocks.filter { $0.isSyncedOriginal && !kept.contains($0.id) }
        guard !originals.isEmpty else { return self }
        var dropped = Set<UUID>()
        // Дети оригинала (и их дети) остаются только в оригинале.
        var frontier = Set(originals.map(\.id))
        while !frontier.isEmpty {
            let next = Set(blocks.filter { $0.parentBlockId.map(frontier.contains) ?? false }.map(\.id))
            let fresh = next.subtracting(dropped)
            dropped.formUnion(fresh)
            frontier = fresh
        }
        let result = blocks.compactMap { block -> Block? in
            guard !dropped.contains(block.id) else { return nil }
            guard block.isSyncedOriginal, !kept.contains(block.id) else { return block }
            var copy = block
            copy.content.syncedFrom = SyncedReference(pageId: block.pageId, blockId: block.id)
            return copy
        }
        return BlockClipboard(blocks: result)
    }
}
