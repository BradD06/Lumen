import Foundation
import Testing
import LumenCore
@testable import LumenStorage

struct FolderRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func library(_ folderId: UUID? = nil) async throws -> LibrarySnapshot {
        try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: folderId) }
    }

    @Test func foldersAndPagesLieWhereTheyWereCreated() async throws {
        let study = try await db.createFolder(name: "Учёба", color: 2, position: LibraryPoint(x: 40, y: 30))
        let math = try await db.createFolder(name: "Матанализ", parentId: study.id)
        let lecture = try await db.createPage(title: "Лекция 1", folderId: study.id)
        let loose = try await db.createPage(title: "План")

        let root = try await library()
        #expect(root.folders.map(\.id) == [study.id])
        #expect(root.folders.first?.itemCount == 2)
        #expect(root.folders.first?.folder.position == LibraryPoint(x: 40, y: 30))
        #expect(root.pages.map(\.id) == [loose.id])

        let inside = try await library(study.id)
        #expect(inside.folder?.id == study.id)
        #expect(inside.folders.map(\.id) == [math.id])
        #expect(inside.pages.map(\.id) == [lecture.id])

        let nested = try await library(math.id)
        #expect(nested.path.map(\.id) == [study.id])
    }

    @Test func quickNotesAndSubpagesDoNotGoIntoFolders() async throws {
        let folder = try await db.createFolder(name: "Папка")
        let note = try await db.createPage(inInbox: true, folderId: folder.id)
        let parent = try await db.createPage(title: "Родитель")
        let child = try await db.createPage(parentId: parent.id, folderId: folder.id)
        #expect(note.folderId == nil)
        #expect(child.folderId == nil)
        #expect(try await library(folder.id).pages.isEmpty)
    }

    @Test func moveIntoFolderTakesPageOutOfInboxAndParent() async throws {
        let folder = try await db.createFolder(name: "Учёба")
        let note = try await db.createQuickNote("Идея")
        let parent = try await db.createPage(title: "Родитель")
        let child = try await db.createPage(title: "Ребёнок", parentId: parent.id)
        try await db.setPosition(.page(note.id), LibraryPoint(x: 1, y: 2))

        try await db.movePage(note.id, toFolder: folder.id)
        try await db.movePage(child.id, toFolder: folder.id)

        let moved = try #require(try await db.page(note.id))
        #expect(!moved.inInbox)
        #expect(moved.folderId == folder.id)
        #expect(moved.position == nil, "На новом месте предмет встаёт в свободную ячейку")
        #expect(try await db.page(child.id)?.parentId == nil)
        #expect(try await library(folder.id).pages.map(\.id).sorted() == [note.id, child.id].sorted())
    }

    @Test func cannotMoveFolderIntoItself() async throws {
        let outer = try await db.createFolder(name: "Внешняя")
        let inner = try await db.createFolder(name: "Внутренняя", parentId: outer.id)
        await #expect(throws: StorageError.invalidMove) {
            try await db.moveFolder(outer.id, toParent: inner.id)
        }
        await #expect(throws: StorageError.invalidMove) {
            try await db.moveFolder(outer.id, toParent: outer.id)
        }
        try await db.moveFolder(inner.id, toParent: nil)
        #expect(try await db.folder(inner.id)?.parentId == nil)
    }

    @Test func positionsDoNotTouchEditTime() async throws {
        let created = try await db.createPage(title: "Страница")
        let page = try #require(try await db.page(created.id))
        try await db.setPositions([.page(page.id): LibraryPoint(x: 300, y: 120)])
        let moved = try #require(try await db.page(page.id))
        #expect(moved.position == LibraryPoint(x: 300, y: 120))
        #expect(moved.updatedAt == page.updatedAt)
    }

    @Test func renameAndColor() async throws {
        let folder = try await db.createFolder(name: "Новая папка")
        try await db.renameFolder(folder.id, name: "Книги")
        try await db.setFolderColor(folder.id, color: 99)
        let changed = try #require(try await db.folder(folder.id))
        #expect(changed.name == "Книги")
        #expect(changed.color == Folder.colorCount - 1)
    }

    @Test func trashAndRestoreFolderWithContents() async throws {
        let study = try await db.createFolder(name: "Учёба")
        let math = try await db.createFolder(name: "Матанализ", parentId: study.id)
        let lecture = try await db.createPage(title: "Пределы", folderId: math.id)
        let earlier = try await db.createPage(title: "Черновик", folderId: study.id)
        try await db.trashPage(earlier.id)

        try await db.trashFolder(study.id)
        #expect(try await db.folder(math.id)?.isTrashed == true)
        #expect(try await db.page(lecture.id)?.isTrashed == true)
        #expect(try await db.search("Пределы").isEmpty)
        #expect(try await library().folders.isEmpty)
        #expect(try await library(study.id).isMissing)

        let trash = try await db.reader.read { try TrashSnapshot.fetch($0) }
        #expect(trash.folders.map(\.id) == [study.id], "Вложенная папка вернётся вместе с родителем")
        #expect(trash.pages.isEmpty, "Страницы удалённой папки отдельно не показываются")
        #expect(try await db.reader.read { try SidebarSnapshot.fetch($0) }.trashCount == 4)

        try await db.restoreFolder(study.id)
        #expect(try await db.folder(math.id)?.isTrashed == false)
        #expect(try await db.page(lecture.id)?.isTrashed == false)
        #expect(try await db.search("Пределы").map(\.pageId) == [lecture.id])
        #expect(try await db.page(earlier.id)?.isTrashed == true, "Удалённое раньше папки остаётся в корзине")
    }

    @Test func restoringPageFromTrashedFolderPutsItInRoot() async throws {
        let folder = try await db.createFolder(name: "Учёба")
        let page = try await db.createPage(title: "Лекция", folderId: folder.id)
        try await db.trashFolder(folder.id)
        try await db.restorePage(page.id)

        let restored = try #require(try await db.page(page.id))
        #expect(restored.folderId == nil)
        #expect(try await library().pages.map(\.id) == [page.id])
    }

    @Test func emptyTrashDeletesFoldersButKeepsLivePages() async throws {
        let folder = try await db.createFolder(name: "Старое")
        let page = try await db.createPage(title: "Лекция", folderId: folder.id)
        try await db.trashFolder(folder.id)
        try await db.restorePage(page.id)
        try await db.emptyTrash()
        #expect(try await db.folder(folder.id) == nil)
        #expect(try await db.page(page.id) != nil)
    }

    @Test func folderTreeIsSortedByName() async throws {
        let b = try await db.createFolder(name: "Работа")
        let a = try await db.createFolder(name: "английский")
        let inner = try await db.createFolder(name: "Проект", parentId: b.id)
        let tree = try await db.reader.read { try FolderTreeQuery.fetch($0) }
        #expect(tree.map(\.id) == [a.id, b.id])
        #expect(tree.last?.children.map(\.id) == [inner.id])
        #expect(tree.flatMap(\.flattened).count == 3)
    }
}
