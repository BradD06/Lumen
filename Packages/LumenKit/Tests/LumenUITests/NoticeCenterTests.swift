import Foundation
import LumenCore
import LumenStorage
import Testing
@testable import LumenUI

@MainActor
struct NoticeCenterTests {
    /// Ждёт, пока условие станет верным: действия плашек идут в отдельных задачах.
    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<200 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Не дождались")
    }

    @Test func trashShowsUndoThatRestores() async throws {
        let database = try AppDatabase.inMemory()
        let page = try await database.createPage(title: "Черновик")
        let center = NoticeCenter()

        center.moveToTrash(.page(page.id), in: database)
        try await waitUntil { center.current != nil }
        #expect(center.current?.text == "Страница в корзине")
        #expect(center.current?.undo != nil)
        #expect(try await database.page(page.id)?.isTrashed == true)

        center.performUndo()
        #expect(center.current == nil)
        try await waitUntil { try await database.page(page.id)?.isTrashed == false }
    }

    @Test func failedActionShowsAnError() async throws {
        let center = NoticeCenter()
        let database = try AppDatabase.inMemory()
        let done = await center.attempt("Не удалось переименовать") {
            try await database.renamePage(UUID(), title: "Нет такой")
        }
        #expect(!done)
        #expect(center.current?.isError == true)
        #expect(center.current?.text == "Не удалось переименовать")
        #expect(await center.perform("Не вышло", { 42 }) == 42)
    }

    @Test(arguments: [(1, "день"), (2, "дня"), (5, "дней"), (11, "дней"), (14, "дней"), (21, "день"), (23, "дня"), (112, "дней")])
    func dayWordAgreesWithTheNumber(_ count: Int, _ word: String) {
        #expect(HomeView.days(count) == word)
    }
}
