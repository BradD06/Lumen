import Foundation

/// Кнопка с доски связей. Самой доски в приложении больше нет, но таблица `boardPin`
/// (миграция v15) остаётся: старые данные не теряются, а синхронизация со старыми версиями
/// на других устройствах не ломается. Новых кнопок никто не создаёт.
/// `id` совпадает с id книги, папки или страницы, `x`, `y` это центр карточки.
public struct BoardPin: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: Kind
    public var x: Double
    public var y: Double
    public var createdAt: Date
    public var updatedAt: Date

    public enum Kind: String, Codable, Sendable {
        case page, source, folder
    }

    public init(item: LibraryItemID, at point: LibraryPoint, createdAt: Date = Date()) {
        switch item {
        case .page(let id): self.id = id; kind = .page
        case .source(let id): self.id = id; kind = .source
        case .folder(let id): self.id = id; kind = .folder
        }
        x = point.x
        y = point.y
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    public var item: LibraryItemID {
        switch kind {
        case .page: .page(id)
        case .source: .source(id)
        case .folder: .folder(id)
        }
    }

    public var point: LibraryPoint {
        get { LibraryPoint(x: x, y: y) }
        set {
            x = newValue.x
            y = newValue.y
        }
    }
}
