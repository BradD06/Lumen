import Foundation
import GRDB
import LumenCore

/// Узел дерева папок для сайдбара и окна «Переместить в…».
public struct FolderNode: Identifiable, Hashable, Sendable {
    public var folder: Folder
    public var children: [FolderNode]

    public var id: UUID { folder.id }

    /// Для `OutlineGroup`: у папки без вложенных папок нет стрелки раскрытия.
    public var childrenOrNil: [FolderNode]? { children.isEmpty ? nil : children }

    /// Все папки этого узла и его потомков подряд.
    public var flattened: [Folder] { [folder] + children.flatMap(\.flattened) }
}

/// Страница с началом текста для списков.
public struct PagePreview: Identifiable, Hashable, Sendable {
    public var page: Page
    public var excerpt: String

    public var id: UUID { page.id }
}

/// Всё, что нужно сайдбару. Пересчитывается при любом изменении страниц и папок.
public struct SidebarSnapshot: Equatable, Sendable {
    public var favorites: [Page]
    /// Страницы баз данных, кроме задач: у них свой пункт.
    public var databases: [Page]
    public var folders: [FolderNode]
    public var inboxCount: Int
    public var trashCount: Int
    /// Что открывали и правили последним: страницы и книги вперемешку.
    public var recent: [RecentItem] = []

    public static let empty = SidebarSnapshot(favorites: [], databases: [], folders: [], inboxCount: 0, trashCount: 0)

    public static func fetch(_ db: Database) throws -> SidebarSnapshot {
        let alive = Page.filter(Column("deletedAt") == nil)
        let favorites = try alive
            .filter(Column("isFavorite") == true)
            .order(Column("title"))
            .fetchAll(db)
        let trashedPages = try Page.filter(Column("deletedAt") != nil).fetchCount(db)
        let trashedFolders = try Folder.filter(Column("deletedAt") != nil).fetchCount(db)
        let trashedSources = try Source.filter(Column("deletedAt") != nil).fetchCount(db)
        return SidebarSnapshot(
            favorites: favorites,
            databases: try DataTableListQuery.fetch(db),
            folders: try FolderTreeQuery.fetch(db),
            inboxCount: try alive.filter(Column("inInbox") == true).fetchCount(db),
            trashCount: trashedPages + trashedFolders + trashedSources,
            recent: try RecentQuery.fetch(db, limit: 5)
        )
    }
}

/// Недавнее: страница или книга.
public enum RecentItem: Hashable, Identifiable, Sendable {
    case page(Page)
    case source(Source)

    public var id: UUID {
        switch self {
        case .page(let page): page.id
        case .source(let source): source.id
        }
    }

    public var title: String {
        switch self {
        case .page(let page): page.displayTitle
        case .source(let source): source.displayTitle
        }
    }

    /// Когда с ним работали последний раз.
    public var date: Date {
        switch self {
        case .page(let page): page.updatedAt
        case .source(let source): source.lastOpenedAt ?? source.createdAt
        }
    }
}

public enum RecentQuery {
    /// Последние правленые страницы (без строк баз) и последние открытые книги, новые сверху.
    public static func fetch(_ db: Database, limit: Int) throws -> [RecentItem] {
        let pages = try Page
            .filter(Column("deletedAt") == nil && Column("databaseId") == nil)
            .order(Column("updatedAt").desc)
            .limit(limit)
            .fetchAll(db)
        let sources = try Source
            .filter(Column("deletedAt") == nil && Column("lastOpenedAt") != nil)
            .order(Column("lastOpenedAt").desc)
            .limit(limit)
            .fetchAll(db)
        let items = pages.map(RecentItem.page) + sources.map(RecentItem.source)
        return Array(items.sorted { $0.date > $1.date }.prefix(limit))
    }
}

/// Папки, куда скорее всего положат заметку из «Входящих»: в которых недавно что-то правили.
public enum SuggestedFoldersQuery {
    public static func fetch(_ db: Database, limit: Int = 3) throws -> [Folder] {
        let busy = try Folder.fetchAll(db, sql: """
            SELECT folder.*
            FROM folder
            JOIN page ON page.folderId = folder.id
            WHERE folder.deletedAt IS NULL AND page.deletedAt IS NULL
            GROUP BY folder.id
            ORDER BY MAX(page.updatedAt) DESC
            LIMIT ?
            """, arguments: [limit])
        guard busy.count < limit else { return busy }
        let taken = Set(busy.map(\.id))
        let rest = try Folder
            .filter(Column("deletedAt") == nil)
            .order(Column("updatedAt").desc)
            .fetchAll(db)
            .filter { !taken.contains($0.id) }
        return busy + rest.prefix(limit - busy.count)
    }
}

/// Шаг пути к странице: «Входящие», папка библиотеки или страница-родитель.
public enum Breadcrumb: Hashable, Identifiable, Sendable {
    case inbox
    case library
    case folder(Folder)
    case page(Page)

    public var id: String {
        switch self {
        case .inbox: "inbox"
        case .library: "library"
        case .folder(let folder): "folder-\(folder.id)"
        case .page(let page): "page-\(page.id)"
        }
    }

    public var title: String {
        switch self {
        case .inbox: "Входящие"
        case .library: "Библиотека"
        case .folder(let folder): folder.displayName
        case .page(let page): page.displayTitle
        }
    }
}

public enum BreadcrumbQuery {
    /// Путь от корня до страницы, без самой страницы. Строка базы идёт после страницы базы.
    public static func fetch(_ db: Database, pageId: UUID) throws -> [Breadcrumb] {
        guard var page = try Page.fetchOne(db, key: pageId) else { return [] }
        var pages: [Page] = []
        var seen: Set<UUID> = [pageId]
        // Вверх по родителям: подстраница, строка базы (её родитель это страница базы).
        while true {
            var parent: Page?
            if let parentId = page.parentId {
                parent = try Page.fetchOne(db, key: parentId)
            } else if let databaseId = page.databaseId {
                parent = try Page.fetchOne(db, sql: """
                    SELECT page.* FROM page JOIN dataTable ON dataTable.pageId = page.id WHERE dataTable.id = ?
                    """, arguments: [databaseId])
            }
            guard let next = parent, next.deletedAt == nil, !seen.contains(next.id) else { break }
            seen.insert(next.id)
            pages.insert(next, at: 0)
            page = next
        }
        // Самая верхняя страница лежит во «Входящих» или в папке.
        if page.inInbox {
            return [.inbox] + pages.map(Breadcrumb.page)
        }
        var folders: [Folder] = []
        var folderId = page.folderId
        var seenFolders: Set<UUID> = []
        while let id = folderId, !seenFolders.contains(id), let folder = try Folder.fetchOne(db, key: id), folder.deletedAt == nil {
            seenFolders.insert(id)
            folders.insert(folder, at: 0)
            folderId = folder.parentId
        }
        return [.library] + folders.map(Breadcrumb.folder) + pages.map(Breadcrumb.page)
    }
}

public enum FolderTreeQuery {
    /// Живые папки деревом, по названию.
    public static func fetch(_ db: Database) throws -> [FolderNode] {
        let folders = try Folder
            .filter(Column("deletedAt") == nil)
            .order(Column("name").collating(.localizedCaseInsensitiveCompare))
            .fetchAll(db)
        let ids = Set(folders.map(\.id))
        let byParent = Dictionary(grouping: folders) { folder -> UUID? in
            // Папка, чей родитель в корзине, показывается в корне.
            guard let parentId = folder.parentId, ids.contains(parentId) else { return nil }
            return parentId
        }
        func nodes(under parentId: UUID?) -> [FolderNode] {
            (byParent[parentId] ?? []).map { FolderNode(folder: $0, children: nodes(under: $0.id)) }
        }
        return nodes(under: nil)
    }
}

/// Папка на холсте библиотеки и сколько в ней лежит.
public struct LibraryFolder: Identifiable, Hashable, Sendable {
    public var folder: Folder
    public var itemCount: Int

    public var id: UUID { folder.id }
}

/// Страница на холсте библиотеки. Подстраницы показываются в её меню.
public struct LibraryPage: Identifiable, Hashable, Sendable {
    public var preview: PagePreview
    public var subpages: [Page]

    public var page: Page { preview.page }
    public var id: UUID { preview.page.id }
}

/// Книга или файл на холсте библиотеки.
public struct LibrarySource: Identifiable, Hashable, Sendable {
    public var source: Source
    public var highlightCount: Int

    public var id: UUID { source.id }
}

/// Содержимое одной папки библиотеки (`folder == nil` это корень).
public struct LibrarySnapshot: Equatable, Sendable {
    public var folder: Folder?
    /// Папки от корня до открытой, без неё самой: для «хлебных крошек».
    public var path: [Folder]
    public var folders: [LibraryFolder]
    public var pages: [LibraryPage]
    public var sources: [LibrarySource]
    /// Открытую папку удалили, пока она была на экране.
    public var isMissing: Bool

    public static let empty = LibrarySnapshot(folder: nil, path: [], folders: [], pages: [], sources: [], isMissing: false)

    public static func fetch(_ db: Database, folderId: UUID?) throws -> LibrarySnapshot {
        var folder: Folder?
        var path: [Folder] = []
        if let folderId {
            guard let found = try Folder.fetchOne(db, key: folderId), !found.isTrashed else {
                return LibrarySnapshot(folder: nil, path: [], folders: [], pages: [], sources: [], isMissing: true)
            }
            folder = found
            var parentId = found.parentId
            while let id = parentId, let parent = try Folder.fetchOne(db, key: id), !path.contains(parent) {
                path.insert(parent, at: 0)
                parentId = parent.parentId
            }
        }

        let folders = try Folder
            .filter(Column("parentId") == folderId)
            .filter(Column("deletedAt") == nil)
            .order(Column("createdAt"))
            .fetchAll(db)
            .map { LibraryFolder(folder: $0, itemCount: try itemCount(db, in: $0.id)) }

        let pages = try previews(db, sql: """
            SELECT page.*, pageSearch.body AS excerpt
            FROM page
            LEFT JOIN pageSearch ON pageSearch.pageId = \(uuidText("page.id"))
            WHERE page.folderId IS ? AND page.parentId IS NULL AND page.inInbox = 0 AND page.deletedAt IS NULL
            ORDER BY page.sortKey
            """, arguments: [folderId])
            .map { preview in
                LibraryPage(
                    preview: preview,
                    subpages: try Page
                        .filter(Column("parentId") == preview.page.id)
                        .filter(Column("deletedAt") == nil && Column("databaseId") == nil)
                        .order(Column("sortKey"))
                        .fetchAll(db)
                )
            }

        let sources = try Source
            .filter(Column("folderId") == folderId)
            .filter(Column("deletedAt") == nil)
            .order(Column("createdAt"))
            .fetchAll(db)
            .map { source in
                LibrarySource(
                    source: source,
                    highlightCount: try Highlight
                        .filter(Column("sourceId") == source.id && Column("deletedAt") == nil)
                        .fetchCount(db)
                )
            }

        return LibrarySnapshot(folder: folder, path: path, folders: folders, pages: pages, sources: sources, isMissing: false)
    }

    static func itemCount(_ db: Database, in folderId: UUID) throws -> Int {
        let folders = try Folder
            .filter(Column("parentId") == folderId && Column("deletedAt") == nil)
            .fetchCount(db)
        let pages = try Page
            .filter(Column("folderId") == folderId && Column("parentId") == nil)
            .filter(Column("inInbox") == false && Column("deletedAt") == nil)
            .fetchCount(db)
        let sources = try Source
            .filter(Column("folderId") == folderId && Column("deletedAt") == nil)
            .fetchCount(db)
        return folders + pages + sources
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

/// Страницы, которые нужны открытому редактору: все живые страницы для выбора ссылки
/// и подписей блоков-ссылок, и страницы, которые ссылаются на открытую.
public struct PageLinksSnapshot: Equatable, Sendable {
    public var pages: [Page]
    public var backlinks: [Page]
    /// Живые источники: для подписей выписок и для шапки страницы заметок к книге.
    public var sources: [Source]

    public static let empty = PageLinksSnapshot(pages: [], backlinks: [], sources: [])

    public static func fetch(_ db: Database, pageId: UUID) throws -> PageLinksSnapshot {
        let pages = try Page
            .filter(Column("deletedAt") == nil)
            .order(Column("updatedAt").desc)
            .fetchAll(db)
        let backlinks = try Page.fetchAll(db, sql: """
            SELECT DISTINCT page.*
            FROM link
            JOIN page ON page.id = link.sourcePageId
            WHERE link.targetPageId = ? AND page.id != ? AND page.deletedAt IS NULL
            ORDER BY page.title
            """, arguments: [pageId, pageId])
        let sources = try Source
            .filter(Column("deletedAt") == nil)
            .fetchAll(db)
        return PageLinksSnapshot(pages: pages, backlinks: backlinks, sources: sources)
    }
}

/// Корзина: удалённые папки (только верхние, вложенные вернутся вместе с ними), страницы и книги.
public struct TrashSnapshot: Equatable, Sendable {
    public var folders: [Folder]
    public var pages: [Page]
    public var sources: [Source]

    public static let empty = TrashSnapshot(folders: [], pages: [], sources: [])

    public var isEmpty: Bool { folders.isEmpty && pages.isEmpty && sources.isEmpty }

    public static func fetch(_ db: Database) throws -> TrashSnapshot {
        let folders = try Folder.fetchAll(db, sql: """
            SELECT folder.*
            FROM folder
            LEFT JOIN folder AS parent ON parent.id = folder.parentId
            WHERE folder.deletedAt IS NOT NULL AND (parent.id IS NULL OR parent.deletedAt IS NULL)
            ORDER BY folder.deletedAt DESC
            """)
        // Страницы из удалённой папки вернутся вместе с ней, отдельно их не показываем.
        // Заметки к удалённой книге тоже вернутся вместе с книгой.
        let pages = try Page.fetchAll(db, sql: """
            SELECT page.*
            FROM page
            LEFT JOIN folder ON folder.id = page.folderId
            LEFT JOIN source ON source.id = page.sourceId
            WHERE page.deletedAt IS NOT NULL AND (folder.id IS NULL OR folder.deletedAt IS NULL)
                AND (source.id IS NULL OR source.deletedAt IS NULL)
            ORDER BY page.deletedAt DESC
            """)
        let sources = try Source.fetchAll(db, sql: """
            SELECT source.*
            FROM source
            LEFT JOIN folder ON folder.id = source.folderId
            WHERE source.deletedAt IS NOT NULL AND (folder.id IS NULL OR folder.deletedAt IS NULL)
            ORDER BY source.deletedAt DESC
            """)
        return TrashSnapshot(folders: folders, pages: pages, sources: sources)
    }
}

/// Книги на полке «Кабинета»: что читали недавно, стоит слева, дальше новые, ещё не открытые.
/// Другой порядок (свой, по названию и т. д.) накладывает `ShelfSort`.
public enum ShelfQuery {
    public static func fetch(_ db: Database, limit: Int = 500) throws -> [Source] {
        try Source
            .filter(Column("deletedAt") == nil)
            .order(sql: "lastOpenedAt IS NULL, lastOpenedAt DESC, createdAt DESC, rowid DESC")
            .limit(limit)
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
        // Строки баз данных (задачи) это тоже страницы, но в «Недавних» и счётчиках им не место.
        let alive = Page.filter(Column("deletedAt") == nil && Column("databaseId") == nil)
        let startOfDay = calendar.startOfDay(for: now)
        return HomeSnapshot(
            inboxCount: try alive.filter(Column("inInbox") == true).fetchCount(db),
            pageCount: try alive.fetchCount(db),
            editedToday: try alive.filter(Column("updatedAt") >= startOfDay).fetchCount(db),
            recent: try previews(db, sql: """
                SELECT page.*, pageSearch.body AS excerpt
                FROM page
                LEFT JOIN pageSearch ON pageSearch.pageId = \(uuidText("page.id"))
                WHERE page.deletedAt IS NULL AND page.databaseId IS NULL
                ORDER BY page.updatedAt DESC
                LIMIT 6
                """)
        )
    }
}

private func previews(_ db: Database, sql: String, arguments: StatementArguments = StatementArguments()) throws -> [PagePreview] {
    try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
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
