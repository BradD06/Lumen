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

    @Test func notesPageIsCreatedOnceBesideTheBook() async throws {
        let folder = try await db.createFolder(name: "Чтение")
        let book = try await addBook(folderId: folder.id)
        try await db.setPosition(.source(book.id), LibraryPoint(x: 200, y: 100))
        #expect(try await db.bookNotesPage(for: book.id) == nil, "Пока заметку не открыли, её нет")

        let notes = try await db.notesPage(for: book.id)
        let again = try await db.notesPage(for: book.id)
        #expect(notes.id == again.id)
        #expect(notes.sourceId == book.id)
        #expect(notes.title == book.title)
        #expect(notes.folderId == folder.id, "Заметка лежит в той же папке, что и книга")
        #expect(notes.position == LibraryPoint(x: 200 + LibraryLayout.cellWidth, y: 100), "и прямо рядом с ней")
        #expect(try await db.bookNotesPage(for: book.id)?.id == notes.id)
        #expect(try await library(folder.id).pages.map(\.id) == [notes.id])
        #expect(try await library().folders.first?.itemCount == 2)
    }

    @Test func bookNotesWithoutFolderLieInTheLibraryRoot() async throws {
        let book = try await addBook()
        let notes = try await db.notesPage(for: book.id)
        #expect(notes.folderId == nil)
        #expect(try await library().pages.map(\.id) == [notes.id])
    }

    @Test func newPageBesideBookTakesTheNextFreeSpot() async throws {
        let folder = try await db.createFolder(name: "Чтение")
        let book = try await addBook(folderId: folder.id)
        try await db.setPosition(.source(book.id), LibraryPoint(x: 200, y: 100))
        let notes = try await db.notesPage(for: book.id)
        let page = try await db.createPage(besideSource: book.id)

        #expect(page.folderId == folder.id)
        #expect(page.sourceId == nil)
        #expect(page.position == LibraryPoint(x: 200, y: 100 + LibraryLayout.cellHeight), "Справа уже заметки, значит снизу")
        #expect(page.position != notes.position)
    }

    @Test func restoredBookBringsItsNotesOutOfATrashedFolder() async throws {
        let folder = try await db.createFolder(name: "Чтение")
        let book = try await addBook(folderId: folder.id)
        let notes = try await db.notesPage(for: book.id)

        try await db.trashFolder(folder.id)
        try await db.restoreSource(book.id)
        #expect(try await db.source(book.id)?.folderId == nil)
        let restored = try #require(try await db.page(notes.id))
        #expect(!restored.isTrashed)
        #expect(restored.folderId == nil, "Заметки поднимаются в корень вместе с книгой")
    }

    @Test func migrationMovesOldBookNotesBesideBooksAndDropsEmptyOnes() throws {
        let queue = try DatabaseQueue(configuration: AppDatabase.configuration)
        try AppDatabase.migrator.migrate(queue, upTo: "v8: databases")
        let folder = UUID(), written = UUID(), untouched = UUID(), writtenNotes = UUID(), emptyNotes = UUID()
        try queue.write { db in
            let now = Date()
            try db.execute(
                sql: "INSERT INTO folder (id, name, createdAt, updatedAt) VALUES (?, 'Чтение', ?, ?)",
                arguments: [folder, now, now]
            )
            for (id, x) in [(written, 200.0), (untouched, 600.0)] {
                try db.execute(sql: """
                    INSERT INTO source (id, title, format, file, originalName, folderId, canvasX, canvasY, createdAt, updatedAt)
                    VALUES (?, 'Книга', 'epub', 'f.epub', 'f.epub', ?, ?, 100, ?, ?)
                    """, arguments: [id, folder, x, now, now])
            }
            for (page, source, text) in [(writtenNotes, written, "Мысли о книге"), (emptyNotes, untouched, "")] {
                try db.execute(sql: """
                    INSERT INTO page (id, title, icon, sourceId, sortKey, createdAt, updatedAt)
                    VALUES (?, 'Книга', '📖', ?, 'a', ?, ?)
                    """, arguments: [page, source, now, now])
                let content = String(decoding: try JSONEncoder().encode(BlockContent(text: text)), as: UTF8.self)
                try db.execute(sql: """
                    INSERT INTO block (id, pageId, type, content, sortKey, createdAt, updatedAt)
                    VALUES (?, ?, 'paragraph', ?, 'a', ?, ?)
                    """, arguments: [UUID(), page, content, now, now])
            }
        }

        _ = try AppDatabase(queue)
        try queue.read { db in
            let moved = try #require(try Page.fetchOne(db, key: writtenNotes))
            #expect(moved.folderId == folder)
            #expect(moved.position == LibraryPoint(x: 200 + LibraryLayout.cellWidth, y: 100))
            #expect(try Page.fetchOne(db, key: emptyNotes) == nil, "Пустая заметка, заведённая сама, удаляется")
        }
    }

    @Test func placeLinkMovesReadingPositionButKeepsProgress() async throws {
        let book = try await addBook()
        try await db.saveReadingPosition(book.id, locator: SourceLocator(section: 9), progress: 0.6)
        let place = SourceLocator(section: 2, progression: 0.3, textOffset: 840)
        try await db.setReadingLocator(book.id, locator: place)
        let saved = try #require(try await db.source(book.id))
        #expect(saved.locator == place)
        #expect(saved.progress == 0.6)
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

    @Test func exactReadingPlaceIsSaved() async throws {
        let book = try await addBook()
        // Книга: строка вверху экрана. PDF: точка страницы в левом верхнем углу.
        let chapter = SourceLocator(section: 2, progression: 0.3, textOffset: 4_210)
        try await db.saveReadingPosition(book.id, locator: chapter, progress: 0.2)
        #expect(try await db.source(book.id)?.locator?.textOffset == 4_210)

        let page = SourceLocator(section: 41, progression: 0.5, point: LocatorPoint(x: 36.5, y: 612.25))
        try await db.saveReadingPosition(book.id, locator: page, progress: 0.5)
        #expect(try await db.source(book.id)?.locator == page)
    }

    @Test func oldReadingPlaceWithoutPointStillDecodes() throws {
        let json = #"{"section":4,"progression":0.25}"#
        let locator = try JSONDecoder().decode(SourceLocator.self, from: Data(json.utf8))
        #expect(locator.section == 4)
        #expect(locator.point == nil)
        #expect(locator.textOffset == nil)
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
