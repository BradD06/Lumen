import Foundation
import Testing
@testable import LumenCore

struct ShelfSearchTests {
    private func book(_ title: String, author: String? = nil) -> Source {
        Source(title: title, author: author, format: .epub, file: "\(title).epub", originalName: "\(title).epub")
    }

    @Test func findsByTitleOrAuthorIgnoringCaseAndYo() {
        let anna = book("Анна Каренина", author: "Лев Толстой")
        let idiot = book("Идиот", author: "Фёдор Достоевский")
        let stats = book("Лекции по статистике")
        let books = [anna, idiot, stats]
        #expect(ShelfSearch.filter(books, query: "каренина").map(\.title) == ["Анна Каренина"])
        #expect(ShelfSearch.filter(books, query: "ТОЛСТОЙ").map(\.title) == ["Анна Каренина"])
        // «ё» и «е» не различаются.
        #expect(ShelfSearch.filter(books, query: "федор").map(\.title) == ["Идиот"])
        #expect(ShelfSearch.filter(books, query: "лек").map(\.title) == ["Лекции по статистике"])
    }

    @Test func everyWordMustMatchInAnyField() {
        let anna = book("Анна Каренина", author: "Лев Толстой")
        let war = book("Война и мир", author: "Лев Толстой")
        let books = [anna, war]
        #expect(ShelfSearch.filter(books, query: "толстой мир").map(\.title) == ["Война и мир"])
        #expect(ShelfSearch.filter(books, query: "лев, анна").map(\.title) == ["Анна Каренина"])
        #expect(ShelfSearch.filter(books, query: "пушкин").isEmpty)
    }

    @Test func emptyQueryKeepsEverythingInOrder() {
        let books = [book("Б"), book("А")]
        #expect(ShelfSearch.filter(books, query: "   ").map(\.title) == ["Б", "А"])
        #expect(ShelfSearch.terms("").isEmpty)
    }

    @Test func fileNameIsTheTitleWhenTitleIsEmpty() {
        let file = Source(title: " ", format: .pdf, file: "x.pdf", originalName: "Матанализ.pdf")
        #expect(ShelfSearch.filter([file], query: "матан").count == 1)
    }
}
