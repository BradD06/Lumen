import Foundation
import Testing
@testable import LumenCore

struct DataQueryTests {
    let table: DataTable
    let status: PropertyDefinition
    let due: PropertyDefinition
    let priority: PropertyDefinition
    let project: PropertyDefinition
    let today = DayDate(year: 2026, month: 10, day: 31)

    init() {
        table = DataTableTemplate.tasks(pageId: UUID())
        status = table.properties[0]
        due = table.properties[1]
        priority = table.properties[2]
        project = table.properties[3]
    }

    private func row(_ title: String, key: String, _ values: [UUID: PropertyValue] = [:]) -> DataRow {
        DataRow(page: Page(title: title, databaseId: table.id, properties: PropertyValues(values), sortKey: key))
    }

    @Test func templateHasTasksShape() {
        #expect(table.properties.map(\.name) == ["Статус", "Срок", "Приоритет", "Проект", "Материал"])
        #expect(table.views.map(\.layout) == [.list, .board, .table, .calendar])
        #expect(status.options.filter(\.isDone).map(\.name) == ["Готово"])
        #expect(table.template == DataTableTemplate.tasksKey)
    }

    @Test func todayViewShowsOpenTasksDueTodayOrEarlier() {
        let todo = status.options[0].id
        let done = status.options[2].id
        let rows = [
            row("Просрочено", key: "a", [status.id: .option(todo), due.id: .date(today.adding(days: -2))]),
            row("Сегодня", key: "b", [status.id: .option(todo), due.id: .date(today)]),
            row("Завтра", key: "c", [status.id: .option(todo), due.id: .date(today.adding(days: 1))]),
            row("Готово сегодня", key: "d", [status.id: .option(done), due.id: .date(today)]),
            row("Без срока", key: "e", [status.id: .option(todo)]),
            row("Без статуса", key: "f", [due.id: .date(today)]),
        ]
        let view = table.views[0]
        let result = DataQuery.rows(rows, in: table, view: view, today: today)
        #expect(result.map(\.title) == ["Просрочено", "Сегодня", "Без статуса"])
    }

    @Test func sortsByOptionOrderWithEmptyLast() {
        let high = priority.options[0].id
        let low = priority.options[2].id
        let rows = [
            row("Низкий", key: "a", [priority.id: .option(low)]),
            row("Пусто", key: "b"),
            row("Высокий", key: "c", [priority.id: .option(high)]),
        ]
        let ascending = DataQuery.sorted(rows, by: [DataSort(propertyId: priority.id)], in: table)
        #expect(ascending.map(\.title) == ["Высокий", "Низкий", "Пусто"])
        let descending = DataQuery.sorted(rows, by: [DataSort(propertyId: priority.id, ascending: false)], in: table)
        #expect(descending.map(\.title) == ["Низкий", "Высокий", "Пусто"])
        let manual = DataQuery.sorted(rows, by: [], in: table)
        #expect(manual.map(\.title) == ["Низкий", "Пусто", "Высокий"])
    }

    @Test func textFiltersIgnoreCase() {
        let rows = [row("Глава 3", key: "a"), row("Конспект", key: "b")]
        let filter = DataFilter(propertyId: nil, op: .contains, value: .text("глава"))
        #expect(rows.filter { DataQuery.matches($0, filter, in: table) }.map(\.title) == ["Глава 3"])
        let empty = DataFilter(propertyId: nil, op: .isEmpty)
        #expect(rows.filter { DataQuery.matches($0, empty, in: table) }.isEmpty)
    }

    @Test func multiSelectContains() {
        let study = project.options[0].id
        let reading = project.options[1].id
        let rows = [
            row("Оба", key: "a", [project.id: .options([study, reading])]),
            row("Учёба", key: "b", [project.id: .options([study])]),
            row("Ничего", key: "c"),
        ]
        let filter = DataFilter(propertyId: project.id, op: .contains, value: .option(reading))
        #expect(rows.filter { DataQuery.matches($0, filter, in: table) }.map(\.title) == ["Оба"])
    }

    @Test func filterOnDeletedPropertyKeepsRows() {
        let filter = DataFilter(propertyId: UUID(), op: .isNotEmpty)
        #expect(DataQuery.matches(row("x", key: "a"), filter, in: table))
    }

    @Test func boardGroupsByStatusWithEmptyFirst() {
        let todo = status.options[0].id
        let doing = status.options[1].id
        let rows = [
            row("1", key: "a", [status.id: .option(doing)]),
            row("2", key: "b"),
            row("3", key: "c", [status.id: .option(todo)]),
        ]
        let groups = DataQuery.groups(rows, by: status.id, in: table)
        #expect(groups.map(\.title) == ["Без значения", "Не начато", "В работе", "Готово"])
        #expect(groups.map { $0.rows.map(\.title) } == [["2"], ["3"], ["1"], []])
        #expect(groups[2].value == .option(doing))
    }

    @Test func newRowInBoardColumnGetsItsValue() {
        let board = table.views[1]
        let groups = DataQuery.groups([], by: status.id, in: table)
        let doing = groups.first { $0.title == "В работе" }
        let values = DataQuery.presetValues(for: board, in: table, group: doing)
        #expect(values[status.id] == .option(status.options[1].id))
    }

    @Test func newRowInTodayViewIsDueTodayAndOpen() {
        let values = DataQuery.presetValues(for: table.views[0], in: table, today: today)
        #expect(values[due.id] == .date(today))
        #expect(values[status.id] == .option(status.options[0].id))
    }

    @Test func calendarBucketsByDay() {
        let rows = [
            row("a", key: "a", [due.id: .date(today)]),
            row("b", key: "b", [due.id: .date(today)]),
            row("c", key: "c"),
        ]
        let days = DataQuery.byDay(rows, dateProperty: due.id)
        #expect(days.count == 1)
        #expect(days[today]?.map(\.title) == ["a", "b"])
    }

    @Test func dayDateRoundTrips() throws {
        let data = try JSONEncoder().encode(PropertyValues([due.id: .date(today)]))
        let decoded = try JSONDecoder().decode(PropertyValues.self, from: data)
        #expect(decoded[due.id] == .date(today))
        #expect(today.description == "2026-10-31")
        #expect(DayDate(string: "2026-12-31")?.adding(days: 1) == DayDate(year: 2027, month: 1, day: 1))
    }

    @Test func emptyValuesAreNotStored() {
        var values = PropertyValues()
        values[due.id] = .text("  ")
        values[status.id] = .checkbox(false)
        #expect(values.isEmpty)
    }
}
