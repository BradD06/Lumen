import Foundation
import Testing
import LumenCore
@testable import LumenStorage

struct DataTableRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func snapshot(_ pageId: UUID) async throws -> DataTableSnapshot {
        try await db.reader.read { try DataTableSnapshot.fetch($0, pageId: pageId) }
    }

    @Test func tasksDatabaseIsCreatedOnceWithExamples() async throws {
        let first = try await db.tasksDataTable()
        let second = try await db.tasksDataTable()
        #expect(first.id == second.id)

        let tasks = try await snapshot(first.pageId)
        #expect(tasks.page?.title == "Задачи")
        #expect(tasks.rows.count == 4)
        #expect(tasks.rows.allSatisfy { $0.page.parentId == first.pageId && $0.page.databaseId == first.id })

        // У задач свой пункт в сайдбаре, в списке баз их нет.
        let books = try await db.createDataTable(title: "Книги")
        let sidebar = try await db.reader.read { try SidebarSnapshot.fetch($0) }
        #expect(sidebar.databases.map(\.id) == [books.pageId])
    }

    @Test func rowsStayOutOfSubpageLists() async throws {
        let table = try await db.createDataTable(title: "Книги")
        try await db.addRow(to: table.id, title: "Война и мир")
        let library = try await db.reader.read { try LibrarySnapshot.fetch($0, folderId: nil) }
        let page = try #require(library.pages.first { $0.id == table.pageId })
        #expect(page.subpages.isEmpty)
    }

    @Test func valuesAreSavedAndCleared() async throws {
        let table = try await db.createDataTable(title: "База")
        let note = try #require(table.properties.first { $0.type == .text })
        let row = try await db.addRow(to: table.id, title: "Строка")

        try await db.setValue(.text("привет"), property: note.id, row: row.id)
        var rows = try await snapshot(table.pageId).rows
        #expect(rows.first?.value(note.id) == .text("привет"))

        try await db.setValue(nil, property: note.id, row: row.id)
        rows = try await snapshot(table.pageId).rows
        #expect(rows.first?.page.properties == nil)
    }

    @Test func manualOrder() async throws {
        let table = try await db.createDataTable(title: "База")
        let a = try await db.addRow(to: table.id, title: "A")
        let b = try await db.addRow(to: table.id, title: "B")
        let c = try await db.addRow(to: table.id, title: "C")
        try await db.moveRow(c.id, after: nil)
        try await db.moveRow(a.id, after: b.id)
        #expect(try await snapshot(table.pageId).rows.map(\.title) == ["C", "B", "A"])

        let d = try await db.addRow(to: table.id, title: "D", after: c.id)
        #expect(try await snapshot(table.pageId).rows.map(\.id) == [c.id, d.id, b.id, a.id])
    }

    @Test func removingPropertyAndOptionCleansRowsAndViews() async throws {
        let table = try await db.tasksDataTable()
        let status = try #require(table.firstProperty(of: [.status]))
        let priority = try #require(table.properties.first { $0.name == "Приоритет" })
        let rows = try await snapshot(table.pageId).rows
        #expect(rows.allSatisfy { $0.value(priority.id) != nil })

        let doing = status.options[1].id
        try await db.updateDataTable(table.id) { table in
            table.properties.removeAll { $0.id == priority.id }
            if let index = table.properties.firstIndex(where: { $0.id == status.id }) {
                table.properties[index].options.removeAll { $0.id == doing }
            }
        }

        let after = try await snapshot(table.pageId)
        #expect(after.rows.allSatisfy { $0.value(priority.id) == nil })
        #expect(after.rows.allSatisfy { $0.value(status.id) != .option(doing) })
        let views = try #require(after.table?.views)
        #expect(views.allSatisfy { view in !view.sorts.contains { $0.propertyId == priority.id } })
    }

    @Test func trashingDatabasePageTrashesRows() async throws {
        let table = try await db.createDataTable(title: "База")
        let row = try await db.addRow(to: table.id, title: "Строка")
        try await db.trashPage(table.pageId)
        #expect(try await db.page(row.id)?.isTrashed == true)
        let sidebar = try await db.reader.read { try SidebarSnapshot.fetch($0) }
        #expect(sidebar.databases.isEmpty)

        // Строка, вернувшаяся без базы, становится обычной страницей.
        try await db.restorePage(row.id)
        let restored = try #require(try await db.page(row.id))
        #expect(restored.parentId == nil)
        #expect(restored.databaseId == nil)
    }

    @Test func rowSnapshotFindsItsTable() async throws {
        let table = try await db.createDataTable(title: "База")
        let row = try await db.addRow(to: table.id, title: "Строка")
        let snapshot = try await db.reader.read { try DataRowSnapshot.fetch($0, rowId: row.id) }
        #expect(snapshot.table?.id == table.id)
        #expect(snapshot.row?.title == "Строка")
    }

    @Test func dataTableChangesAreLoggedForSync() async throws {
        let table = try await db.createDataTable(title: "База")
        let pending = try await db.pendingSyncChanges()
        #expect(pending.contains { $0.id == SyncRecordID(table: .dataTable, id: table.id) })
        let record = try #require(try await db.syncRecord(for: SyncRecordID(table: .dataTable, id: table.id)))
        #expect(record.record.fields["properties"] != nil)
    }

    @Test func rowsStayOutOfHomeScreen() async throws {
        let table = try await db.tasksDataTable()
        let home = try await db.reader.read { try HomeSnapshot.fetch($0) }
        #expect(home.pageCount == 1, "Считается только страница «Задачи», не сами задачи")
        #expect(home.recent.map(\.page.id) == [table.pageId])
    }
}
