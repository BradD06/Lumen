import Foundation
import Testing
@testable import LumenCore

struct ShelfSortTests {
    private func book(_ title: String, author: String? = nil, progress: Double = 0, added: TimeInterval = 0, key: String? = nil) -> Source {
        Source(
            title: title, author: author, format: .epub, file: "\(title).epub", originalName: "\(title).epub",
            progress: progress, shelfOrder: key, createdAt: Date(timeIntervalSince1970: added)
        )
    }

    @Test func sortsByTitleAuthorProgressAndDate() {
        let anna = book("Анна Каренина", author: "Толстой", progress: 0.2, added: 3)
        let idiot = book("Идиот", author: "Достоевский", progress: 0.9, added: 1)
        let notes = book("Записки", progress: 0.5, added: 2)
        let books = [notes, idiot, anna]
        #expect(ShelfSort.recent.sorted(books).map(\.title) == ["Записки", "Идиот", "Анна Каренина"])
        #expect(ShelfSort.title.sorted(books).map(\.title) == ["Анна Каренина", "Записки", "Идиот"])
        // Без автора в конце.
        #expect(ShelfSort.author.sorted(books).map(\.title) == ["Идиот", "Анна Каренина", "Записки"])
        #expect(ShelfSort.progress.sorted(books).map(\.title) == ["Идиот", "Записки", "Анна Каренина"])
        #expect(ShelfSort.added.sorted(books).map(\.title) == ["Анна Каренина", "Записки", "Идиот"])
    }

    @Test func customOrderPutsNewBooksFirst() {
        let a = book("A", key: "V")
        let b = book("B", key: "F")
        let fresh = book("Новая")
        #expect(ShelfSort.custom.sorted([a, fresh, b]).map(\.title) == ["Новая", "B", "A"])
    }

    @Test func rearrangingKeepsKeysThatAreStillInOrder() {
        // Книгу «X» перенесли из конца в начало: новый ключ только у неё.
        let keys = SortKey.rearranged(["d", "a", "b", "c"])
        #expect(Array(keys.dropFirst()) == ["a", "b", "c"])
        #expect(keys[0] < "a")
        #expect(keys == keys.sorted())
    }

    @Test func rearrangingFillsBooksWithoutKeys() {
        let keys = SortKey.rearranged([nil, "M", nil, nil, "T", nil])
        #expect(keys[1] == "M" && keys[4] == "T")
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
        let fresh = SortKey.rearranged([nil, nil, nil])
        #expect(fresh == fresh.sorted() && Set(fresh).count == 3)
    }
}
