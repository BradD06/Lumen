import Foundation
import GRDB
import LumenCore

/// Всё для доски связей: что приколото, живые книги, папки и страницы, связи между ними
/// и нитки между приколотым. Связи не хранятся отдельно, а каждый раз собираются из заметок:
/// ссылки на страницы (`link`), ссылки `lumen://` в тексте, выписки и заметки к книгам.
public struct BoardSnapshot: Equatable, Sendable {
    /// Приколотое, только живое (не в корзине).
    public var pins: [BoardPin]
    /// Все живые вещи по id: для карточек и для окна «Приколоть…».
    public var pages: [UUID: Page]
    public var sources: [UUID: Source]
    public var folders: [UUID: Folder]
    /// Сколько всего лежит прямо в папке.
    public var folderCounts: [UUID: Int]
    /// Начало текста приколотых страниц.
    public var snippets: [UUID: String]
    public var relations: [BoardRelation]
    /// Где лежит вещь: папка или родительская страница.
    public var container: [LibraryItemID: LibraryItemID]
    public var threads: [BoardThread]

    public static let empty = BoardSnapshot(
        pins: [], pages: [:], sources: [:], folders: [:], folderCounts: [:], snippets: [:],
        relations: [], container: [:], threads: []
    )

    public var pinnedItems: Set<LibraryItemID> { Set(pins.map(\.item)) }

    /// Связанное, что ещё не приколото: это кнопка «Приколоть всё, что связано».
    public var unpinnedLinkedItems: Set<LibraryItemID> {
        LinkBoard.linkedItems(relations).subtracting(pinnedItems)
    }

    public func isAlive(_ item: LibraryItemID) -> Bool {
        switch item {
        case .page(let id): pages[id] != nil
        case .source(let id): sources[id] != nil
        case .folder(let id): folders[id] != nil
        }
    }

    public static func fetch(_ db: Database) throws -> BoardSnapshot {
        let alive = Column("deletedAt") == nil
        let pageList = try Page.filter(alive).fetchAll(db)
        let sourceList = try Source.filter(alive).fetchAll(db)
        let folderList = try Folder.filter(alive).fetchAll(db)
        var snapshot = BoardSnapshot.empty
        snapshot.pages = Dictionary(pageList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        snapshot.sources = Dictionary(sourceList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        snapshot.folders = Dictionary(folderList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Копия только для проверки «жива ли вещь»: замыкания ниже не трогают меняющийся `snapshot`.
        let living = snapshot

        // Где что лежит.
        var container: [LibraryItemID: LibraryItemID] = [:]
        var counts: [UUID: Int] = [:]
        for page in pageList {
            if let parent = page.parentId {
                container[.page(page.id)] = .page(parent)
            } else if let folder = page.folderId {
                container[.page(page.id)] = .folder(folder)
                if !page.isDatabaseRow { counts[folder, default: 0] += 1 }
            }
        }
        for source in sourceList {
            if let folder = source.folderId {
                container[.source(source.id)] = .folder(folder)
                counts[folder, default: 0] += 1
            }
        }
        for folder in folderList {
            if let parent = folder.parentId {
                container[.folder(folder.id)] = .folder(parent)
                counts[parent, default: 0] += 1
            }
        }
        snapshot.container = container.filter { living.isAlive($0.key) && living.isAlive($0.value) }
        snapshot.folderCounts = counts

        snapshot.relations = try relations(db).filter { living.isAlive($0.from) && living.isAlive($0.to) }
        snapshot.pins = try BoardPin
            .order(Column("createdAt"))
            .fetchAll(db)
            .filter { living.isAlive($0.item) }
        snapshot.threads = LinkBoard.threads(
            relations: snapshot.relations,
            pinned: snapshot.pinnedItems,
            container: snapshot.container
        )
        snapshot.snippets = try snippets(db, pageIds: snapshot.pins.filter { $0.kind == .page }.map(\.id))
        return snapshot
    }

    /// Связи из заметок, без проверки, живы ли концы.
    static func relations(_ db: Database) throws -> [BoardRelation] {
        var relations: [BoardRelation] = []
        // Блоки «Страница» и `[[ссылки]]`: индекс уже собран.
        for row in try Row.fetchAll(db, sql: "SELECT DISTINCT sourcePageId, targetPageId FROM link") {
            let from: UUID = row["sourcePageId"]
            let to: UUID = row["targetPageId"]
            relations.append(BoardRelation(.page(from), .page(to), kind: .link))
        }
        // Выписки и ссылки `lumen://` в тексте. Косые черты в JSON могут быть экранированы,
        // поэтому ищем по «lumen:».
        let decoder = JSONDecoder()
        let rows = try Row.fetchAll(db, sql: """
            SELECT pageId, content FROM block
            WHERE type = ? OR content LIKE '%lumen:%'
            """, arguments: [BlockType.excerpt.rawValue])
        for row in rows {
            let pageId: UUID = row["pageId"]
            guard let data = row["content"] as Data?,
                  let content = try? decoder.decode(BlockContent.self, from: data) else { continue }
            if let excerpt = content.excerpt {
                relations.append(BoardRelation(.page(pageId), .source(excerpt.sourceId), kind: .excerpt))
            }
            for run in content.runs {
                guard let text = run.link, let url = URL(string: text), let link = LumenLink(url: url) else { continue }
                switch link {
                case .page(let target):
                    relations.append(BoardRelation(.page(pageId), .page(target), kind: .link))
                case .source(let source):
                    relations.append(BoardRelation(.page(pageId), .source(source), kind: .link))
                case .highlight(let source, _), .place(let source, _):
                    relations.append(BoardRelation(.page(pageId), .source(source), kind: .excerpt))
                }
            }
        }
        // Заметки к книгам.
        for row in try Row.fetchAll(db, sql: "SELECT id, sourceId FROM page WHERE sourceId IS NOT NULL") {
            let pageId: UUID = row["id"]
            let sourceId: UUID = row["sourceId"]
            relations.append(BoardRelation(.page(pageId), .source(sourceId), kind: .notes))
        }
        return relations.filter { $0.from != $0.to }
    }

    /// Начало текста страниц для карточек: первые строки, без названия.
    static func snippets(_ db: Database, pageIds: [UUID]) throws -> [UUID: String] {
        guard !pageIds.isEmpty else { return [:] }
        let marks = Array(repeating: "?", count: pageIds.count).joined(separator: ", ")
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT pageId, substr(body, 1, 200) AS body FROM pageSearch WHERE pageId IN (\(marks))",
            arguments: StatementArguments(pageIds.map(\.uuidString))
        )
        var result: [UUID: String] = [:]
        for row in rows {
            guard let idText = row["pageId"] as String?, let id = UUID(uuidString: idText) else { continue }
            let body = (row["body"] as String? ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !body.isEmpty { result[id] = body }
        }
        return result
    }
}

extension AppDatabase {
    /// Прикалывает вещи к доске (или переносит уже приколотые) в указанные места.
    public func pinToBoard(_ placements: [LibraryItemID: LibraryPoint]) async throws {
        guard !placements.isEmpty else { return }
        try await writer.write { db in
            let now = Date()
            for (item, point) in placements {
                if var pin = try BoardPin.fetchOne(db, key: item.uuid) {
                    pin.point = point
                    pin.updatedAt = now
                    try pin.update(db)
                } else {
                    try BoardPin(item: item, at: point, createdAt: now).insert(db)
                }
            }
        }
    }

    /// Прикалывает одну вещь рядом с тем, с чем она связана, или в свободное место.
    /// Возвращает `false`, если она уже на доске.
    @discardableResult
    public func pinToBoard(_ item: LibraryItemID) async throws -> Bool {
        try await writer.write { db -> Bool in
            let snapshot = try BoardSnapshot.fetch(db)
            guard snapshot.isAlive(item), !snapshot.pinnedItems.contains(item) else { return false }
            let occupied = Dictionary(snapshot.pins.map { ($0.item, $0.point) }, uniquingKeysWith: { first, _ in first })
            let threads = LinkBoard.threads(
                relations: snapshot.relations,
                pinned: snapshot.pinnedItems.union([item]),
                container: snapshot.container
            )
            guard let point = BoardLayout.place([item], occupied: occupied, threadsAfter: threads)[item] else { return false }
            try BoardPin(item: item, at: point).insert(db)
            return true
        }
    }

    /// Карточку передвинули по доске.
    public func moveBoardPin(_ item: LibraryItemID, to point: LibraryPoint) async throws {
        try await pinToBoard([item: point])
    }

    /// Снимает вещи с доски. Сами книги, папки и заметки не трогаются.
    public func unpinFromBoard(_ items: [LibraryItemID]) async throws {
        guard !items.isEmpty else { return }
        try await writer.write { db in
            _ = try BoardPin.filter(keys: items.map(\.uuid)).deleteAll(db)
        }
    }

    /// Вещь удалили навсегда: её кнопка с доски тоже уходит.
    static func removeOrphanBoardPins(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM boardPin
            WHERE (kind = 'page' AND id NOT IN (SELECT id FROM page))
                OR (kind = 'source' AND id NOT IN (SELECT id FROM source))
                OR (kind = 'folder' AND id NOT IN (SELECT id FROM folder))
            """)
    }
}
