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

/// Одна полка «Кабинета» и книги на ней. `shelf == nil`: общая полка, на ней всё,
/// что не стоит на своих полках. Заметки стоят рядом с книгами: из нескольких листов
/// папкой, одиночные листы лежат в лотке, приколотые висят под доской.
public struct ShelfGroup: Identifiable, Equatable, Sendable {
    public var shelf: Folder?
    public var books: [Source]
    public var notes: [ShelfNote]

    public var id: UUID? { shelf?.id }

    public init(shelf: Folder?, books: [Source], notes: [ShelfNote] = []) {
        self.shelf = shelf
        self.books = books
        self.notes = notes
    }

    /// Заметки из нескольких листов: на полке они стоят папками.
    public var folders: [ShelfNote] { notes.filter(\.isFolder) }
    /// Заметки из одного листа: лежат стопкой в лотке в конце полки.
    public var singleSheets: [ShelfNote] { notes.filter { !$0.isFolder } }
    /// Приколотые к полке листы.
    public var pinned: [ShelfNote] { notes.filter { $0.shelfPin != nil } }

    /// Общая полка первой, дальше свои полки по порядку. Книга стоит на полке своей папки;
    /// книги из обычных папок и из корня библиотеки на общей. Порядок книг сохраняется.
    /// Заметки расходятся по полкам так же, по своей папке.
    public static func make(books: [Source], shelves: [Folder], notes: [ShelfNote] = []) -> [ShelfGroup] {
        let shelfIds = Set(shelves.map(\.id))
        var byShelf: [UUID: [Source]] = [:]
        var loose: [Source] = []
        for book in books {
            if let folderId = book.folderId, shelfIds.contains(folderId) {
                byShelf[folderId, default: []].append(book)
            } else {
                loose.append(book)
            }
        }
        var notesByShelf: [UUID: [ShelfNote]] = [:]
        var looseNotes: [ShelfNote] = []
        for note in notes {
            if let folderId = note.folderId, shelfIds.contains(folderId) {
                notesByShelf[folderId, default: []].append(note)
            } else {
                looseNotes.append(note)
            }
        }
        return [ShelfGroup(shelf: nil, books: loose, notes: looseNotes)]
            + shelves.map { ShelfGroup(shelf: $0, books: byShelf[$0.id] ?? [], notes: notesByShelf[$0.id] ?? []) }
    }
}

/// Заметка на полке: сколько в ней листов и приколот ли какой-то лист к полке.
public struct ShelfNote: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var icon: String?
    public var folderId: UUID?
    /// Сколько листов: у обычной заметки по границам листов, у рукописной по листам тетради.
    public var sheetCount: Int
    /// Номер приколотого листа с нуля, см. `Page.shelfPin`.
    public var shelfPin: Int?
    public var isNotebook: Bool
    public var updatedAt: Date

    public init(
        id: UUID,
        title: String,
        icon: String? = nil,
        folderId: UUID? = nil,
        sheetCount: Int = 1,
        shelfPin: Int? = nil,
        isNotebook: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.folderId = folderId
        self.sheetCount = max(sheetCount, 1)
        self.shelfPin = shelfPin
        self.isNotebook = isNotebook
        self.updatedAt = updatedAt
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    /// Два листа и больше: заметка стоит на полке папкой.
    public var isFolder: Bool { sheetCount > 1 }

    /// Приколотый лист, не дальше последнего (листы могли удалить).
    public var pinnedSheet: Int? { shelfPin.map { min(max($0, 0), sheetCount - 1) } }

    /// «1 лист», «3 листа», «12 листов».
    public static func sheetsLabel(_ count: Int) -> String {
        let tens = count % 100
        let ones = count % 10
        let word: String
        if (11...14).contains(tens) {
            word = "листов"
        } else if ones == 1 {
            word = "лист"
        } else if (2...4).contains(ones) {
            word = "листа"
        } else {
            word = "листов"
        }
        return "\(count) \(word)"
    }
}
