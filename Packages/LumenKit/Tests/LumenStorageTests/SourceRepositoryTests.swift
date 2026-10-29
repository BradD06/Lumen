import Foundation
import GRDB
import Testing
import LumenCore
@testable import LumenStorage

struct SourceRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func library(_ folderId: UUID? = nil) async throws -> LibrarySnapshot {
        try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: folderId) }
    }

    private func addBook(_ title: String = "Мастер и Маргарита", folderId: UUID? = nil) async throws -> Source {
        let file = try db.attachments.save(Data("книга".utf8), fileExtension: "epub")
        return try await db.addSource(title: title, format: .epub, file: file, originalName: "\(title).epub", folderId: folderId)
    }

    @Test func booksLieInFoldersNextToPages() async throws {
        let folder = try await db.createFolder(name: "Чтение")
        let book = try await addBook(folderId: folder.id)
        _ = try await db.createPage(title: "План", folderId: folder.id)

        let inside = try await library(folder.id)
        #expect(inside.sources.map(\.id) == [book.id])
        #expect(try await library().folders.first?.itemCount == 2)

        try await db.moveSource(book.id, toFolder: nil)
        #expect(try await library().sources.map(\.id) == [book.id])
        #expect(try await library(folder.id).sources.isEmpty)

        try await db.setPosition(.source(book.id), LibraryPoint(x: 10, y: 20))
        #expect(try await db.source(book.id)?.position == LibraryPoint(x: 10, y: 20))
    }

    @Test func notesPageIsCreatedOnceAndHiddenFromLibrary() async throws {
        let book = try await addBook()
        let notes = try await db.notesPage(for: book.id)
        let again = try await db.notesPage(for: book.id)

        #expect(notes.id == again.id)
        #expect(notes.sourceId == book.id)
        #expect(notes.title == book.title)
        #expect(try await library().pages.isEmpty, "Заметки к книге живут рядом с книгой, а не отдельной плиткой")
    }

    @Test func readingPositionAndHighlightsAreSaved() async throws {
        let book = try await addBook()
        let locator = SourceLocator(section: 3, progression: 0.4)
        try await db.saveReadingPosition(book.id, locator: locator, progress: 0.25)
        let saved = try #require(try await db.source(book.id))
        #expect(saved.locator == locator)
        #expect(saved.progress == 0.25)
        #expect(saved.lastOpenedAt != nil)

        let highlight = try await db.addHighlight(Highlight(
            sourceId: book.id,
            locator: SourceLocator(section: 3, text: "Рукописи не горят", textOffset: 120),
            text: "Рукописи не горят",
            label: "Глава 4"
        ))
        try await db.setHighlightColor(highlight.id, color: .pink)
        try await db.setHighlightNote(highlight.id, note: "  Воланд  ")
        let stored = try #require(try await db.highlight(highlight.id))
        #expect(stored.color == .pink)
        #expect(stored.note == "Воланд")
        #expect(stored.locator.textOffset == 120)
        #expect(try await library().sources.first?.highlightCount == 1)
    }

    @Test func trashTakesNotesAlongAndRestoresThem() async throws {
        let book = try await addBook()
        let notes = try await db.notesPage(for: book.id)

        try await db.trashSource(book.id)
        #expect(try await db.source(book.id)?.isTrashed == true)
        #expect(try await db.page(notes.id)?.isTrashed == true)
        let trash = try await db.reader.read { try TrashSnapshot.fetch($0) }
        #expect(trash.sources.map(\.id) == [book.id])
        #expect(trash.pages.isEmpty, "Заметки вернутся вместе с книгой")

        try await db.restoreSource(book.id)
        #expect(try await db.source(book.id)?.isTrashed == false)
        #expect(try await db.page(notes.id)?.isTrashed == false)
    }

    @Test func trashedFolderTakesBooksAlong() async throws {
        let folder = try await db.createFolder(name: "Чтение")
        let book = try await addBook(folderId: folder.id)

        try await db.trashFolder(folder.id)
        #expect(try await db.source(book.id)?.isTrashed == true)

        try await db.restoreFolder(folder.id)
        #expect(try await db.source(book.id)?.isTrashed == false)
        #expect(try await db.source(book.id)?.folderId == folder.id)
    }

    @Test func emptyTrashDeletesBookFiles() async throws {
        let book = try await addBook()
        let fileURL = db.attachments.url(for: book.file)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let highlight = try await db.addHighlight(Highlight(
            sourceId: book.id, locator: SourceLocator(section: 0), text: "цитата", label: "1"
        ))

        try await db.trashSource(book.id)
        try await db.emptyTrash()

        #expect(try await db.source(book.id) == nil)
        #expect(try await db.highlight(highlight.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func excerptTextIsSearchable() async throws {
        let page = try await db.createPage(title: "Цитаты")
        let block = Block(
            pageId: page.id,
            type: .excerpt,
            content: BlockContent(
                runs: [TextRun("Рукописи не горят")],
                excerpt: ExcerptReference(sourceId: UUID(), highlightId: UUID(), label: "Глава 24")
            ),
            sortKey: "b"
        )
        try await db.saveBlock(block)
        let saved = try #require(try await db.blocks(of: page.id).first { $0.id == block.id })
        #expect(saved.content.excerpt?.label == "Глава 24")
        #expect(try await db.search("рукописи").map(\.pageId) == [page.id])
    }

    @Test func deletingTheLastExcerptHidesItsHighlight() async throws {
        let book = try await addBook()
        let highlight = try await db.addHighlight(Highlight(
            sourceId: book.id, locator: SourceLocator(section: 0), text: "Цитата", label: "Глава 1"
        ))
        let page = try await db.createPage(title: "Конспект")
        func excerpt(_ sortKey: String) -> Block {
            Block(
                pageId: page.id,
                type: .excerpt,
                content: BlockContent(
                    runs: [TextRun("Цитата")],
                    excerpt: ExcerptReference(sourceId: book.id, highlightId: highlight.id, label: "Глава 1")
                ),
                sortKey: sortKey
            )
        }
        let first = excerpt("b")
        let second = excerpt("c")
        try await db.saveBlock(first)
        try await db.saveBlock(second)

        try await db.deleteBlock(first.id)
        #expect(try await db.highlight(highlight.id)?.isTrashed == false)

        try await db.deleteBlock(second.id)
        #expect(try await db.highlight(highlight.id)?.isTrashed == true)
        #expect(try await library().sources.first?.highlightCount == 0)

        // Отмена удаления возвращает выписку, а с ней и выделение.
        try await db.saveBlock(second)
        #expect(try await db.highlight(highlight.id)?.isTrashed == false)

        try await db.deleteBlock(second.id)
        try await db.emptyTrash()
        #expect(try await db.highlight(highlight.id) == nil)
    }
}
