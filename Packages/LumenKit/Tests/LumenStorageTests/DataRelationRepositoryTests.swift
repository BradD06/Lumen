import Foundation
import Testing
import LumenCore
@testable import LumenStorage

/// Связи между базами в SQLite: обратная колонка, её включение и выключение, удаление связи.
struct DataRelationRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func snapshot(_ pageId: UUID) async throws -> DataTableSnapshot {
        try await db.reader.read { try DataTableSnapshot.fetch($0, pageId: pageId) }
    }

    private func table(_ id: UUID) async throws -> DataTable {
        try #require(try await db.dataTable(id))
    }

    @Test func twoWayRelationKeepsBothSidesInSync() async throws {
        let projects = try await db.createDataTable(title: "Проекты")
        let books = try await db.createDataTable(title: "Книги")
        let relation = try await db.addRelation(to: projects.id, target: books.id, twoWay: true)
        #expect(relation.name == "Книги")
        let pairedId = try #require(relation.relation?.pairedPropertyId)
        let paired = try #require(try await table(books.id).property(pairedId))
        #expect(paired.name == "Проекты")
        #expect(paired.relation == RelationConfig(targetTableId: projects.id, pairedPropertyId: relation.id))

        let thesis = try await db.addRow(to: projects.id, title: "Диплом")
        let war = try await db.addRow(to: books.id, title: "Война и мир")
        let anna = try await db.addRow(to: books.id, title: "Анна Каренина")

        try await db.setValue(.pages([war.id, anna.id, war.id]), property: relation.id, row: thesis.id)
        var bookRows = try await snapshot(books.pageId).rows
        #expect(bookRows.allSatisfy { $0.value(pairedId) == .pages([thesis.id]) })
        var projectRows = try await snapshot(projects.pageId)
        #expect(projectRows.rows.first?.value(relation.id) == .pages([war.id, anna.id]))
        #expect(projectRows.relations.rows[books.id]?.count == 2)
        #expect(projectRows.relations.tableTitles[books.id] == "Книги")
        #expect(projectRows.databases.map(\.title).sorted() == ["Книги", "Проекты"])

        // Убрали связь со стороны книги: проект тоже её теряет.
        try await db.setValue(nil, property: pairedId, row: anna.id)
        projectRows = try await snapshot(projects.pageId)
        #expect(projectRows.rows.first?.value(relation.id) == .pages([war.id]))
        bookRows = try await snapshot(books.pageId).rows
        #expect(bookRows.first { $0.id == anna.id }?.value(pairedId) == nil)
    }

    @Test func newRowWithRelationIsLinkedBack() async throws {
        let projects = try await db.createDataTable(title: "Проекты")
        let tasks = try await db.createDataTable(title: "Задачи")
        let relation = try await db.addRelation(to: tasks.id, target: projects.id, twoWay: true)
        let pairedId = try #require(relation.relation?.pairedPropertyId)
        let thesis = try await db.addRow(to: projects.id, title: "Диплом")

        var values = PropertyValues()
        values[relation.id] = .pages([thesis.id])
        let task = try await db.addRow(to: tasks.id, title: "Введение", values: values)
        let rows = try await snapshot(projects.pageId).rows
        #expect(rows.first?.value(pairedId) == .pages([task.id]))
    }

    @Test func turningTwoWayOnFillsTheOtherSideAndOffRemovesIt() async throws {
        let projects = try await db.createDataTable(title: "Проекты")
        let books = try await db.createDataTable(title: "Книги")
        let relation = try await db.addRelation(to: projects.id, target: books.id, twoWay: false)
        #expect(relation.relation?.isTwoWay == false)
        let thesis = try await db.addRow(to: projects.id, title: "Диплом")
        let war = try await db.addRow(to: books.id, title: "Война и мир")
        try await db.setValue(.pages([war.id]), property: relation.id, row: thesis.id)
        let before = try await table(books.id)
        #expect(before.properties.count == 2)

        try await db.setRelationTwoWay(true, table: projects.id, property: relation.id)
        let pairedId = try #require(try await table(projects.id).property(relation.id)?.relation?.pairedPropertyId)
        let linked = try await snapshot(books.pageId).rows
        #expect(linked.first?.value(pairedId) == .pages([thesis.id]))

        try await db.setRelationTwoWay(false, table: projects.id, property: relation.id)
        let after = try await table(books.id)
        #expect(after.property(pairedId) == nil)
        let unlinked = try await snapshot(books.pageId).rows
        #expect(unlinked.first?.page.properties == nil)
        // Сама связь со стороны проекта осталась.
        let projectRows = try await snapshot(projects.pageId).rows
        #expect(projectRows.first?.value(relation.id) == .pages([war.id]))
    }

    @Test func deletingRelationLeavesOtherSideOneWay() async throws {
        let projects = try await db.createDataTable(title: "Проекты")
        let books = try await db.createDataTable(title: "Книги")
        let relation = try await db.addRelation(to: projects.id, target: books.id, twoWay: true)
        let pairedId = try #require(relation.relation?.pairedPropertyId)

        try await db.updateDataTable(projects.id) { table in
            table.properties.removeAll { $0.id == relation.id }
        }
        let paired = try #require(try await table(books.id).property(pairedId))
        #expect(paired.type == .relation)
        #expect(paired.relation?.pairedPropertyId == nil)
    }

    @Test func selfRelationTwoWay() async throws {
        let tasks = try await db.createDataTable(title: "Задачи")
        let relation = try await db.addRelation(to: tasks.id, target: tasks.id, twoWay: true)
        let pairedId = try #require(relation.relation?.pairedPropertyId)
        let names = try await table(tasks.id).properties.map(\.name)
        #expect(names.suffix(2) == ["Связанные", "Обратная связь"])

        let parent = try await db.addRow(to: tasks.id, title: "Глава")
        let child = try await db.addRow(to: tasks.id, title: "Параграф")
        try await db.setValue(.pages([child.id]), property: relation.id, row: parent.id)
        let rows = try await snapshot(tasks.pageId).rows
        #expect(rows.first { $0.id == child.id }?.value(pairedId) == .pages([parent.id]))
    }
}
