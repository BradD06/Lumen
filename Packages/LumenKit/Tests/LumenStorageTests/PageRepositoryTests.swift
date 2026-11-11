import Foundation
import Testing
import LumenCore
@testable import LumenStorage

struct PageRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func quickNoteGoesToInbox() async throws {
        let page = try await db.createQuickNote("Купить молоко\n\nи хлеб\nи сыр")
        #expect(page.inInbox)
        #expect(page.title == "Купить молоко")

        let blocks = try await db.blocks(of: page.id)
        #expect(blocks.map(\.text) == ["и хлеб", "и сыр"])

        let inbox = try await db.reader.read { try InboxQuery.fetch($0) }
        #expect(inbox.map(\.page.id) == [page.id])
        #expect(inbox.first?.excerpt == "и хлеб\nи сыр")

        let sidebar = try await db.reader.read { try SidebarSnapshot.fetch($0) }
        #expect(sidebar.inboxCount == 1)
        let counts = try await db.reader.read { try SidebarSnapshot.fetchCounts($0) }
        #expect(counts.inboxCount == 1, "Табло комнат считает записки так же, как полный снимок")
        #expect(counts.favorites.isEmpty && counts.folders.isEmpty, "Табло не грузит списки")
        let library = try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: nil) }
        #expect(library.pages.isEmpty, "Входящие не показываются в библиотеке")
    }

    @Test func pagePreviewShowsTheStartOfTheTextAndHidesTrashedPages() async throws {
        let page = try await db.createQuickNote("Митоз по фазам\n\nПрофаза: хромосомы скручиваются")
        let preview = try await db.reader.read { try PagePreviewQuery.fetch($0, pageId: page.id) }
        #expect(preview?.page.title == "Митоз по фазам")
        #expect(preview?.excerpt == "Профаза: хромосомы скручиваются")

        try await db.trashPage(page.id)
        let trashed = try await db.reader.read { try PagePreviewQuery.fetch($0, pageId: page.id) }
        #expect(trashed == nil)
    }

    @Test func filedNoteCanGoBackToInbox() async throws {
        let note = try await db.createQuickNote("Спросить про мейоз")
        let folder = try await db.createFolder(name: "Биология")
        try await db.movePage(note.id, toFolder: folder.id)
        #expect(try await db.reader.read { try InboxQuery.fetch($0) }.isEmpty)

        try await db.returnToInbox(note.id)
        let inbox = try await db.reader.read { try InboxQuery.fetch($0) }
        #expect(inbox.map(\.page.id) == [note.id])
        #expect(inbox.first?.page.folderId == nil)
        let library = try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: folder.id) }
        #expect(library.pages.isEmpty)
    }

    @Test func newPageHasOneEmptyParagraph() async throws {
        let page = try await db.createPage(title: "Конспект")
        let blocks = try await db.blocks(of: page.id)
        #expect(blocks.count == 1)
        #expect(blocks.first?.type == .paragraph)
        #expect(blocks.first?.text == "")
    }

    @Test func pagesFormATree() async throws {
        let course = try await db.createPage(title: "Курс")
        let lecture1 = try await db.createPage(title: "Лекция 1", parentId: course.id)
        let lecture2 = try await db.createPage(title: "Лекция 2", parentId: course.id)
        let other = try await db.createPage(title: "Другое")

        let library = try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: nil) }
        #expect(library.pages.map(\.id) == [course.id, other.id])
        #expect(library.pages.first?.subpages.map(\.id) == [lecture1.id, lecture2.id])
        #expect(library.pages.last?.subpages.isEmpty == true)
    }

    @Test func moveFromInboxToPage() async throws {
        let note = try await db.createQuickNote("Идея")
        let project = try await db.createPage(title: "Проект")
        try await db.movePage(note.id, toParent: project.id)

        let moved = try #require(try await db.page(note.id))
        #expect(!moved.inInbox)
        #expect(moved.parentId == project.id)
    }

    @Test func cannotMovePageIntoItsChild() async throws {
        let parent = try await db.createPage(title: "Родитель")
        let child = try await db.createPage(title: "Ребёнок", parentId: parent.id)
        await #expect(throws: StorageError.invalidMove) {
            try await db.movePage(parent.id, toParent: child.id)
        }
    }

    @Test func trashAndRestoreSubtree() async throws {
        let parent = try await db.createPage(title: "Учёба")
        let child = try await db.createPage(title: "Матанализ", parentId: parent.id)

        try await db.trashPage(parent.id)
        #expect(try await db.page(child.id)?.isTrashed == true)
        let sidebar = try await db.reader.read { try SidebarSnapshot.fetch($0) }
        #expect(try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: nil) }.pages.isEmpty)
        #expect(sidebar.trashCount == 2)
        #expect(try await db.search("Матанализ").isEmpty, "Страницы в корзине не ищутся")

        try await db.restorePage(parent.id)
        let library = try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: nil) }
        #expect(library.pages.first?.subpages.map(\.id) == [child.id])
        #expect(try await db.search("Матанализ").map(\.pageId) == [child.id])
    }

    @Test func restoringChildOfTrashedParentMovesItToTop() async throws {
        let parent = try await db.createPage(title: "Папка")
        let child = try await db.createPage(title: "Файл", parentId: parent.id)
        try await db.trashPage(parent.id)
        try await db.restorePage(child.id)

        let restored = try #require(try await db.page(child.id))
        #expect(restored.parentId == nil)
        #expect(!restored.isTrashed)
    }

    @Test func emptyTrashDeletesForever() async throws {
        let page = try await db.createPage(title: "Черновик")
        try await db.trashPage(page.id)
        try await db.emptyTrash()
        #expect(try await db.page(page.id) == nil)
        #expect(try await db.blocks(of: page.id).isEmpty)
    }

    @Test func favorites() async throws {
        let page = try await db.createPage(title: "Важное")
        try await db.setFavorite(page.id, true)
        let sidebar = try await db.reader.read { try SidebarSnapshot.fetch($0) }
        #expect(sidebar.favorites.map(\.id) == [page.id])
    }

    @Test func homeSnapshotCounts() async throws {
        _ = try await db.createQuickNote("Мысль")
        _ = try await db.createPage(title: "Страница")
        let home = try await db.reader.read { try HomeSnapshot.fetch($0) }
        #expect(home.inboxCount == 1)
        #expect(home.pageCount == 2)
        #expect(home.editedToday == 2)
        #expect(home.recent.count == 2)
    }
}

struct BlockAndSearchTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test func savedBlocksAreSearchable() async throws {
        let page = try await db.createPage(title: "Философия")
        var block = try #require(try await db.blocks(of: page.id).first)
        block.text = "Познай самого себя"
        try await db.saveBlock(block)

        let next = Block(pageId: page.id, type: .quote, content: BlockContent(text: "Я знаю, что ничего не знаю"),
                         sortKey: SortKey.between(block.sortKey, nil))
        try await db.saveBlock(next)

        #expect(try await db.blocks(of: page.id).map(\.type) == [.paragraph, .quote])

        let byBody = try await db.search("позна")
        #expect(byBody.map(\.pageId) == [page.id])
        #expect(byBody.first?.title == "Философия")

        let byTitle = try await db.search("ФИЛОС")
        #expect(byTitle.map(\.pageId) == [page.id])

        #expect(try await db.search("ничего знаю").count == 1)
        #expect(try await db.search("квантовая").isEmpty)
    }

    @Test func renameUpdatesSearch() async throws {
        let page = try await db.createPage(title: "Старое")
        try await db.renamePage(page.id, title: "Новое название")
        #expect(try await db.search("старое").isEmpty)
        #expect(try await db.search("новое").map(\.pageId) == [page.id])
    }

    @Test func deleteBlock() async throws {
        let page = try await db.createQuickNote("Список\nпервый\nвторой")
        let blocks = try await db.blocks(of: page.id)
        try await db.deleteBlock(blocks[0].id)
        #expect(try await db.blocks(of: page.id).map(\.text) == ["второй"])
        #expect(try await db.search("первый").isEmpty)
    }

    /// Редактор пишет название, новые и удалённые блоки одной записью, и поиск видит всё сразу.
    @Test func pageEditsAreSavedTogether() async throws {
        let page = try await db.createQuickNote("Список\nпервый\nвторой")
        let blocks = try await db.blocks(of: page.id)
        let added = Block(pageId: page.id, content: BlockContent(text: "третий"), sortKey: "zz")

        try await db.savePageEdits(pageId: page.id, title: "Покупки", saving: [added], deleting: [blocks[0].id])

        #expect(try await db.blocks(of: page.id).map(\.text) == ["второй", "третий"])
        #expect(try await db.page(page.id)?.title == "Покупки")
        #expect(try await db.search("первый").isEmpty)
        #expect(try await db.search("третий").map(\.pageId) == [page.id])
        #expect(try await db.search("покупки").map(\.pageId) == [page.id])
    }

    @Test func blockContentSurvivesRoundTrip() async throws {
        let page = try await db.createPage()
        let todo = Block(pageId: page.id, type: .todo, content: BlockContent(text: "Сдать отчёт", isChecked: true),
                         sortKey: "a")
        try await db.saveBlock(todo)
        let loaded = try #require(try await db.blocks(of: page.id).first { $0.id == todo.id })
        #expect(loaded.type == .todo)
        #expect(loaded.content.isChecked)
        #expect(loaded.text == "Сдать отчёт")
    }

    @Test(arguments: [
        ("", nil),
        ("  ", nil),
        ("кот", "\"кот\"*"),
        ("кот \"OR\" пёс", "\"кот\"* \"OR\"* \"пёс\"*"),
        ("c++ (2024)", "\"c\"* \"2024\"*"),
    ] as [(String, String?)])
    func ftsPatternIsSafe(input: String, expected: String?) {
        #expect(AppDatabase.ftsPattern(input) == expected)
    }

    @Test func onDiskDatabaseMigrates() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try AppDatabase.onDisk(at: url)
        _ = try AppDatabase.onDisk(at: url)
    }
}
