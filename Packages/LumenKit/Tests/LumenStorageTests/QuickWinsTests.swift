import Foundation
import GRDB
import Testing
import LumenCore
@testable import LumenStorage

/// Корзина (удалить навсегда, автоочистка), копия страницы, общий поиск и чтение на главной.
struct QuickWinsTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func addBook(_ title: String = "Мастер и Маргарита", author: String? = nil, folderId: UUID? = nil) async throws -> Source {
        let file = try db.attachments.save(Data("книга".utf8), fileExtension: "epub")
        return try await db.addSource(title: title, author: author, format: .epub, file: file, originalName: "\(title).epub", folderId: folderId)
    }

    private func trash() async throws -> TrashSnapshot {
        try await db.reader.read { try TrashSnapshot.fetch($0) }
    }

    // MARK: Корзина

    @Test func deleteForeverRemovesOnlyThatItem() async throws {
        let kept = try await db.createPage(title: "Останется")
        let page = try await db.createPage(title: "Удалить")
        let child = try await db.createPage(title: "Подстраница", parentId: page.id)
        try await db.trashPage(kept.id)
        try await db.trashPage(page.id)

        try await db.deleteForever(.page(page.id))

        #expect(try await db.page(page.id) == nil)
        #expect(try await db.page(child.id) == nil)
        #expect(try await trash().pages.map(\.id) == [kept.id])
    }

    @Test func deleteForeverIgnoresLivingItems() async throws {
        let page = try await db.createPage(title: "Живая")
        try await db.deleteForever(.page(page.id))
        #expect(try await db.page(page.id) != nil)
    }

    @Test func deletingAFolderForeverTakesItsContentsAndFiles() async throws {
        let folder = try await db.createFolder(name: "Чтение")
        let inner = try await db.createFolder(name: "Внутри", parentId: folder.id)
        let page = try await db.createPage(title: "План", folderId: inner.id)
        let book = try await addBook(folderId: folder.id)
        let notes = try await db.notesPage(for: book.id)
        try await db.trashFolder(folder.id)

        try await db.deleteForever(.folder(folder.id))

        #expect(try await db.folder(folder.id) == nil)
        #expect(try await db.folder(inner.id) == nil)
        #expect(try await db.page(page.id) == nil)
        #expect(try await db.source(book.id) == nil)
        #expect(try await db.page(notes.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: db.attachments.url(for: book.file).path))
        #expect(try await trash().isEmpty)
    }

    @Test func oldTrashIsPurgedAfterThirtyDays() async throws {
        let old = try await db.createPage(title: "Старая")
        let recent = try await db.createPage(title: "Свежая")
        let book = try await addBook()
        try await db.trashPage(old.id)
        try await db.trashPage(recent.id)
        try await db.trashSource(book.id)
        let longAgo = Date().addingTimeInterval(-40 * 24 * 3600)
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE page SET deletedAt = ? WHERE id = ?", arguments: [longAgo, old.id])
            try db.execute(sql: "UPDATE source SET deletedAt = ? WHERE id = ?", arguments: [longAgo, book.id])
        }

        let removed = try await db.purgeTrash()

        #expect(removed == 2)
        #expect(try await db.page(old.id) == nil)
        #expect(try await db.source(book.id) == nil)
        #expect(try await trash().pages.map(\.id) == [recent.id])
    }

    // MARK: Копия страницы

    @Test func duplicateCopiesBlocksWithTheirTree() async throws {
        let folder = try await db.createFolder(name: "Учёба")
        let page = try await db.createPage(title: "Лекция", folderId: folder.id)
        let target = try await db.createPage(title: "Ссылка")
        let blocks = try await db.blocks(of: page.id)
        let toggle = Block(pageId: page.id, type: .toggle, content: BlockContent(text: "Раздел"), sortKey: "m")
        let inner = Block(pageId: page.id, parentBlockId: toggle.id, content: BlockContent(text: "Внутри"), sortKey: "a")
        let link = Block(pageId: page.id, type: .page, content: BlockContent(pageId: target.id), sortKey: "n")
        try await db.saveBlock(toggle)
        try await db.saveBlock(inner)
        try await db.saveBlock(link)

        let copy = try await db.duplicatePage(page.id)

        #expect(copy.id != page.id)
        #expect(copy.title == "Лекция (копия)")
        #expect(copy.folderId == folder.id)
        #expect(copy.sortKey > page.sortKey)
        let copied = try await db.blocks(of: copy.id)
        #expect(copied.count == blocks.count + 3)
        #expect(Set(copied.map(\.id)).isDisjoint(with: [toggle.id, inner.id, link.id]))
        let copiedToggle = try #require(copied.first { $0.type == .toggle })
        let copiedInner = try #require(copied.first { $0.text == "Внутри" })
        #expect(copiedInner.parentBlockId == copiedToggle.id)
        // Ссылка из копии тоже видна как обратная ссылка.
        let backlinks = try await db.reader.read { try PageLinksSnapshot.fetch($0, pageId: target.id).backlinks }
        #expect(Set(backlinks.map(\.id)) == [page.id, copy.id])
        // Копия находится поиском.
        #expect(try await db.search("Внутри").map(\.pageId).contains(copy.id))
    }

    @Test func duplicateOfBookNotesIsAnOrdinaryPage() async throws {
        let book = try await addBook()
        let notes = try await db.notesPage(for: book.id)
        let copy = try await db.duplicatePage(notes.id)
        #expect(copy.sourceId == nil)
        #expect(try await db.notesPage(for: book.id).id == notes.id)
    }

    // MARK: Поиск

    @Test func searchFindsBooksAndHighlights() async throws {
        let book = try await addBook("Война и мир", author: "Лев Толстой")
        _ = try await addBook("Анна Каренина")
        let quote = try await db.addHighlight(Highlight(
            sourceId: book.id, locator: SourceLocator(section: 0), text: "Всё смешалось в доме", label: "Глава 1"
        ))
        let commented = try await db.addHighlight(Highlight(
            sourceId: book.id, locator: SourceLocator(section: 1), text: "Другая цитата", label: "Глава 2"
        ))
        try await db.setHighlightNote(commented.id, note: "Важно для эссе")

        #expect(try await db.searchEverything("толстой").sources.map(\.id) == [book.id])
        #expect(try await db.searchEverything("ВОЙНА мир").sources.map(\.id) == [book.id])
        #expect(try await db.searchEverything("смешалось").highlights.map(\.id) == [quote.id])
        let byNote = try await db.searchEverything("эссе")
        #expect(byNote.highlights.map(\.id) == [commented.id])
        #expect(byNote.highlights.first?.sourceTitle == "Война и мир")
        #expect(try await db.searchEverything("   ").isEmpty)

        // Книга в корзине и её выделения не находятся.
        try await db.trashSource(book.id)
        let afterTrash = try await db.searchEverything("смешалось")
        #expect(afterTrash.highlights.isEmpty)
        #expect(try await db.searchEverything("толстой").sources.isEmpty)
    }

    // MARK: Главная

    @Test func homeShowsTheBookToContinueAndTodaysReading() async throws {
        let empty = try await db.reader.read { try HomeReadingSnapshot.fetch($0) }
        #expect(empty.current == nil)
        #expect(empty.sourceCount == 0)

        let first = try await addBook("Первая")
        let second = try await addBook("Вторая")
        // Ни одну ещё не открывали: предлагается последняя добавленная.
        #expect(try await db.reader.read { try HomeReadingSnapshot.fetch($0) }.current?.id == second.id)

        try await db.saveReadingPosition(first.id, locator: SourceLocator(section: 2), progress: 0.4)
        try await db.saveReadingSession(ReadingSession(sourceId: first.id, startedAt: Date(), endedAt: Date(), seconds: 900))
        let reading = try await db.reader.read { try HomeReadingSnapshot.fetch($0) }
        #expect(reading.current?.id == first.id)
        #expect(reading.stats.todaySeconds == 900)
        #expect(reading.stats.streakDays == 1)
        #expect(reading.sourceCount == 2)

        // Дочитанную книгу не предлагаем продолжить.
        try await db.saveReadingPosition(first.id, locator: SourceLocator(section: 9), progress: 1)
        #expect(try await db.reader.read { try HomeReadingSnapshot.fetch($0) }.current?.id == second.id)
    }
}
