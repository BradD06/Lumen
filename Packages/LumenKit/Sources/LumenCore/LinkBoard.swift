import Foundation

/// Доска связей «Кабинета»: книги, папки и листы приколоты кнопками к пробковой доске,
/// а ссылки между ними натянуты красной ниткой. Здесь чистая логика: какие нитки видны
/// и куда приколоть новое. Сами ссылки собирает `BoardSnapshot` (LumenStorage).

/// Что приколото к доске и где. `id` совпадает с id книги, папки или страницы:
/// одна вещь приколота не больше одного раза. `x`, `y` это центр карточки.
public struct BoardPin: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: Kind
    public var x: Double
    public var y: Double
    public var createdAt: Date
    public var updatedAt: Date

    public enum Kind: String, Codable, Sendable {
        case page, source, folder
    }

    public init(item: LibraryItemID, at point: LibraryPoint, createdAt: Date = Date()) {
        switch item {
        case .page(let id): self.id = id; kind = .page
        case .source(let id): self.id = id; kind = .source
        case .folder(let id): self.id = id; kind = .folder
        }
        x = point.x
        y = point.y
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    public var item: LibraryItemID {
        switch kind {
        case .page: .page(id)
        case .source: .source(id)
        case .folder: .folder(id)
        }
    }

    public var point: LibraryPoint {
        get { LibraryPoint(x: x, y: y) }
        set {
            x = newValue.x
            y = newValue.y
        }
    }
}

/// Одна связь двух вещей, ещё без доски: ссылка в заметке, выписка из книги, заметки к книге.
public struct BoardRelation: Hashable, Sendable {
    public var from: LibraryItemID
    public var to: LibraryItemID
    public var kind: Kind

    public enum Kind: String, Hashable, Sendable, CaseIterable {
        /// Ссылка на страницу или книгу в тексте заметки.
        case link
        /// Выписка или ссылка на место из книги.
        case excerpt
        /// Заметки к книге.
        case notes
        /// Лежит в папке или это подстраница.
        case contains
    }

    public init(_ from: LibraryItemID, _ to: LibraryItemID, kind: Kind) {
        self.from = from
        self.to = to
        self.kind = kind
    }
}

/// Нитка между двумя приколотыми вещами. Несколько связей одной пары это одна нитка.
public struct BoardThread: Identifiable, Hashable, Sendable {
    public var a: LibraryItemID
    public var b: LibraryItemID
    public var kinds: Set<BoardRelation.Kind>
    /// Сколько связей натянуто этой ниткой.
    public var count: Int

    public var id: String { "\(a.boardKey)|\(b.boardKey)" }

    /// Только «лежит в папке»: такую нитку рисуют тоньше.
    public var isContainmentOnly: Bool { kinds == [.contains] }

    public func touches(_ item: LibraryItemID) -> Bool { a == item || b == item }

    public func other(than item: LibraryItemID) -> LibraryItemID? {
        if a == item { return b }
        if b == item { return a }
        return nil
    }
}

extension LibraryItemID {
    /// Постоянный ключ для сортировки и id ниток.
    public var boardKey: String {
        switch self {
        case .folder(let id): "f.\(id.uuidString)"
        case .page(let id): "p.\(id.uuidString)"
        case .source(let id): "s.\(id.uuidString)"
        }
    }

    public var uuid: UUID {
        switch self {
        case .folder(let id), .page(let id), .source(let id): id
        }
    }
}

public enum LinkBoard {
    /// Нитки между приколотыми вещами.
    ///
    /// Если вещь сама не приколота, за неё отвечает ближайшая приколотая папка (или страница),
    /// в которой она лежит: приколол папку с конспектами, и нитки от всех конспектов идут к ней.
    /// Приколотая вещь внутри приколотой папки привязана к ней ниткой «лежит в папке».
    /// - Parameter container: где лежит вещь: папка или родительская страница.
    public static func threads(
        relations: [BoardRelation],
        pinned: Set<LibraryItemID>,
        container: [LibraryItemID: LibraryItemID]
    ) -> [BoardThread] {
        var byPair: [String: BoardThread] = [:]

        func add(_ x: LibraryItemID, _ y: LibraryItemID, kind: BoardRelation.Kind) {
            guard x != y else { return }
            let (a, b) = x.boardKey < y.boardKey ? (x, y) : (y, x)
            let key = "\(a.boardKey)|\(b.boardKey)"
            if var thread = byPair[key] {
                thread.kinds.insert(kind)
                thread.count += 1
                byPair[key] = thread
            } else {
                byPair[key] = BoardThread(a: a, b: b, kinds: [kind], count: 1)
            }
        }

        for relation in relations {
            guard let a = representative(of: relation.from, pinned: pinned, container: container),
                  let b = representative(of: relation.to, pinned: pinned, container: container)
            else { continue }
            add(a, b, kind: relation.kind)
        }
        for item in pinned {
            if let holder = nearestPinnedContainer(of: item, pinned: pinned, container: container) {
                add(holder, item, kind: .contains)
            }
        }
        return byPair.values.sorted { $0.id < $1.id }
    }

    /// Кто на доске отвечает за вещь: она сама или ближайшая приколотая папка над ней.
    public static func representative(
        of item: LibraryItemID,
        pinned: Set<LibraryItemID>,
        container: [LibraryItemID: LibraryItemID]
    ) -> LibraryItemID? {
        if pinned.contains(item) { return item }
        return nearestPinnedContainer(of: item, pinned: pinned, container: container)
    }

    static func nearestPinnedContainer(
        of item: LibraryItemID,
        pinned: Set<LibraryItemID>,
        container: [LibraryItemID: LibraryItemID]
    ) -> LibraryItemID? {
        var current = item
        var seen: Set<LibraryItemID> = [item]
        while let parent = container[current] {
            // Папка в самой себе (испорченные данные) не зацикливает доску.
            guard seen.insert(parent).inserted else { return nil }
            if pinned.contains(parent) { return parent }
            current = parent
        }
        return nil
    }

    /// Соседи вещи: всё, с чем она связана одной ниткой.
    public static func neighbors(of item: LibraryItemID, threads: [BoardThread]) -> Set<LibraryItemID> {
        Set(threads.compactMap { $0.other(than: item) })
    }

    /// «Тема»: всё, до чего можно дойти по ниткам от вещи, вместе с ней самой.
    public static func cluster(of item: LibraryItemID, threads: [BoardThread]) -> Set<LibraryItemID> {
        var adjacency: [LibraryItemID: [LibraryItemID]] = [:]
        for thread in threads {
            adjacency[thread.a, default: []].append(thread.b)
            adjacency[thread.b, default: []].append(thread.a)
        }
        var found: Set<LibraryItemID> = [item]
        var queue = [item]
        while let next = queue.popLast() {
            for neighbor in adjacency[next] ?? [] where found.insert(neighbor).inserted {
                queue.append(neighbor)
            }
        }
        return found
    }

    /// Всё, у чего есть хоть одна ссылка (без «лежит в папке»): это предлагается приколоть разом.
    public static func linkedItems(_ relations: [BoardRelation]) -> Set<LibraryItemID> {
        var items = Set<LibraryItemID>()
        for relation in relations where relation.kind != .contains && relation.from != relation.to {
            items.insert(relation.from)
            items.insert(relation.to)
        }
        return items
    }

    /// С чем вещь связана напрямую, если смотреть на сами ссылки, а не на доску.
    /// У папки это всё, с чем связано лежащее в ней.
    public static func related(
        to item: LibraryItemID,
        relations: [BoardRelation],
        container: [LibraryItemID: LibraryItemID]
    ) -> Set<LibraryItemID> {
        func isInside(_ candidate: LibraryItemID) -> Bool {
            if candidate == item { return true }
            var current = candidate
            var seen: Set<LibraryItemID> = [candidate]
            while let parent = container[current], seen.insert(parent).inserted {
                if parent == item { return true }
                current = parent
            }
            return false
        }
        var result = Set<LibraryItemID>()
        for relation in relations where relation.kind != .contains {
            let fromInside = isInside(relation.from)
            let toInside = isInside(relation.to)
            if fromInside, !toInside { result.insert(relation.to) }
            if toInside, !fromInside { result.insert(relation.from) }
        }
        return result
    }
}

/// Куда приколоть новые карточки, чтобы они не легли друг на друга.
public enum BoardLayout {
    /// Место под одну карточку с запасом на нитки.
    public static let cellWidth = 230.0
    public static let cellHeight = 230.0
    /// Центр первой карточки на пустой доске.
    public static let origin = LibraryPoint(x: 180, y: 170)

    /// Места для `items` по порядку. Вещь, связанная с уже приколотыми, ложится рядом с ними,
    /// остальные в свободные клетки по строкам. Занятые места (`occupied`) не трогаются.
    public static func place(
        _ items: [LibraryItemID],
        occupied: [LibraryItemID: LibraryPoint],
        threadsAfter threads: [BoardThread],
        columns: Int = 6
    ) -> [LibraryItemID: LibraryPoint] {
        var taken = occupied
        var result: [LibraryItemID: LibraryPoint] = [:]
        // Сначала самые связанные: они становятся центрами, остальные ложатся вокруг.
        let degree = Dictionary(grouping: threads.flatMap { [$0.a, $0.b] }, by: { $0 }).mapValues(\.count)
        let ordered = items.enumerated().sorted { lhs, rhs in
            let l = degree[lhs.element] ?? 0
            let r = degree[rhs.element] ?? 0
            return l == r ? lhs.offset < rhs.offset : l > r
        }.map(\.element)

        for item in ordered where taken[item] == nil {
            let anchors = LinkBoard.neighbors(of: item, threads: threads).compactMap { taken[$0] }
            let spot: LibraryPoint
            if anchors.isEmpty {
                spot = firstFreeCell(taken: Array(taken.values), columns: columns)
            } else {
                let center = LibraryPoint(
                    x: anchors.map(\.x).reduce(0, +) / Double(anchors.count),
                    y: anchors.map(\.y).reduce(0, +) / Double(anchors.count)
                )
                spot = freeSpot(near: center, taken: Array(taken.values))
            }
            taken[item] = spot
            result[item] = spot
        }
        return result
    }

    /// Свободна ли точка: ни одна карточка не ближе, чем на клетку.
    public static func isFree(_ point: LibraryPoint, taken: [LibraryPoint]) -> Bool {
        taken.allSatisfy { abs($0.x - point.x) >= cellWidth * 0.9 || abs($0.y - point.y) >= cellHeight * 0.9 }
    }

    /// Ближайшее свободное место вокруг `center`: по кольцам клеток всё дальше от него.
    static func freeSpot(near center: LibraryPoint, taken: [LibraryPoint]) -> LibraryPoint {
        for ring in 1...40 {
            var candidates: [LibraryPoint] = []
            for dx in -ring...ring {
                for dy in -ring...ring where max(abs(dx), abs(dy)) == ring {
                    let point = LibraryPoint(
                        x: center.x + Double(dx) * cellWidth,
                        y: center.y + Double(dy) * cellHeight
                    )
                    // Не левее и не выше края доски.
                    guard point.x >= origin.x, point.y >= origin.y else { continue }
                    candidates.append(point)
                }
            }
            candidates.sort { lhs, rhs in
                let l = hypot(lhs.x - center.x, lhs.y - center.y)
                let r = hypot(rhs.x - center.x, rhs.y - center.y)
                return l == r ? (lhs.y, lhs.x) < (rhs.y, rhs.x) : l < r
            }
            if let free = candidates.first(where: { isFree($0, taken: taken) }) {
                return free
            }
        }
        return firstFreeCell(taken: taken, columns: 6)
    }

    /// Первая свободная клетка сетки, клетки идут по строкам.
    static func firstFreeCell(taken: [LibraryPoint], columns: Int) -> LibraryPoint {
        let columns = max(columns, 1)
        // Каждая карточка занимает не больше одной клетки, так что свободная найдётся
        // среди первых `taken.count + 1` клеток.
        for index in 0...(taken.count * 4 + 1) {
            let point = LibraryPoint(
                x: origin.x + Double(index % columns) * cellWidth,
                y: origin.y + Double(index / columns) * cellHeight
            )
            if isFree(point, taken: taken) { return point }
        }
        return LibraryPoint(x: origin.x, y: origin.y + Double(taken.count + 1) * cellHeight)
    }
}
