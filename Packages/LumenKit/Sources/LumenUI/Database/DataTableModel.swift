import Foundation
import GRDB
import LumenCore
import LumenStorage
import Observation

/// Состояние открытой базы данных: описание базы, строки и выбранное представление.
/// Источник правды в SQLite: каждая правка сразу пишется, а наблюдение возвращает свежие строки.
@MainActor
@Observable
final class DataTableModel {
    let database: AppDatabase
    let pageId: UUID

    private(set) var snapshot = DataTableSnapshot.empty
    private(set) var isLoaded = false
    /// Выбранное представление. `nil` значит первое.
    var selectedViewId: UUID?

    init(database: AppDatabase, pageId: UUID, initialViewId: UUID? = nil) {
        self.database = database
        self.pageId = pageId
        self.selectedViewId = initialViewId
    }

    var table: DataTable? { snapshot.table }
    var page: Page? { snapshot.page }
    var view: DataView? { table?.view(selectedViewId) }

    /// Строки выбранного представления: отфильтрованные и отсортированные.
    var visibleRows: [DataRow] {
        guard let table, let view else { return [] }
        return DataQuery.rows(snapshot.rows, in: table, view: view)
    }

    /// Колонки, которые показаны в выбранном представлении.
    var visibleProperties: [PropertyDefinition] {
        guard let table else { return [] }
        guard let view else { return table.properties }
        return table.properties.filter(view.shows)
    }

    /// Свойство-статус: по нему кружок в списке отмечает задачу выполненной.
    var statusProperty: PropertyDefinition? { table?.firstProperty(of: [.status]) }

    func observe() async {
        let pageId = pageId
        let observation = ValueObservation.tracking { db in try DataTableSnapshot.fetch(db, pageId: pageId) }
        do {
            for try await value in observation.values(in: database.reader) {
                snapshot = value
                isLoaded = true
            }
        } catch {
            lumenLog.error("Data table observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Страница базы

    func rename(_ title: String) {
        let pageId = pageId
        Task {
            await NoticeCenter.shared.attempt("Не удалось переименовать") {
                try await database.renamePage(pageId, title: title)
            }
        }
    }

    func setIcon(_ icon: String?) {
        let pageId = pageId
        Task {
            await NoticeCenter.shared.attempt("Не удалось сохранить оформление страницы") {
                try await database.setIcon(pageId, icon: icon)
            }
        }
    }

    // MARK: Строки

    /// Новая строка в выбранном представлении. Значения подбираются так, чтобы строка
    /// не исчезла из него сразу: в колонке доски её статус, в календаре её день.
    @discardableResult
    func addRow(title: String = "", group: DataGroup? = nil, day: DayDate? = nil) async -> Page? {
        guard let table, let view else { return nil }
        let values = DataQuery.presetValues(for: view, in: table, group: group, day: day)
        LumenSounds.play(.create)
        return try? await database.addRow(to: table.id, title: title, values: values)
    }

    func renameRow(_ rowId: UUID, _ title: String) {
        Task {
            await NoticeCenter.shared.attempt("Не удалось переименовать") {
                try await database.renamePage(rowId, title: title)
            }
        }
    }

    func setValue(_ value: PropertyValue?, property propertyId: UUID, row rowId: UUID) {
        Task {
            await NoticeCenter.shared.attempt("Не удалось сохранить значение") {
                try await database.setValue(value, property: propertyId, row: rowId)
            }
        }
    }

    /// Отмечает задачу выполненной или возвращает в работу.
    func toggleDone(_ row: DataRow) {
        guard let status = statusProperty else { return }
        let isDone = row.value(status.id)?.optionIds.contains { status.option($0)?.isDone == true } ?? false
        let next = isDone
            ? status.options.first(where: { !$0.isDone })
            : status.options.first(where: { $0.isDone })
        LumenSounds.play(.toggle)
        setValue(next.map { .option($0.id) }, property: status.id, row: row.id)
    }

    func trashRow(_ rowId: UUID) {
        NoticeCenter.shared.moveToTrash(.page(rowId), in: database)
    }

    func moveRow(_ rowId: UUID, after afterRowId: UUID?) {
        Task {
            await NoticeCenter.shared.attempt("Не удалось переместить строку") {
                try await database.moveRow(rowId, after: afterRowId)
            }
        }
    }

    // MARK: Описание базы

    func updateTable(_ change: @escaping @Sendable (inout DataTable) -> Void) {
        guard let id = table?.id else { return }
        Task { try? await database.updateDataTable(id, change) }
    }

    /// Меняет выбранное представление.
    func updateView(_ change: @escaping @Sendable (inout DataView) -> Void) {
        guard let viewId = view?.id else { return }
        updateTable { table in
            guard let index = table.views.firstIndex(where: { $0.id == viewId }) else { return }
            change(&table.views[index])
        }
    }

    func addView(_ layout: DataViewLayout) {
        guard let table else { return }
        var view = DataView(name: layout.title, layout: layout)
        view.groupBy = table.firstProperty(of: [.status, .select])?.id
        view.dateProperty = table.firstProperty(of: [.date])?.id
        let newView = view
        updateTable { $0.views.append(newView) }
        selectedViewId = newView.id
    }

    func duplicateView(_ viewId: UUID) {
        guard var copy = table?.views.first(where: { $0.id == viewId }) else { return }
        copy.id = UUID()
        copy.name += " (копия)"
        let newView = copy
        updateTable { table in
            let index = table.views.firstIndex { $0.id == viewId }.map { $0 + 1 } ?? table.views.endIndex
            table.views.insert(newView, at: index)
        }
        selectedViewId = newView.id
    }

    func deleteView(_ viewId: UUID) {
        guard let table, table.views.count > 1 else { return }
        if view?.id == viewId { selectedViewId = nil }
        updateTable { $0.views.removeAll { $0.id == viewId } }
    }

    func renameView(_ viewId: UUID, _ name: String) {
        updateTable { table in
            guard let index = table.views.firstIndex(where: { $0.id == viewId }) else { return }
            table.views[index].name = name
        }
    }

    func addProperty(_ type: PropertyType) {
        guard let table else { return }
        let property = PropertyDefinition(name: Self.uniqueName(type.title, among: table.properties.map(\.name)), type: type)
        updateTable { $0.properties.append(property) }
    }

    func updateProperty(_ propertyId: UUID, _ change: @escaping @Sendable (inout PropertyDefinition) -> Void) {
        updateTable { table in
            guard let index = table.properties.firstIndex(where: { $0.id == propertyId }) else { return }
            change(&table.properties[index])
        }
    }

    func deleteProperty(_ propertyId: UUID) {
        updateTable { $0.properties.removeAll { $0.id == propertyId } }
    }

    /// Новый вариант выбора. Цвета идут по кругу, чтобы соседние варианты различались.
    func addOption(to propertyId: UUID, name: String) -> SelectOption? {
        guard let property = table?.property(propertyId),
              let found = Self.option(named: name, in: property) else { return nil }
        if found.isNew {
            let option = found.option
            updateProperty(propertyId) { $0.options.append(option) }
        }
        return found.option
    }

    /// Вариант с таким именем: уже существующий или новый, который ещё нужно дописать в свойство.
    nonisolated static func option(named name: String, in property: PropertyDefinition) -> (option: SelectOption, isNew: Bool)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = property.options.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return (existing, false)
        }
        let colors = BlockColor.allCases
        return (SelectOption(name: trimmed, color: colors[(property.options.count + 3) % colors.count]), true)
    }

    static func uniqueName(_ base: String, among names: [String]) -> String {
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}
