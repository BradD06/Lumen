import Foundation
import GRDB
import LumenCore

extension AppDatabase {
    /// Записывает отрезок чтения. Пока книга открыта, один и тот же отрезок перезаписывается
    /// с растущим временем, поэтому вызывать можно сколько угодно раз.
    public func saveReadingSession(_ session: ReadingSession) async throws {
        try await writer.write { db in
            guard try Source.exists(db, key: session.sourceId) else { return }
            try session.save(db)
        }
    }

    public func readingStats(of sourceId: UUID, now: Date = Date(), calendar: Calendar = .current) async throws -> ReadingStats {
        try await reader.read { db in
            ReadingStats(sessions: try ReadingSession.forSource(sourceId, db), now: now, calendar: calendar)
        }
    }
}

extension ReadingSession {
    static func forSource(_ sourceId: UUID, _ db: Database) throws -> [ReadingSession] {
        try ReadingSession.filter(Column("sourceId") == sourceId).order(Column("endedAt")).fetchAll(db)
    }
}

/// Всё для дашборда книги: сама книга, выделения, время чтения и страницы с выписками из неё.
public struct SourceDashboardSnapshot: Equatable, Sendable {
    public var source: Source?
    public var highlights: [Highlight]
    public var sessions: [ReadingSession]
    /// Страница заметок к книге, если её уже создали.
    public var notesPage: Page?
    /// Другие страницы, где есть выписки из книги, и сколько выписок на каждой. Новые сверху.
    public var excerptPages: [ExcerptPage]

    public struct ExcerptPage: Equatable, Sendable, Identifiable {
        public var page: Page
        public var excerptCount: Int

        public var id: UUID { page.id }
    }

    public static let empty = SourceDashboardSnapshot(source: nil, highlights: [], sessions: [], notesPage: nil, excerptPages: [])

    public static func fetch(_ db: Database, sourceId: UUID) throws -> SourceDashboardSnapshot {
        let source = try Source.fetchOne(db, key: sourceId)
        let highlights = try Highlight
            .filter(Column("sourceId") == sourceId && Column("deletedAt") == nil)
            .order(Column("createdAt"))
            .fetchAll(db)
        let sessions = try ReadingSession.forSource(sourceId, db)
        let notesPage = try Page
            .filter(Column("sourceId") == sourceId && Column("parentId") == nil && Column("deletedAt") == nil)
            .fetchOne(db)

        var counts: [UUID: Int] = [:]
        for block in try Block.filter(Column("type") == BlockType.excerpt.rawValue).fetchAll(db)
        where block.content.excerpt?.sourceId == sourceId {
            counts[block.pageId, default: 0] += 1
        }
        if let notesPage { counts[notesPage.id] = nil }
        let excerptPages = try Page
            .filter(keys: Array(counts.keys))
            .filter(Column("deletedAt") == nil)
            .order(Column("updatedAt").desc)
            .fetchAll(db)
            .map { ExcerptPage(page: $0, excerptCount: counts[$0.id] ?? 0) }

        return SourceDashboardSnapshot(
            source: source,
            highlights: highlights,
            sessions: sessions,
            notesPage: notesPage,
            excerptPages: excerptPages
        )
    }
}

/// Чтение для главного экрана: какую книгу продолжить и сколько читали по всем книгам.
public struct HomeReadingSnapshot: Equatable, Sendable {
    /// Книга, которую открывали последней, если её ещё не дочитали. Иначе последняя добавленная.
    public var current: Source?
    /// Время чтения по всем книгам: сегодня, серия дней и последние две недели.
    public var stats: ReadingStats
    /// Сколько книг и файлов в библиотеке.
    public var sourceCount: Int

    public static let empty = HomeReadingSnapshot(current: nil, stats: .empty, sourceCount: 0)

    public static func fetch(_ db: Database, now: Date = Date(), calendar: Calendar = .current) throws -> HomeReadingSnapshot {
        let alive = Source.filter(Column("deletedAt") == nil)
        let current = try alive
            .filter(Column("lastOpenedAt") != nil && Column("progress") < 0.995)
            .order(Column("lastOpenedAt").desc)
            .fetchOne(db)
            ?? alive.filter(Column("lastOpenedAt") == nil).order(Column("createdAt").desc, Column.rowID.desc).fetchOne(db)
        // Серия и график берут только последние недели, старые отрезки не нужны.
        let since = calendar.date(byAdding: .day, value: -400, to: now) ?? now
        let sessions = try ReadingSession
            .filter(Column("endedAt") >= since)
            .filter(sql: "sourceId IN (SELECT id FROM source WHERE deletedAt IS NULL)")
            .fetchAll(db)
        return HomeReadingSnapshot(
            current: current,
            stats: ReadingStats(sessions: sessions, now: now, calendar: calendar),
            sourceCount: try alive.fetchCount(db)
        )
    }
}
