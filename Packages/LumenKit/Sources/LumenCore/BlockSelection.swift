import Foundation

/// Выделение нескольких блоков, как в Notion: что на самом деле двигать и копировать,
/// и какие блоки попадают в диапазон по Shift.
public enum BlockSelection {
    /// Выделенные блоки, у которых не выделен ни один предок, в порядке `blocks`.
    /// Потомки выделенного блока идут вместе с ним, отдельно их трогать не нужно.
    public static func roots(_ selected: Set<UUID>, in blocks: [Block]) -> [UUID] {
        guard !selected.isEmpty else { return [] }
        var parents: [UUID: UUID] = [:]
        for block in blocks {
            if let parent = block.parentBlockId { parents[block.id] = parent }
        }
        return blocks.compactMap { block in
            guard selected.contains(block.id) else { return nil }
            var parent = block.parentBlockId
            var steps = 0
            // Шаги ограничены: повреждённые данные с циклом в родителях не вешают выделение.
            while let current = parent, steps < blocks.count {
                if selected.contains(current) { return nil }
                parent = parents[current]
                steps += 1
            }
            return block.id
        }
    }

    /// Блоки от `anchor` до `target` включительно в порядке на экране.
    public static func range(from anchor: UUID, to target: UUID, in order: [UUID]) -> [UUID] {
        guard let start = order.firstIndex(of: anchor), let end = order.firstIndex(of: target) else { return [target] }
        return Array(order[min(start, end)...max(start, end)])
    }

    /// «1 блок», «3 блока», «12 блоков».
    public static func blocksCaption(_ count: Int) -> String {
        let tens = count % 100
        let ones = count % 10
        let word: String
        if ones == 1, tens != 11 {
            word = "блок"
        } else if (2...4).contains(ones), !(12...14).contains(tens) {
            word = "блока"
        } else {
            word = "блоков"
        }
        return "\(count) \(word)"
    }
}

/// Скопированные блоки: корни и все их потомки в порядке документа.
/// Лежат в буфере обмена, при вставке получают новые id.
public struct BlockClipboard: Codable, Sendable, Equatable {
    public var blocks: [Block]

    public init(blocks: [Block]) {
        self.blocks = blocks
    }

    /// Корни с потомками из `blocks`, который уже в порядке документа. Границы листов не копируются.
    public static func make(roots: [UUID], from blocks: [Block]) -> BlockClipboard {
        var byId: [UUID: Block] = [:]
        var children: [UUID: [Block]] = [:]
        for block in blocks {
            byId[block.id] = block
            if let parent = block.parentBlockId { children[parent, default: []].append(block) }
        }
        var result: [Block] = []
        var visited: Set<UUID> = []
        func add(_ id: UUID) {
            guard let block = byId[id], visited.insert(id).inserted else { return }
            result.append(block)
            for child in children[id] ?? [] {
                add(child.id)
            }
        }
        for root in roots where byId[root]?.type != .sheetBreak {
            add(root)
        }
        return BlockClipboard(blocks: result)
    }

    /// Блоки, чей родитель не скопирован, по порядку.
    public var rootIds: [UUID] {
        let ids = Set(blocks.map(\.id))
        return blocks.filter { block in block.parentBlockId.map { !ids.contains($0) } ?? true }.map(\.id)
    }

    /// Копии для вставки на страницу `pageId` в родителя `parentId`. Корни получают ключи
    /// `rootKeys` по порядку, потомки остаются у своих (новых) родителей.
    /// `keepingIds`: блоки, которые переезжают и сохраняют свой id (вырезанный синхронный блок).
    public func copies(pageId: UUID, parentId: UUID?, rootKeys: [String], keepingIds: Set<UUID> = [], now: Date = Date()) -> (blocks: [Block], roots: [UUID]) {
        var newIds: [UUID: UUID] = [:]
        for block in blocks {
            newIds[block.id] = keepingIds.contains(block.id) ? block.id : UUID()
        }
        let roots = rootIds
        var keys: [UUID: String] = [:]
        for (id, key) in zip(roots, rootKeys) {
            keys[id] = key
        }
        let copied = blocks.compactMap { block -> Block? in
            guard let newId = newIds[block.id] else { return nil }
            var copy = block
            copy.id = newId
            copy.pageId = pageId
            copy.createdAt = now
            copy.updatedAt = now
            if let key = keys[block.id] {
                copy.parentBlockId = parentId
                copy.sortKey = key
            } else {
                copy.parentBlockId = block.parentBlockId.flatMap { newIds[$0] }
            }
            return copy
        }
        return (copied, roots.compactMap { newIds[$0] })
    }
}

/// Размер картинки на странице. Ширина хранится долей ширины страницы, форма отношением
/// высоты к ширине: на iPhone и на Mac картинка выглядит одинаково, только масштаб разный.
public enum ImageSizing {
    /// Картинка по умолчанию не выше этого, как было до ручек.
    public static let defaultMaxHeight = 460.0
    public static let minWidth = 48.0
    public static let minHeight = 32.0
    public static let maxHeight = 2400.0
    /// Самая плоская и самая вытянутая форма.
    public static let minAspect = 0.05
    public static let maxAspect = 6.0
    /// Пока пропорции снимка не прочитаны.
    public static let fallbackAspect = 0.66

    /// Ширина и высота картинки в строке шириной `available`.
    /// `natural` это высота на ширину самого снимка, если она известна.
    public static func size(widthShare: Double?, aspect: Double?, natural: Double?, available: Double) -> (width: Double, height: Double) {
        guard available > 0 else { return (0, 0) }
        let shape = clampAspect(aspect ?? natural ?? fallbackAspect)
        var width: Double
        if let widthShare {
            width = available * min(max(widthShare, 0), 1)
        } else {
            // По умолчанию на всю ширину, но не выше 460 точек.
            width = min(available, defaultMaxHeight / shape)
        }
        width = min(max(width, min(minWidth, available)), available)
        return (width, width * shape)
    }

    /// Что сохранить после перетаскивания ручки. Почти вся ширина считается всей,
    /// форма почти как у снимка считается исходной: так картинку легко вернуть к своему виду.
    /// `keepsShape`: тянули только ширину, форма остаётся прежней (`currentAspect`).
    public static func stored(
        width: Double,
        height: Double,
        available: Double,
        natural: Double?,
        keepsShape: Bool,
        currentAspect: Double?
    ) -> (widthShare: Double?, aspect: Double?) {
        let share = available > 0 ? min(max(width / available, 0.05), 1) : 1
        let widthShare = share > 0.98 ? 1 : share
        if keepsShape { return (widthShare, currentAspect) }
        let aspect = clampAspect(height / max(width, 1))
        if let natural, natural > 0, abs(aspect - natural) / natural < 0.02 {
            return (widthShare, nil)
        }
        return (widthShare, aspect)
    }

    public static func clampAspect(_ aspect: Double) -> Double {
        guard aspect.isFinite, aspect > 0 else { return fallbackAspect }
        return min(max(aspect, minAspect), maxAspect)
    }
}
