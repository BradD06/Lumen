import Foundation
import GRDB
import LumenCore

/// База данных с её страницей и строками: всё, что нужно экрану базы.
public struct DataTableSnapshot: Equatable, Sendable {
    public var page: Page?
    public var table: DataTable?
    /// Живые строки в ручном порядке. Фильтры и сортировки представления применяет `DataQuery`.
    public var rows: [DataRow]
    /// Живые страницы, не строки: для свойства «Ссылка на страницу».
    public var linkablePages: [Page]

    public static let empty = DataTableSnapshot(page: nil, table: nil, rows: [], linkablePages: [])

    /// Базу показывает страница `pageId`. Если у страницы базы нет, `table == nil`.
    public static func fetch(_ db: Database, pageId: UUID) throws -> DataTableSnapshot {
        let page = try Page.fetchOne(db, key: pageId)
        guard let table = try DataTable.filter(Column("pageId") == pageId).fetchOne(db) else {
            return DataTableSnapshot(page: page, table: nil, rows: [], linkablePages: [])
        }
        let rows = try Page
            .filter(Column("databaseId") == table.id && Column("deletedAt") == nil)
            .order(Column("sortKey"))
            .fetchAll(db)
            .map(DataRow.init(page:))
        return DataTableSnapshot(page: page, table: table, rows: rows, linkablePages: try linkablePages(db))
    }

    static func linkablePages(_ db: Database) throws -> [Page] {
        try Page
            .filter(Column("deletedAt") == nil && Column("databaseId") == nil)
            .order(Column("title").collating(.localizedCaseInsensitiveCompare))
            .fetchAll(db)
    }
}

/// Строка базы, открытая как страница: её база и значения для панели свойств над текстом.
public struct DataRowSnapshot: Equatable, Sendable {
    public var row: DataRow?
    public var table: DataTable?
    public var linkablePages: [Page]

    public static let empty = DataRowSnapshot(row: nil, table: nil, linkablePages: [])

    public static func fetch(_ db: Database, rowId: UUID) throws -> DataRowSnapshot {
        guard let page = try Page.fetchOne(db, key: rowId), let tableId = page.databaseId,
              let table = try DataTable.fetchOne(db, key: tableId) else {
            return .empty
        }
        return DataRowSnapshot(
            row: DataRow(page: page),
            table: table,
            linkablePages: try DataTableSnapshot.linkablePages(db)
        )
    }
}

/// Базы данных для сайдбара: страницы, на которых они живут. Задачи в сайдбаре отдельным пунктом,
/// поэтому их здесь нет.
public enum DataTableListQuery {
    public static func fetch(_ db: Database) throws -> [Page] {
        try Page.fetchAll(db, sql: """
            SELECT page.*
            FROM dataTable
            JOIN page ON page.id = dataTable.pageId
            WHERE page.deletedAt IS NULL AND dataTable.template IS NOT ?
            ORDER BY page.title COLLATE NOCASE
            """, arguments: [DataTableTemplate.tasksKey])
    }
}

public enum DataTableKind: Sendable {
    case blank
    case tasks
}

extension AppDatabase {
    // MARK: Создание

    /// Новая страница с базой данных. Для задач сразу несколько примеров, чтобы было видно, как это работает.
    @discardableResult
    public func createDataTable(
        title: String,
        kind: DataTableKind = .blank,
        icon: String? = nil,
        folderId: UUID? = nil
    ) async throws -> DataTable {
        try await writer.write { db in
            try Self.insertDataTable(db, title: title, kind: kind, icon: icon, folderId: folderId)
        }
    }

    static func insertDataTable(_ db: Database, title: String, kind: DataTableKind, icon: String?, folderId: UUID?) throws -> DataTable {
        var page = try insertPage(db, title: title, parentId: nil, inInbox: false, folderId: folderId, bodyLines: [])
        page.icon = icon
        try page.update(db)
        let table: DataTable
        switch kind {
        case .blank:
            table = DataTableTemplate.blank(pageId: page.id)
        case .tasks:
            table = DataTableTemplate.tasks(pageId: page.id)
        }
        try table.insert(db)
        if kind == .tasks {
            try insertTaskExamples(db, table: table)
        }
        return table
    }

    private static func insertTaskExamples(_ db: Database, table: DataTable) throws {
        guard let status = table.firstProperty(of: [.status]),
              let due = table.firstProperty(of: [.date]),
              let priority = table.property(table.properties.first { $0.name == "Приоритет" }?.id),
              let project = table.firstProperty(of: [.multiSelect]) else { return }
        let today = DayDate.today()
        let examples: [(String, Int, Int?, Int, Int)] = [
            ("Прочитать главу 3", 0, 0, 0, 1),
            ("Сделать конспект лекции", 1, 1, 1, 0),
            ("Повторить формулы к экзамену", 0, 3, 0, 0),
            ("Разобрать входящие заметки", 2, -1, 2, 2),
        ]
        for (title, statusIndex, dueDays, priorityIndex, projectIndex) in examples {
            var values = PropertyValues()
            values[status.id] = .option(status.options[statusIndex].id)
            if let dueDays { values[due.id] = .date(today.adding(days: dueDays)) }
            values[priority.id] = .option(priority.options[priorityIndex].id)
            values[project.id] = .options([project.options[projectIndex].id])
            _ = try insertRow(db, table: table, title: title, values: values)
        }
    }

    /// База «Задачи». Создаётся при первом обращении.
    @discardableResult
    public func tasksDataTable() async throws -> DataTable {
        try await writer.write { db in
            if let existing = try DataTable.fetchOne(db, sql: """
                SELECT dataTable.*
                FROM dataTable
                JOIN page ON page.id = dataTable.pageId
                WHERE dataTable.template = ? AND page.deletedAt IS NULL
                ORDER BY dataTable.createdAt
                LIMIT 1
                """, arguments: [DataTableTemplate.tasksKey]) {
                return existing
            }
            return try Self.insertDataTable(db, title: "Задачи", kind: .tasks, icon: "✅", folderId: nil)
        }
    }

    // MARK: Чтение

    public func dataTable(onPage pageId: UUID) async throws -> DataTable? {
        try await reader.read { db in
            try DataTable.filter(Column("pageId") == pageId).fetchOne(db)
        }
    }

    public func dataTable(_ id: UUID) async throws -> DataTable? {
        try await reader.read { db in try DataTable.fetchOne(db, key: id) }
    }

    // MARK: Строки

    /// Новая строка в конце базы (или после `afterRowId`) со значениями `values`.
    @discardableResult
    public func addRow(to tableId: UUID, title: String = "", values: PropertyValues = PropertyValues(), after afterRowId: UUID? = nil) async throws -> Page {
        try await writer.write { db in
            guard let table = try DataTable.fetchOne(db, key: tableId) else { throw StorageError.dataTableNotFound }
            var row = try Self.insertRow(db, table: table, title: title, values: values)
            if let afterRowId {
                row.sortKey = try Self.rowSortKey(db, table: table, after: afterRowId, excluding: row.id)
                try row.update(db)
            }
            return row
        }
    }

    static func insertRow(_ db: Database, table: DataTable, title: String, values: PropertyValues) throws -> Page {
        var page = try insertPage(db, title: title, parentId: table.pageId, inInbox: false, bodyLines: [])
        page.databaseId = table.id
        page.properties = values.isEmpty ? nil : values
        try page.update(db)
        return page
    }

    /// Задаёт одно значение. `nil` или пустое значение стирает его.
    public func setValue(_ value: PropertyValue?, property propertyId: UUID, row rowId: UUID) async throws {
        try await writer.write { db in
            try Self.updatePage(db, rowId) { page in
                var values = page.properties ?? PropertyValues()
                values[propertyId] = value
                page.properties = values.isEmpty ? nil : values
            }
        }
    }

    /// Переставляет строку в ручном порядке: сразу после `afterRowId` (`nil` значит в начало).
    public func moveRow(_ rowId: UUID, after afterRowId: UUID?) async throws {
        try await writer.write { db in
            guard let page = try Page.fetchOne(db, key: rowId), let tableId = page.databaseId,
                  let table = try DataTable.fetchOne(db, key: tableId) else { throw StorageError.pageNotFound }
            let key = try Self.rowSortKey(db, table: table, after: afterRowId, excluding: rowId)
            try Self.updatePage(db, rowId) { $0.sortKey = key }
        }
    }

    private static func rowSortKey(_ db: Database, table: DataTable, after afterRowId: UUID?, excluding excluded: UUID) throws -> String {
        let keys = try String.fetchAll(db, sql: """
            SELECT sortKey FROM page WHERE databaseId = ? AND id != ? ORDER BY sortKey
            """, arguments: [table.id, excluded])
        let afterKey = try afterRowId.flatMap { id in
            try String.fetchOne(db, sql: "SELECT sortKey FROM page WHERE id = ?", arguments: [id])
        }
        let upper = keys.first { key in afterKey.map { key > $0 } ?? true }
        return SortKey.between(afterKey, upper)
    }

    // MARK: Свойства и представления

    /// Меняет описание базы: свойства, варианты, представления.
    public func updateDataTable(_ id: UUID, _ change: @escaping @Sendable (inout DataTable) -> Void) async throws {
        try await writer.write { db in
            guard var table = try DataTable.fetchOne(db, key: id) else { throw StorageError.dataTableNotFound }
            let before = table
            change(&table)
            table.updatedAt = Date()
            try table.update(db)
            try Self.cleanRows(db, table: table, before: before)
        }
    }

    /// Новое свойство в конце. Возвращает его, чтобы экран мог сразу открыть настройку.
    @discardableResult
    public func addProperty(to tableId: UUID, name: String, type: PropertyType) async throws -> PropertyDefinition {
        let property = PropertyDefinition(name: name, type: type)
        try await updateDataTable(tableId) { $0.properties.append(property) }
        return property
    }

    /// Убирает из строк значения свойств и вариантов, которых больше нет, а из представлений
    /// фильтры, сортировки и группировки по ним. Тип свойства сменили: старые значения тоже уходят.
    static func cleanRows(_ db: Database, table: DataTable, before: DataTable) throws {
        var removed = Set<UUID>()
        var removedOptions: [UUID: Set<UUID>] = [:]
        for old in before.properties {
            guard let new = table.property(old.id), new.type == old.type else {
                removed.insert(old.id)
                continue
            }
            let gone = Set(old.options.map(\.id)).subtracting(new.options.map(\.id))
            if !gone.isEmpty { removedOptions[old.id] = gone }
        }
        guard !removed.isEmpty || !removedOptions.isEmpty else { return }

        let rows = try Page.filter(Column("databaseId") == table.id).fetchAll(db)
        for var row in rows {
            guard var values = row.properties else { continue }
            let original = values
            for id in removed { values[id] = nil }
            for (propertyId, options) in removedOptions {
                switch values[propertyId] {
                case .option(let id)? where options.contains(id):
                    values[propertyId] = nil
                case .options(let ids)?:
                    values[propertyId] = .options(ids.filter { !options.contains($0) })
                default:
                    break
                }
            }
            if values != original {
                row.properties = values.isEmpty ? nil : values
                row.updatedAt = Date()
                try row.update(db)
            }
        }

        // Удалённые свойства не должны висеть в настройках представлений.
        if !removed.isEmpty {
            var cleaned = table
            for index in cleaned.views.indices {
                cleaned.views[index].filters.removeAll { $0.propertyId.map(removed.contains) ?? false }
                cleaned.views[index].sorts.removeAll { $0.propertyId.map(removed.contains) ?? false }
                cleaned.views[index].hiddenProperties.removeAll { removed.contains($0) }
                if let group = cleaned.views[index].groupBy, removed.contains(group) {
                    cleaned.views[index].groupBy = nil
                }
                if let date = cleaned.views[index].dateProperty, removed.contains(date) {
                    cleaned.views[index].dateProperty = nil
                }
            }
            if cleaned != table {
                try cleaned.update(db)
            }
        }
    }
}
