import Foundation
import Testing
@testable import LumenCore

/// Связи между базами и сводки: проекты и их задачи.
struct DataRelationTests {
    let tasks: DataTable
    let status: PropertyDefinition
    let hours: PropertyDefinition
    let projects: DataTable
    let relation: PropertyDefinition

    init() {
        var tasks = DataTableTemplate.tasks(pageId: UUID())
        hours = PropertyDefinition(name: "Часы", type: .number)
        tasks.properties.append(hours)
        self.tasks = tasks
        status = tasks.properties[0]
        var projects = DataTableTemplate.blank(pageId: UUID())
        relation = PropertyDefinition(name: "Задачи", type: .relation, relation: RelationConfig(targetTableId: tasks.id))
        projects.properties.append(relation)
        self.projects = projects
    }

    private func task(_ title: String, done: Bool, hours value: Double?) -> DataRow {
        var values: [UUID: PropertyValue] = [status.id: .option(status.options[done ? 2 : 0].id)]
        if let value { values[hours.id] = .number(value) }
        return DataRow(page: Page(title: title, databaseId: tasks.id, properties: PropertyValues(values), sortKey: title))
    }

    private func project(_ title: String, _ ids: [UUID]) -> DataRow {
        DataRow(page: Page(title: title, databaseId: projects.id, properties: PropertyValues([relation.id: .pages(ids)]), sortKey: "a"))
    }

    private func rollup(_ function: RollupFunction, target: UUID?) -> PropertyDefinition {
        PropertyDefinition(name: "Сводка", type: .rollup, rollup: RollupConfig(relationPropertyId: relation.id, targetPropertyId: target, function: function))
    }

    @Test func rollupsCountSumAndPercentDone() {
        let a = task("Глава 1", done: true, hours: 2)
        let b = task("Глава 2", done: false, hours: 3.5)
        let c = task("Глава 3", done: true, hours: nil)
        let context = RelationContext(tables: [tasks.id: tasks], tableTitles: [tasks.id: "Задачи"], rows: [tasks.id: [a, b, c]])
        let row = project("Диплом", [a.id, b.id, c.id])

        func value(_ function: RollupFunction, _ target: UUID?) -> PropertyValue? {
            Rollup.value(of: rollup(function, target: target), row: row, table: projects, relations: context)
        }
        #expect(value(.count, nil) == .number(3))
        #expect(value(.sum, hours.id) == .number(5.5))
        #expect(value(.average, hours.id) == .number(2.75))
        #expect(value(.countValues, hours.id) == .number(2))
        #expect(value(.countDone, status.id) == .number(2))
        #expect(value(.percentDone, status.id) == .number(66.7))
        #expect(value(.showOriginal, nil) == .text("Глава 1, Глава 2, Глава 3"))
        #expect(value(.showOriginal, status.id) == .text("Готово, Не начато, Готово"))
        #expect(value(.countUnique, status.id) == .number(2))
    }

    @Test func trashedAndForeignRowsAreSkipped() {
        let a = task("Есть", done: false, hours: 1)
        let gone = UUID()
        let stranger = DataRow(page: Page(title: "Чужая", databaseId: UUID(), sortKey: "z"))
        let context = RelationContext(tables: [tasks.id: tasks], rows: [tasks.id: [a], UUID(): [stranger]])
        let row = project("П", [a.id, gone, stranger.id, a.id])
        #expect(Rollup.value(of: rollup(.count, target: nil), row: row, table: projects, relations: context) == .number(1))
    }

    @Test func formulaSeesRollupAndRelationCount() {
        let a = task("A", done: true, hours: 4)
        let b = task("B", done: false, hours: 6)
        let total = rollup(.sum, target: hours.id)
        var table = projects
        table.properties.append(total)
        table.properties.append(PropertyDefinition(name: "Итог", type: .formula, formula: "{Сводка} / {Задачи}"))
        let context = RelationContext(tables: [tasks.id: tasks], rows: [tasks.id: [a, b]])
        let view = DataView(name: "Все", layout: .table)
        let rows = DataQuery.rows([project("П", [a.id, b.id])], in: table, view: view, relations: context)
        #expect(rows.first?.value(table.properties.last!.id) == .number(5))
    }

    @Test func relationFilterContainsRow() {
        let a = task("A", done: false, hours: nil)
        let b = task("B", done: false, hours: nil)
        let first = project("С A", [a.id])
        let second = project("С B", [b.id])
        let view = DataView(name: "A", layout: .table, filters: [DataFilter(propertyId: relation.id, op: .contains, value: .page(a.id))])
        let rows = DataQuery.rows([first, second], in: projects, view: view)
        #expect(rows.map(\.title) == ["С A"])
        // Новая строка в этом представлении сразу связана с A.
        #expect(DataQuery.presetValues(for: view, in: projects)[relation.id] == .pages([a.id]))
    }

    @Test func pairedChangesAndUpdates() {
        let a = UUID(), b = UUID(), c = UUID()
        let changes = DataRelation.changes(old: .pages([a, b]), new: .pages([b, c, c]))
        #expect(changes.added == [c])
        #expect(changes.removed == [a])

        let row = UUID()
        #expect(DataRelation.updating(nil, with: row, adding: true) == .pages([row]))
        #expect(DataRelation.updating(.pages([a, row]), with: row, adding: true) == .pages([a, row]))
        #expect(DataRelation.updating(.pages([row]), with: row, adding: false) == nil)
        #expect(DataRelation.normalized([a, a, b]) == .pages([a, b]))
    }

    @Test func oldTablesWithoutRelationFieldsStillDecode() throws {
        let json = #"{"id":"6F0D5F7B-5E36-4D8F-9E33-6B8C6D1B2A10","name":"Заметка","type":"text","options":[]}"#
        let property = try JSONDecoder().decode(PropertyDefinition.self, from: Data(json.utf8))
        #expect(property.relation == nil && property.rollup == nil)

        var values = PropertyValues()
        let id = UUID()
        values[id] = .pages([UUID()])
        let decoded = try JSONDecoder().decode(PropertyValues.self, from: JSONEncoder().encode(values))
        #expect(decoded == values)
        values[id] = .pages([])
        #expect(values.isEmpty)
    }
}
