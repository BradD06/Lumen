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
        await model.addExcerpt(highlight)
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

    @Test func excerptsGoToTheNoteOpenInTheOtherHalfOfTheScreen() async throws {
        let source = try await db.addSource(
            title: "Книга", format: .epub, file: "missing.epub", originalName: "Книга.epub"
        )
        let beside = try await db.createPage(title: "Рядом")
        let editor = PageEditorModel(database: db, pageId: beside.id)
        await editor.load()
        OpenPageEditors.shared.register(editor)
        defer { OpenPageEditors.shared.unregister(editor) }

        let model = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await model.load()
        model.besidePageId = beside.id
        let highlight = Highlight(
            sourceId: source.id, locator: SourceLocator(section: 0, progression: 0), text: "Цитата", label: "гл. 1"
        )
        await model.addExcerpt(highlight)
        await editor.flush()

        // Выписка сразу в открытом редакторе и в базе, а заметки к книге не заводятся.
        #expect(editor.blocks.filter { $0.type == .excerpt }.map(\.text) == ["Цитата"])
        let saved = try await db.blocks(of: beside.id).filter { $0.type == .excerpt }
        #expect(saved.map(\.text) == ["Цитата"])
        #expect(model.notes == nil)
        #expect(try await db.bookNotesPage(for: source.id) == nil)

        // Рядом закрыли заметку: выписки снова идут в заметки к книге.
        model.besidePageId = nil
        await model.addExcerpt(highlight)
        await model.flush()
        let notes = try #require(try await db.bookNotesPage(for: source.id))
        #expect(try await db.blocks(of: notes.id).filter { $0.type == .excerpt }.count == 1)
    }

    @Test func bookNotesAreCreatedOnlyWhenTheEditorOpens() async throws {
        let folder = try await db.createFolder(name: "Курс")
        let source = try await db.addSource(
            title: "Книга", format: .epub, file: "missing.epub", originalName: "Книга.epub",
            folderId: folder.id, position: LibraryPoint(x: 200, y: 100)
        )
        let model = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await model.load()
        #expect(model.notes == nil)
        #expect(try await db.bookNotesPage(for: source.id) == nil, "Книгу открыли, но заметку ещё не начинали")

        let notes = try #require(await model.ensureNotes())
        let page = try #require(try await db.page(notes.pageId))
        #expect(page.sourceId == source.id)
        #expect(page.folderId == folder.id)
        #expect(page.position == LibraryPoint(x: 200 + LibraryLayout.cellWidth, y: 100))
        #expect(model.showsBookNotes)
        #expect(await model.ensureNotes()?.pageId == notes.pageId, "Вторая заметка не заводится")

        // В следующий раз книга сразу открывает уже заведённую заметку.
        let reopened = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await reopened.load()
        #expect(reopened.notes?.pageId == notes.pageId)
    }

    @Test func firstExcerptStartsTheBookNotes() async throws {
        let source = try await db.addSource(
            title: "Книга", format: .epub, file: "missing.epub", originalName: "Книга.epub"
        )
        let model = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await model.load()
        let highlight = Highlight(
            sourceId: source.id, locator: SourceLocator(section: 0, progression: 0), text: "Цитата", label: "гл. 1"
        )
        await model.addExcerpt(highlight)
        await model.flush()

        let page = try #require(try await db.bookNotesPage(for: source.id))
        #expect(page.folderId == nil, "Книга лежит в корне, и заметка тоже")
        let excerpts = try await db.blocks(of: page.id).filter { $0.type == .excerpt }
        #expect(excerpts.map(\.text) == ["Цитата"])
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
