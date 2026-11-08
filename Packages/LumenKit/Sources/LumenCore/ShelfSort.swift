import Foundation

/// Как расставлены книги на полке «Кабинета».
public enum ShelfSort: String, CaseIterable, Identifiable, Sendable {
    /// Как их расставили руками.
    case custom
    /// Что читали недавно, слева; дальше новые, ещё не открытые.
    case recent
    case title
    case author
    /// Больше всего прочитано, слева.
    case progress
    /// Недавно добавленные, слева.
    case added

    public var id: Self { self }

    /// `books` приходят в порядке «Недавние» (`ShelfQuery`): он же решает при равенстве.
    public func sorted(_ books: [Source]) -> [Source] {
        let ranked = Array(books.enumerated())
        func by(_ before: (Source, Source) -> Bool?) -> [Source] {
            ranked.sorted { a, b in before(a.element, b.element) ?? (a.offset < b.offset) }.map(\.element)
        }
        switch self {
        case .recent:
            return books
        case .custom:
            // Ещё не переставленные (новые) книги стоят слева, остальные по своим ключам.
            return by { a, b in
                switch (a.shelfOrder, b.shelfOrder) {
                case (nil, nil): nil
                case (nil, _): true
                case (_, nil): false
                case let (x?, y?): x == y ? nil : x < y
                }
            }
        case .title:
            return by { a, b in Self.compare(a.displayTitle, b.displayTitle) }
        case .author:
            return by { a, b in
                let x = a.author?.trimmingCharacters(in: .whitespaces) ?? ""
                let y = b.author?.trimmingCharacters(in: .whitespaces) ?? ""
                // Без автора в конце.
                if x.isEmpty != y.isEmpty { return !x.isEmpty }
                return Self.compare(x, y) ?? Self.compare(a.displayTitle, b.displayTitle)
            }
        case .progress:
            return by { a, b in a.progress == b.progress ? nil : a.progress > b.progress }
        case .added:
            return by { a, b in a.createdAt == b.createdAt ? nil : a.createdAt > b.createdAt }
        }
    }

    private static func compare(_ a: String, _ b: String) -> Bool? {
        switch a.localizedStandardCompare(b) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: nil
        }
    }
}

extension SortKey {
    /// Ключи для списка, который расставили заново. Ключи, что уже идут по возрастанию
    /// (самая длинная такая цепочка), остаются; новые получают только остальные.
    /// Передвинули одну книгу: меняется один ключ.
    public static func rearranged(_ keys: [String?]) -> [String] {
        let kept = increasingRun(keys)
        var result: [String] = []
        result.reserveCapacity(keys.count)
        var index = 0
        while index < keys.count {
            if kept.contains(index), let key = keys[index] {
                result.append(key)
                index += 1
                continue
            }
            // Подряд идущие места без ключа: ставим их между соседями.
            var end = index
            while end < keys.count, !kept.contains(end) { end += 1 }
            let upper = end < keys.count ? keys[end] : nil
            result += sequence(count: end - index, after: result.last, before: upper)
            index = end
        }
        return result
    }

    /// Номера мест, чьи ключи образуют самую длинную строго возрастающую цепочку.
    private static func increasingRun(_ keys: [String?]) -> Set<Int> {
        var tails: [Int] = []
        var previous = [Int?](repeating: nil, count: keys.count)
        for (index, key) in keys.enumerated() {
            guard let key else { continue }
            var low = 0
            var high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if keys[tails[mid]]! < key { low = mid + 1 } else { high = mid }
            }
            previous[index] = low > 0 ? tails[low - 1] : nil
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var run = Set<Int>()
        var cursor = tails.last
        while let index = cursor {
            run.insert(index)
            cursor = previous[index]
        }
        return run
    }
}
