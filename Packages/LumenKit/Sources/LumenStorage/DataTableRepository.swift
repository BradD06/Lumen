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
    /// Строки баз, с которыми связана эта: для колонок «Связь» и «Сводка».
    public var relations: RelationContext
    /// Все базы: с какой можно связать новую колонку «Связь».
    public var databases: [DataTableChoice]

    public init(
        page: Page?,
        table: DataTable?,
        rows: [DataRow],
        linkablePages: [Page],
        relations: RelationContext = .empty,
        databases: [DataTableChoice] = []
    ) {
        self.page = page
        self.table = table
        self.rows = rows
        self.linkablePages = linkablePages
        self.relations = relations
        self.databases = databases
    }

    public static let empty = DataTableSnapshot(page: nil, table: nil, rows: [], linkablePages: [])

    /// Базу показывает страница `pageId`. Если у страницы базы нет, `table == nil`.
    public static func fetch(_ db: Database, pageId: UUID) throws -> DataTableSnapshot {
        let page = try Page.fetchOne(db, key: pageId)
        guard let table = try DataTable.filter(Column("pageId") == pageId).fetchOne(db) else {
            return DataTableSnapshot(page: page, table: nil, rows: [], linkablePages: [])
        }
        let rows = try liveRows(db, tableId: table.id)
        return DataTableSnapshot(
            page: page,
            table: table,
            rows: rows,
            linkablePages: try linkablePages(db),
            relations: try relationContext(db, for: table),
            databases: try DataTableChoice.fetchAll(db)
        )
    }

    static func liveRows(_ db: Database, tableId: UUID) throws -> [DataRow] {
        try Page
            .filter(Column("databaseId") == tableId && Column("deletedAt") == nil)
            .order(Column("sortKey"))
            .fetchAll(db)
            .map(DataRow.init(page:))
    }

    /// Связанные базы и их живые строки. Формулы связанных строк считаются сразу,
    /// чтобы сводка могла их сложить; сводки тех баз нет (сводка по сводке не считается).
    static func relationContext(_ db: Database, for table: DataTable) throws -> RelationContext {
        let targetIds = Set(table.properties.compactMap { $0.type == .relation ? $0.relation?.targetTableId : nil })
        guard !targetIds.isEmpty else { return .empty }
        var tables: [UUID: DataTable] = [:]
        var titles: [UUID: String] = [:]
        var rows: [UUID: [DataRow]] = [:]
        for id in targetIds {
            guard let target = try DataTable.fetchOne(db, key: id),
                  let page = try Page.fetchOne(db, key: target.pageId), page.deletedAt == nil else { continue }
            tables[id] = target
            titles[id] = page.displayTitle
            let live = try liveRows(db, tableId: id)
            rows[id] = Formula.computed(live, in: target)
        }
        return RelationContext(tables: tables, tableTitles: titles, rows: rows)
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
    public var relations: RelationContext = .empty

    public static let empty = DataRowSnapshot(row: nil, table: nil, linkablePages: [])

    public static func fetch(_ db: Database, rowId: UUID) throws -> DataRowSnapshot {
        guard let page = try Page.fetchOne(db, key: rowId), let tableId = page.databaseId,
              let table = try DataTable.fetchOne(db, key: tableId) else {
            return .empty
        }
        return DataRowSnapshot(
            row: DataRow(page: page),
            table: table,
            linkablePages: try DataTableSnapshot.linkablePages(db),
            relations: try DataTableSnapshot.relationContext(db, for: table)
        )
    }
}

/// База, с которой можно связать колонку: для выбора в настройке связи.
public struct DataTableChoice: Identifiable, Hashable, Sendable {
    /// Идентификатор базы (`DataTable.id`).
    public var id: UUID
    public var pageId: UUID
    public var title: String
    public var icon: String?

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    /// Все живые базы, задачи тоже, по названию.
    public static func fetchAll(_ db: Database) throws -> [DataTableChoice] {
        try Row.fetchAll(db, sql: """
            SELECT dataTable.id AS id, page.id AS pageId, page.title AS title, page.icon AS icon
            FROM dataTable
            JOIN page ON page.id = dataTable.pageId
            WHERE page.deletedAt IS NULL
            ORDER BY page.title COLLATE NOCASE
            """).map { row in
            DataTableChoice(id: row["id"], pageId: row["pageId"], title: (row["title"] as String?) ?? "", icon: row["icon"])
        }
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
        folderId: UUID? = nil,
        parentId: UUID? = nil
    ) async throws -> DataTable {
        try await writer.write { db in
            try Self.insertDataTable(db, title: title, kind: kind, icon: icon, folderId: folderId, parentId: parentId)
        }
    }

    /// `parentId`: база живёт подстраницей другой страницы (встроенная база в блоке «База данных»).
    static func insertDataTable(
        _ db: Database,
        title: String,
        kind: DataTableKind,
        icon: String?,
        folderId: UUID?,
        parentId: UUID? = nil
    ) throws -> DataTable {
        var page = try insertPage(db, title: title, parentId: parentId, inInbox: false, folderId: folderId, bodyLines: [])
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
        // Новая строка сразу со связью (добавлена в отфильтрованное по связи представление):
        // обратная колонка той базы тоже должна её увидеть.
        for property in table.properties where property.type == .relation {
            if let value = values[property.id] {
                try syncPairedRelation(db, rowId: page.id, table: table, propertyId: property.id, old: nil, new: value)
            }
        }
        return page
    }

    /// Задаёт одно значение. `nil` или пустое значение стирает его.
    /// У двусторонней связи заодно правится обратная колонка связанных строк.
    public func setValue(_ value: PropertyValue?, property propertyId: UUID, row rowId: UUID) async throws {
        try await writer.write { db in
            guard let page = try Page.fetchOne(db, key: rowId) else { throw StorageError.pageNotFound }
            let old = page.properties?[propertyId]
            var value = value
            if case .pages(let ids)? = value { value = DataRelation.normalized(ids) }
            let stored = value
            try Self.updatePage(db, rowId) { page in
                var values = page.properties ?? PropertyValues()
                values[propertyId] = stored
                page.properties = values.isEmpty ? nil : values
            }
            if let tableId = page.databaseId, let table = try DataTable.fetchOne(db, key: tableId) {
                try Self.syncPairedRelation(db, rowId: rowId, table: table, propertyId: propertyId, old: old, new: stored)
            }
        }
    }

    /// Двусторонняя связь: строки, которые добавили в связь, получают эту строку в обратной колонке,
    /// а убранные теряют её. Пишется прямо в строки, без повторной синхронизации.
    static func syncPairedRelation(_ db: Database, rowId: UUID, table: DataTable, propertyId: UUID, old: PropertyValue?, new: PropertyValue?) throws {
        guard let property = table.property(propertyId), property.type == .relation,
              let config = property.relation, let pairedId = config.pairedPropertyId else { return }
        let changes = DataRelation.changes(old: old, new: new)
        for (ids, adding) in [(changes.added, true), (changes.removed, false)] {
            for targetId in ids {
                guard var target = try Page.fetchOne(db, key: targetId), target.databaseId == config.targetTableId else { continue }
                var values = target.properties ?? PropertyValues()
                let updated = DataRelation.updating(values[pairedId], with: rowId, adding: adding)
                guard updated != values[pairedId] else { continue }
                values[pairedId] = updated
                target.properties = values.isEmpty ? nil : values
                target.updatedAt = Date()
                try target.update(db)
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
            try Self.unpairRemovedRelations(db, table: table, before: before)
        }
    }

    // MARK: Связи между базами

    /// Новая колонка «Связь» со строками базы `targetTableId`. С `twoWay` в той базе появляется
    /// обратная колонка, и обе всегда показывают одно и то же с двух сторон.
    @discardableResult
    public func addRelation(to tableId: UUID, target targetTableId: UUID, twoWay: Bool) async throws -> PropertyDefinition {
        try await writer.write { db in
            guard var table = try DataTable.fetchOne(db, key: tableId),
                  var target = try DataTable.fetchOne(db, key: targetTableId) else { throw StorageError.dataTableNotFound }
            let isSelf = tableId == targetTableId
            let targetTitle = try Self.tableTitle(db, target)
            let sourceTitle = try Self.tableTitle(db, table)
            var property = PropertyDefinition(
                name: Self.uniqueName(isSelf ? "Связанные" : targetTitle, among: table.properties.map(\.name)),
                type: .relation,
                relation: RelationConfig(targetTableId: targetTableId)
            )
            if twoWay {
                let pairedId = UUID()
                property.relation?.pairedPropertyId = pairedId
                let names = isSelf ? table.properties.map(\.name) + [property.name] : target.properties.map(\.name)
                let paired = PropertyDefinition(
                    id: pairedId,
                    name: Self.uniqueName(isSelf ? "Обратная связь" : sourceTitle, among: names),
                    type: .relation,
                    relation: RelationConfig(targetTableId: tableId, pairedPropertyId: property.id)
                )
                if isSelf {
                    table.properties.append(contentsOf: [property, paired])
                } else {
                    table.properties.append(property)
                    target.properties.append(paired)
                    target.updatedAt = Date()
                    try target.update(db)
                }
            } else {
                table.properties.append(property)
            }
            table.updatedAt = Date()
            try table.update(db)
            return property
        }
    }

    /// Включает или выключает обратную колонку у связи. Включённая сразу заполняется
    /// по уже связанным строкам; выключенная удаляется из той базы вместе со значениями.
    public func setRelationTwoWay(_ isOn: Bool, table tableId: UUID, property propertyId: UUID) async throws {
        try await writer.write { db in
            guard var table = try DataTable.fetchOne(db, key: tableId),
                  let index = table.properties.firstIndex(where: { $0.id == propertyId }),
                  let config = table.properties[index].relation else { throw StorageError.dataTableNotFound }
            guard config.isTwoWay != isOn else { return }
            let targetTableId = config.targetTableId
            let isSelf = targetTableId == tableId

            if isOn {
                let pairedId = UUID()
                table.properties[index].relation?.pairedPropertyId = pairedId
                let sourceTitle = try Self.tableTitle(db, table)
                func paired(among names: [String]) -> PropertyDefinition {
                    PropertyDefinition(
                        id: pairedId,
                        name: Self.uniqueName(isSelf ? "Обратная связь" : sourceTitle, among: names),
                        type: .relation,
                        relation: RelationConfig(targetTableId: tableId, pairedPropertyId: propertyId)
                    )
                }
                if isSelf {
                    table.properties.append(paired(among: table.properties.map(\.name)))
                } else {
                    guard var target = try DataTable.fetchOne(db, key: targetTableId) else { throw StorageError.dataTableNotFound }
                    target.properties.append(paired(among: target.properties.map(\.name)))
                    target.updatedAt = Date()
                    try target.update(db)
                }
                table.updatedAt = Date()
                try table.update(db)
                // Уже связанные строки сразу появляются в новой колонке.
                for row in try DataTableSnapshot.liveRows(db, tableId: tableId) {
                    if let value = row.value(propertyId) {
                        try Self.syncPairedRelation(db, rowId: row.id, table: table, propertyId: propertyId, old: nil, new: value)
                    }
                }
            } else {
                guard let pairedId = config.pairedPropertyId else { return }
                table.properties[index].relation?.pairedPropertyId = nil
                if isSelf {
                    let before = table
                    table.properties.removeAll { $0.id == pairedId }
                    table.updatedAt = Date()
                    try table.update(db)
                    try Self.cleanRows(db, table: table, before: before)
                } else {
                    table.updatedAt = Date()
                    try table.update(db)
                    if var target = try DataTable.fetchOne(db, key: targetTableId) {
                        let before = target
                        target.properties.removeAll { $0.id == pairedId }
                        target.updatedAt = Date()
                        try target.update(db)
                        try Self.cleanRows(db, table: target, before: before)
                    }
                }
            }
        }
    }

    /// Связь удалили или сменили ей тип: обратная колонка в той базе остаётся, но уже односторонней,
    /// иначе она ждала бы пару, которой нет.
    static func unpairRemovedRelations(_ db: Database, table: DataTable, before: DataTable) throws {
        for old in before.properties where old.type == .relation {
            guard let config = old.relation, let pairedId = config.pairedPropertyId else { continue }
            let current = table.property(old.id)
            if current?.type == .relation, current?.relation?.pairedPropertyId == pairedId { continue }
            guard var other = try DataTable.fetchOne(db, key: config.targetTableId),
                  let index = other.properties.firstIndex(where: { $0.id == pairedId }),
                  other.properties[index].relation?.pairedPropertyId == old.id else { continue }
            other.properties[index].relation?.pairedPropertyId = nil
            other.updatedAt = Date()
            try other.update(db)
        }
    }

    static func tableTitle(_ db: Database, _ table: DataTable) throws -> String {
        try Page.fetchOne(db, key: table.pageId)?.displayTitle ?? "База"
    }

    static func uniqueName(_ base: String, among names: [String]) -> String {
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
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
