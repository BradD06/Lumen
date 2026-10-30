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

    @Test func readingTimeCountsOnlyActiveStretches() async throws {
        let source = try await db.addSource(
            title: "Книга", format: .epub, file: "missing.epub", originalName: "Книга.epub"
        )
        let model = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await model.load()
        let start = Date().addingTimeInterval(60)
        model.noteActivity(at: start)
        model.noteActivity(at: start.addingTimeInterval(120))
        // Долгий перерыв не засчитывается, счёт идёт дальше с нового действия.
        model.noteActivity(at: start.addingTimeInterval(120 + ReaderModel.idleLimit + 60))
        model.noteActivity(at: start.addingTimeInterval(120 + ReaderModel.idleLimit + 90))

        let session = try #require(model.readingSession)
        #expect(session.seconds >= 150 && session.seconds < 220)

        try await db.saveReadingSession(session)
        #expect(try await db.readingStats(of: source.id).totalSeconds == session.seconds)
    }
}
