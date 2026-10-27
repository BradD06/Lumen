import Foundation
import GRDB
import LumenCore

/// Узел дерева страниц для сайдбара.
public struct PageNode: Identifiable, Hashable, Sendable {
    public var page: Page
    public var children: [PageNode]

    public var id: UUID { page.id }

    /// Для `OutlineGroup`: у листа нет стрелки раскрытия.
    public var childrenOrNil: [PageNode]? { children.isEmpty ? nil : children }
}

/// Страница с началом текста для списков.
public struct PagePreview: Identifiable, Hashable, Sendable {
    public var page: Page
    public var excerpt: String

    public var id: UUID { page.id }
}

/// Всё, что нужно сайдбару. Пересчитывается при любом изменении страниц.
public struct SidebarSnapshot: Equatable, Sendable {
    public var favorites: [Page]
    public var tree: [PageNode]
    public var inboxCount: Int
    public var trashCount: Int

    public static let empty = SidebarSnapshot(favorites: [], tree: [], inboxCount: 0, trashCount: 0)

    public static func fetch(_ db: Database) throws -> SidebarSnapshot {
        let alive = Page.filter(Column("deletedAt") == nil)
        let pages = try alive
            .filter(Column("inInbox") == false)
            .order(Column("sortKey"))
            .fetchAll(db)
        let favorites = try alive
            .filter(Column("isFavorite") == true)
            .order(Column("title"))
            .fetchAll(db)
        return SidebarSnapshot(
            favorites: favorites,
            tree: buildTree(pages),
            inboxCount: try alive.filter(Column("inInbox") == true).fetchCount(db),
            trashCount: try Page.filter(Column("deletedAt") != nil).fetchCount(db)
        )
    }

    static func buildTree(_ pages: [Page]) -> [PageNode] {
        let ids = Set(pages.map(\.id))
        let byParent = Dictionary(grouping: pages) { page -> UUID? in
            // Страница, чей родитель не попал в выборку, показывается на верхнем уровне.
            guard let parentId = page.parentId, ids.contains(parentId) else { return nil }
            return parentId
        }
        func nodes(under parentId: UUID?) -> [PageNode] {
            (byParent[parentId] ?? []).map { PageNode(page: $0, children: nodes(under: $0.id)) }
        }
        return nodes(under: nil)
    }
}

public enum InboxQuery {
    /// Страницы во «Входящих», новые сверху.
    public static func fetch(_ db: Database) throws -> [PagePreview] {
        try previews(db, sql: """
            SELECT page.*, pageSearch.body AS excerpt
            FROM page
            LEFT JOIN pageSearch ON pageSearch.pageId = \(uuidText("page.id"))
            WHERE page.inInbox = 1 AND page.deletedAt IS NULL
            ORDER BY page.createdAt DESC
            """)
    }
}

public enum TrashQuery {
    public static func fetch(_ db: Database) throws -> [Page] {
        try Page
            .filter(Column("deletedAt") != nil)
            .order(Column("deletedAt").desc)
            .fetchAll(db)
    }
}

/// Данные для главного экрана-дашборда.
public struct HomeSnapshot: Equatable, Sendable {
    public var inboxCount: Int
    public var pageCount: Int
    public var editedToday: Int
    public var recent: [PagePreview]

    public static let empty = HomeSnapshot(inboxCount: 0, pageCount: 0, editedToday: 0, recent: [])

    public static func fetch(_ db: Database, now: Date = Date(), calendar: Calendar = .current) throws -> HomeSnapshot {
        let alive = Page.filter(Column("deletedAt") == nil)
        let startOfDay = calendar.startOfDay(for: now)
        return HomeSnapshot(
            inboxCount: try alive.filter(Column("inInbox") == true).fetchCount(db),
            pageCount: try alive.fetchCount(db),
            editedToday: try alive.filter(Column("updatedAt") >= startOfDay).fetchCount(db),
            recent: try previews(db, sql: """
                SELECT page.*, pageSearch.body AS excerpt
                FROM page
                LEFT JOIN pageSearch ON pageSearch.pageId = \(uuidText("page.id"))
                WHERE page.deletedAt IS NULL
                ORDER BY page.updatedAt DESC
                LIMIT 6
                """)
        )
    }
}

private func previews(_ db: Database, sql: String) throws -> [PagePreview] {
    try Row.fetchAll(db, sql: sql).map { row in
        let body: String = row["excerpt"] ?? ""
        return PagePreview(page: try Page(row: row), excerpt: String(body.prefix(240)))
    }
}

/// SQL-выражение, которое превращает 16-байтовый UUID из колонки в строку того же вида,
/// что `UUID.uuidString` (так pageId хранится в поисковом индексе).
func uuidText(_ column: String) -> String {
    let hex = "upper(hex(\(column)))"
    return "substr(\(hex), 1, 8) || '-' || substr(\(hex), 9, 4) || '-' || substr(\(hex), 13, 4) || '-' || substr(\(hex), 17, 4) || '-' || substr(\(hex), 21, 12)"
}
