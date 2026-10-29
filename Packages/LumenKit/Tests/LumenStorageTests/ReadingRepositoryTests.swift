import Foundation
import GRDB
import Testing
import LumenCore
@testable import LumenStorage

struct ReadingRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func addBook() async throws -> Source {
        let file = try db.attachments.save(Data("книга".utf8), fileExtension: "epub")
        return try await db.addSource(title: "Книга", format: .epub, file: file, originalName: "Книга.epub")
    }

    @Test func sessionIsRewrittenWhileTheBookIsOpen() async throws {
        let book = try await addBook()
        var session = ReadingSession(sourceId: book.id, startedAt: Date(), endedAt: Date(), seconds: 60)
        try await db.saveReadingSession(session)
        session.seconds = 600
        try await db.saveReadingSession(session)

        let stats = try await db.readingStats(of: book.id)
        #expect(stats.totalSeconds == 600)
        #expect(stats.streakDays == 1)
    }

    @Test func dashboardListsHighlightsAndPagesWithExcerpts() async throws {
        let book = try await addBook()
        let highlight = try await db.addHighlight(Highlight(
            sourceId: book.id, locator: SourceLocator(section: 0), text: "Цитата", label: "Глава 1"
        ))
        let notes = try await db.notesPage(for: book.id)
        let summary = try await db.createPage(title: "Конспект")
        for (page, key) in [(notes.id, "b"), (summary.id, "b"), (summary.id, "c")] {
            try await db.saveBlock(Block(
                pageId: page,
                type: .excerpt,
                content: BlockContent(
                    runs: [TextRun("Цитата")],
                    excerpt: ExcerptReference(sourceId: book.id, highlightId: highlight.id, label: "Глава 1")
                ),
                sortKey: key
            ))
        }
        // Выписка из другой книги не считается.
        try await db.saveBlock(Block(
            pageId: summary.id,
            type: .excerpt,
            content: BlockContent(excerpt: ExcerptReference(sourceId: UUID(), highlightId: UUID(), label: "")),
            sortKey: "d"
        ))

        let snapshot = try await db.reader.read { try SourceDashboardSnapshot.fetch($0, sourceId: book.id) }
        #expect(snapshot.source?.id == book.id)
        #expect(snapshot.highlights.map(\.id) == [highlight.id])
        #expect(snapshot.notesPage?.id == notes.id)
        #expect(snapshot.excerptPages.map(\.page.id) == [summary.id])
        #expect(snapshot.excerptPages.first?.excerptCount == 2)

        try await db.saveReadingSession(ReadingSession(sourceId: book.id, startedAt: Date(), endedAt: Date(), seconds: 90))
        try await db.trashSource(book.id)
        try await db.emptyTrash()
        #expect(try await db.reader.read { try ReadingSession.fetchCount($0) } == 0)
    }
}
