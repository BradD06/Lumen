import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct SidePageTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func anyPageOpensBesideTheBookAndTakesExcerpts() async throws {
        let folder = try await db.createFolder(name: "Курс")
        let source = try await db.addSource(
            title: "Книга", format: .epub, file: "missing.epub", originalName: "Книга.epub", folderId: folder.id
        )
        let other = try await db.createPage(title: "Конспект", folderId: folder.id)
        let model = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await model.load()
        #expect(model.showsBookNotes)

        await model.openSidePage(other.id)
        #expect(model.notes?.pageId == other.id)
        #expect(!model.showsBookNotes)

        let highlight = Highlight(
            sourceId: source.id, locator: SourceLocator(section: 0, progression: 0), text: "Цитата", label: "гл. 1"
        )
        model.addExcerpt(highlight)
        await model.flush()
        let excerpts = try await db.blocks(of: other.id).filter { $0.type == .excerpt }
        #expect(excerpts.map(\.text) == ["Цитата"])

        // Книга запоминает, какая заметка была открыта рядом.
        let reopened = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await reopened.load()
        #expect(reopened.notes?.pageId == other.id)

        await reopened.openBookNotes()
        #expect(reopened.showsBookNotes)
    }

    @Test func newSidePageGoesIntoTheBooksFolder() async throws {
        let folder = try await db.createFolder(name: "Курс")
        let source = try await db.addSource(
            title: "Книга", format: .epub, file: "missing.epub", originalName: "Книга.epub", folderId: folder.id
        )
        let model = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await model.load()

        await model.createSidePage()

        let pageId = try #require(model.notes?.pageId)
        let page = try #require(try await db.page(pageId))
        #expect(page.folderId == folder.id)
        #expect(page.sourceId == nil)
    }
}
