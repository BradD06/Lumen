import Foundation

/// Одна и та же книга, добавленная на двух устройствах до синхронизации: после неё в библиотеке
/// две записи с разными id. Здесь решается, какие записи это одна книга и какая из них остаётся.
public enum BookDuplicates {
    public struct Pair: Equatable, Sendable {
        public var duplicate: UUID
        public var keeper: UUID
    }

    /// Пары «повтор → оригинал». Одна книга, если:
    /// - тот же формат, то же имя файла и то же название (если размеры обоих файлов известны
    ///   и разные, это разные книги, например другое издание);
    /// - или тот же формат и файлы одинаковы байт в байт (`sameContent`), даже под другим именем:
    ///   «Книга (1).pdf» из Telegram или «Книга 2.pdf» от iCloud.
    /// Оригинал добавлен раньше (при равенстве меньший id), поэтому все устройства выбирают одно и то же.
    public static func pairs(
        _ books: [Source],
        size: (Source) -> Int64?,
        sameContent: (Source, Source) -> Bool = { _, _ in false }
    ) -> [Pair] {
        let alive = books.filter { $0.deletedAt == nil }.sorted(by: isEarlier)
        var keepers: [(book: Source, key: String, size: Int64?)] = []
        var result: [Pair] = []
        for book in alive {
            let bookKey = key(book)
            let bookSize = size(book)
            let keeper = keepers.first { keeper in
                if keeper.key == bookKey, sameFile(keeper.size, bookSize) { return true }
                guard keeper.book.format == book.format, let known = keeper.size, known == bookSize else { return false }
                return sameContent(keeper.book, book)
            }
            if let keeper {
                result.append(Pair(duplicate: book.id, keeper: keeper.book.id))
            } else {
                keepers.append((book, bookKey, bookSize))
            }
        }
        return result
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
