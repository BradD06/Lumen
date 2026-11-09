import Foundation

/// Одна и та же книга, добавленная на двух устройствах до синхронизации: после неё в библиотеке
/// две записи с разными id. Здесь решается, какие записи это одна книга и какая из них остаётся.
public enum BookDuplicates {
    public struct Pair: Equatable, Sendable {
        public var duplicate: UUID
        public var keeper: UUID
    }

    /// Пары «повтор → оригинал». Одна книга: тот же формат, то же имя файла и то же название.
    /// Если размеры обоих файлов известны и разные, это разные книги (например, другое издание).
    /// Оригинал добавлен раньше (при равенстве меньший id), поэтому все устройства выбирают одно и то же.
    public static func pairs(_ books: [Source], size: (Source) -> Int64?) -> [Pair] {
        let alive = books.filter { $0.deletedAt == nil }
        let groups = Dictionary(grouping: alive, by: key)
        var result: [Pair] = []
        for group in groups.values where group.count > 1 {
            var keepers: [(book: Source, size: Int64?)] = []
            for book in group.sorted(by: isEarlier) {
                let bookSize = size(book)
                if let keeper = keepers.first(where: { sameFile($0.size, bookSize) }) {
                    result.append(Pair(duplicate: book.id, keeper: keeper.book.id))
                } else {
                    keepers.append((book, bookSize))
                }
            }
        }
        return result.sorted { $0.duplicate.uuidString < $1.duplicate.uuidString }
    }

    static func key(_ book: Source) -> String {
        [book.format.rawValue, normalized(book.originalName), normalized(book.title)].joined(separator: "|")
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sameFile(_ a: Int64?, _ b: Int64?) -> Bool {
        guard let a, let b else { return true }
        return a == b
    }

    private static func isEarlier(_ a: Source, _ b: Source) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}
