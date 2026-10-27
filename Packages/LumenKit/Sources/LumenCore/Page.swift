import Foundation

/// Страница: заметка, документ или (позже) строка базы данных. Страницы образуют дерево.
public struct Page: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var parentId: UUID?
    public var title: String
    /// Эмодзи или имя SF Symbol.
    public var icon: String?
    /// Источник (книга, файл), к которому привязана заметка. Появится на этапе 3.
    public var sourceId: UUID?
    /// Быстрые заметки лежат во «Входящих», пока их не разложат по разделам.
    public var inInbox: Bool
    public var isFavorite: Bool
    /// Дробный индекс порядка среди соседей, см. `SortKey`.
    public var sortKey: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Мягкое удаление: страница лежит в корзине.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        parentId: UUID? = nil,
        title: String = "",
        icon: String? = nil,
        sourceId: UUID? = nil,
        inInbox: Bool = false,
        isFavorite: Bool = false,
        sortKey: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.title = title
        self.icon = icon
        self.sourceId = sourceId
        self.inInbox = inInbox
        self.isFavorite = isFavorite
        self.sortKey = sortKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    public var isTrashed: Bool { deletedAt != nil }
}
