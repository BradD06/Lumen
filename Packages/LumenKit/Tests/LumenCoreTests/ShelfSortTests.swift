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

struct ShelfGroupTests {
    @Test func commonShelfComesFirstEvenWhenEmpty() {
        let shelf = Folder(name: "Полка", isShelf: true)
        let book = Source(title: "Книга", format: .epub, file: "a.epub", originalName: "a.epub", folderId: shelf.id)
        let groups = ShelfGroup.make(books: [book], shelves: [shelf])
        #expect(groups.map(\.id) == [nil, shelf.id])
        #expect(groups[0].books.isEmpty)
        #expect(groups[1].books.map(\.id) == [book.id])
    }
}

struct BookDuplicatesTests {
    private func book(_ title: String, file: String = "war.epub", added: TimeInterval) -> Source {
        Source(title: title, format: .epub, file: UUID().uuidString, originalName: file, createdAt: Date(timeIntervalSince1970: added))
    }

    @Test func sameBookFromTwoDevicesKeepsTheEarlierOne() {
        let first = book("Война и мир", added: 10)
        let second = book("Война и мир ", added: 20)
        let other = book("Анна Каренина", file: "anna.epub", added: 5)
        let pairs = BookDuplicates.pairs([second, other, first]) { _ in nil }
        #expect(pairs == [BookDuplicates.Pair(duplicate: second.id, keeper: first.id)])
    }

    @Test func differentFileSizesAreDifferentBooks() {
        let first = book("Война и мир", added: 10)
        let second = book("Война и мир", added: 20)
        let sizes = [first.id: Int64(100), second.id: Int64(200)]
        #expect(BookDuplicates.pairs([first, second]) { sizes[$0.id] }.isEmpty)
    }

    @Test func trashedBooksAreNotDuplicates() {
        let first = book("Война и мир", added: 10)
        var second = book("Война и мир", added: 20)
        second.deletedAt = Date()
        #expect(BookDuplicates.pairs([first, second]) { _ in nil }.isEmpty)
    }
}
