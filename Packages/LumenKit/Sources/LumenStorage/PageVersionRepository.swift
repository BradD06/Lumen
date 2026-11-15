import Foundation
import GRDB
import LumenCore

/// Прошлая версия страницы: название и все блоки, как они были. Хранится только на этом устройстве.
public struct PageVersion: Identifiable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pageVersion"

    public var id: UUID
    public var pageId: UUID
    public var title: String
    public var blockCount: Int
    /// Блоки страницы в JSON.
    public var blocks: Data
    public var createdAt: Date

    public init(id: UUID = UUID(), pageId: UUID, title: String, blocks: [Block], createdAt: Date) throws {
        self.id = id
        self.pageId = pageId
        self.title = title
        self.blockCount = blocks.count
        self.blocks = try JSONEncoder().encode(blocks)
        self.createdAt = createdAt
    }

    public func decodedBlocks() throws -> [Block] {
        try JSONDecoder().decode([Block].self, from: blocks)
    }
}

/// Версия в списке истории, без самих блоков.
public struct PageVersionSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var blockCount: Int
    public var createdAt: Date
}

extension AppDatabase {
    /// Запоминает страницу такой, как сейчас, если с прошлой версии прошло десять минут
    /// (`force`: сразу, например перед откатом) и в ней что-то поменялось.
    /// Возвращает true, если версия записана. Старые версии прореживаются (`PageVersionPolicy`).
    @discardableResult
    public func savePageVersion(
        pageId: UUID,
        title: String,
        blocks: [Block],
        force: Bool = false,
        now: Date = Date()
    ) async throws -> Bool {
        try await writer.write { db in
            guard try Page.fetchOne(db, key: pageId) != nil else { return false }
            let latest = try PageVersion
                .filter(Column("pageId") == pageId)
                .order(Column("createdAt").desc)
                .fetchOne(db)
            if !force, !PageVersionPolicy.isDue(last: latest?.createdAt, now: now) { return false }
            if let latest, latest.title == title,
               let previous = try? latest.decodedBlocks(),
               PageVersionPolicy.normalized(previous) == PageVersionPolicy.normalized(blocks) {
                return false
            }
            try PageVersion(pageId: pageId, title: title, blocks: blocks, createdAt: now).insert(db)

            let dates = try Row.fetchAll(
                db,
                sql: "SELECT id, createdAt FROM pageVersion WHERE pageId = ?",
                arguments: [pageId]
            )
            let ids: [UUID] = dates.map { $0["id"] }
            let removed = PageVersionPolicy.toDelete(dates.map { $0["createdAt"] }, now: now)
            if !removed.isEmpty {
                try PageVersion.deleteAll(db, keys: removed.map { ids[$0] })
            }
            return true
        }
    }

    /// Версии страницы, новые сверху.
    public func pageVersions(of pageId: UUID) async throws -> [PageVersionSummary] {
        try await reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, title, blockCount, createdAt FROM pageVersion
                WHERE pageId = ? ORDER BY createdAt DESC
                """, arguments: [pageId]).map { row in
                PageVersionSummary(id: row["id"], title: row["title"], blockCount: row["blockCount"], createdAt: row["createdAt"])
            }
        }
    }

    public func pageVersion(_ id: UUID) async throws -> PageVersion? {
        try await reader.read { db in try PageVersion.fetchOne(db, key: id) }
    }
}
