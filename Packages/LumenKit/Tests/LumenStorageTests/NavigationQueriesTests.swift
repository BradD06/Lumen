import Foundation
import Testing
import LumenCore
@testable import LumenStorage

/// Путь над страницей, «Недавние» в сайдбаре и папки-подсказки при разборе «Входящих».
struct NavigationQueriesTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func crumbs(_ pageId: UUID) async throws -> [Breadcrumb] {
        try await db.reader.read { try BreadcrumbQuery.fetch($0, pageId: pageId) }
    }

    @Test func breadcrumbsGoFromLibraryThroughFoldersAndParents() async throws {
        let study = try await db.createFolder(name: "Учёба")
        let math = try await db.createFolder(name: "Матанализ", parentId: study.id)
        let course = try await db.createPage(title: "Курс", folderId: math.id)
        let lecture = try await db.createPage(title: "Лекция 1", parentId: course.id)

        #expect(try await crumbs(lecture.id).map(\.id) == ["library", "folder-\(study.id)", "folder-\(math.id)", "page-\(course.id)"])
        #expect(try await crumbs(course.id).map(\.id) == ["library", "folder-\(study.id)", "folder-\(math.id)"])
    }

    @Test func quickNoteBreadcrumbStartsAtInbox() async throws {
        let note = try await db.createQuickNote("Идея")
        let child = try await db.createPage(title: "Подробнее", parentId: note.id)
        #expect(try await crumbs(note.id).map(\.id) == ["inbox"])
        #expect(try await crumbs(child.id).map(\.id) == ["inbox", "page-\(note.id)"])
    }

    @Test func taskRowBreadcrumbGoesThroughItsDatabasePage() async throws {
        let table = try await db.tasksDataTable()
        let row = try await db.addRow(to: table.id, title: "Сдать отчёт")
        let path = try await crumbs(row.id)
        #expect(path.last?.id == "page-\(table.pageId)")
    }

    @Test func recentSkipsDatabaseRowsAndListsOpenedBooks() async throws {
        let note = try await db.createPage(title: "Заметка")
        let table = try await db.tasksDataTable()
        let row = try await db.addRow(to: table.id, title: "Задача")
        let book = try await db.addSource(title: "Книга", format: .epub, file: "book.epub", originalName: "book.epub")
        let unopened = try await db.addSource(title: "Не открыта", format: .epub, file: "other.epub", originalName: "other.epub")
        try await db.saveReadingPosition(book.id, locator: SourceLocator(section: 0), progress: 0.3)

        let recent = try await db.reader.read { try RecentQuery.fetch($0, limit: 10) }
        let ids = recent.map(\.id)
        #expect(ids.contains(note.id))
        #expect(ids.contains(book.id))
        #expect(!ids.contains(row.id))
        #expect(!ids.contains(unopened.id))
    }

    @Test func suggestedFoldersPutBusyFoldersFirst() async throws {
        let quiet = try await db.createFolder(name: "Тихая")
        let busy = try await db.createFolder(name: "Рабочая")
        _ = try await db.createPage(title: "Отчёт", folderId: busy.id)

        let folders = try await db.reader.read { try SuggestedFoldersQuery.fetch($0, limit: 3) }
        #expect(folders.map(\.id) == [busy.id, quiet.id])
    }
}
