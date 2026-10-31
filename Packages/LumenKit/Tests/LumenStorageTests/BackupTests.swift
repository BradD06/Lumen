import Foundation
import GRDB
import Testing
import LumenCore
@testable import LumenStorage

struct BackupTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumenBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// База на диске в своей папке, как настоящая: файл базы, рядом вложения и копии.
    private func makeDatabase(_ name: String) throws -> AppDatabase {
        let home = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return try AppDatabase.onDisk(
            at: home.appendingPathComponent("lumen.sqlite"),
            attachments: AttachmentStore(folder: home.appendingPathComponent("Attachments", isDirectory: true))
        )
    }

    private func titles(_ db: AppDatabase) async throws -> [String] {
        try await db.reader.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM page WHERE deletedAt IS NULL ORDER BY title")
        }
    }

    @Test func backupRestoresPagesBooksAndFiles() async throws {
        let original = try makeDatabase("original")
        let page = try await original.createPage(title: "Конспект")
        var block = try #require(try await original.blocks(of: page.id).first)
        block.text = "Пределы и производные"
        try await original.saveBlock(block)
        let file = try original.attachments.save(Data("книга".utf8), fileExtension: "epub")
        let book = try await original.addSource(title: "Мастер и Маргарита", format: .epub, file: file, originalName: "book.epub")

        let archive = folder.appendingPathComponent("copy.zip")
        let saved = try await original.writeBackup(to: archive)
        #expect(saved.pageCount == 1)
        #expect(saved.sourceCount == 1)
        #expect(saved.fileCount == 1)

        let other = try makeDatabase("other")
        try await other.createPage(title: "Другая заметка")

        let restored = try await other.restoreBackup(from: archive)
        #expect(restored.pageCount == 1)
        #expect(try await titles(other) == ["Конспект"])
        #expect(try await other.blocks(of: page.id).map(\.text) == ["Пределы и производные"])
        #expect(try await other.source(book.id)?.title == "Мастер и Маргарита")
        #expect(other.attachments.data(for: file) == Data("книга".utf8))
        #expect(try await other.search("производные").map(\.pageId) == [page.id], "Поиск работает по восстановленным страницам")

        // То, что было до восстановления, лежит в автоматической копии, и его можно вернуть.
        let safety = try #require(AppDatabase.automaticBackups(in: other.backupsFolder).first)
        #expect(safety.kind == .beforeRestore)
        try await other.restoreBackup(from: safety.url)
        #expect(try await titles(other) == ["Другая заметка"])
    }

    @Test func backupWithoutFilesKeepsCurrentFiles() async throws {
        let db = try makeDatabase("db")
        let file = try db.attachments.save(Data([1, 2, 3]), fileExtension: "png")
        let archive = folder.appendingPathComponent("light.zip")
        let summary = try await db.writeBackup(to: archive, includeFiles: false)
        #expect(!summary.includesFiles)
        #expect(summary.fileCount == 0)

        try await db.restoreBackup(from: archive)
        #expect(db.attachments.data(for: file) == Data([1, 2, 3]))
    }

    @Test func rejectsFilesThatAreNotBackups() async throws {
        let db = try makeDatabase("db")
        let text = folder.appendingPathComponent("notes.txt")
        try Data("просто текст".utf8).write(to: text)
        await #expect(throws: BackupError.notABackup) {
            try await db.restoreBackup(from: text)
        }

        // Чужая база SQLite тоже не копия Lumen.
        let foreign = folder.appendingPathComponent("foreign.sqlite")
        try await DatabaseQueue(path: foreign.path).write { db in
            try db.execute(sql: "CREATE TABLE note (id INTEGER PRIMARY KEY, text TEXT)")
        }
        await #expect(throws: BackupError.notABackup) {
            try await db.restoreBackup(from: foreign)
        }
        #expect(try await titles(db).isEmpty, "После ошибки база не тронута")
    }

    @Test func copiesDatabaseBeforeMigratingAndRestoresOldCopy() async throws {
        let home = folder.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let url = home.appendingPathComponent("lumen.sqlite")
        let pageId = UUID()
        // База старой версии приложения: только первая миграция и одна страница.
        do {
            let pool = try DatabasePool(path: url.path)
            try AppDatabase.migrator.migrate(pool, upTo: "v1: pages, blocks, search")
            try await pool.write { db in
                try db.execute(
                    sql: "INSERT INTO page (id, title, sortKey, createdAt, updatedAt) VALUES (?, 'Старая', 'a', ?, ?)",
                    arguments: [pageId, Date(), Date()]
                )
            }
        }

        let backups = home.appendingPathComponent("Backups", isDirectory: true)
        let updated = try AppDatabase.onDisk(at: url)
        #expect(try await updated.page(pageId)?.title == "Старая")
        let copies = AppDatabase.automaticBackups(in: backups)
        #expect(copies.map(\.kind) == [.beforeUpdate])

        // Схема уже новая: при следующем запуске копия не нужна.
        _ = try AppDatabase.onDisk(at: url)
        #expect(AppDatabase.automaticBackups(in: backups).count == 1)

        // Копию старой схемы можно восстановить: она догоняет схему теми же миграциями.
        let fresh = try makeDatabase("fresh")
        try await fresh.restoreBackup(from: try #require(copies.first).url)
        #expect(try await fresh.page(pageId)?.title == "Старая")
    }

    @Test func newEmptyDatabaseIsNotCopied() throws {
        _ = try makeDatabase("new")
        let backups = folder.appendingPathComponent("new/Backups", isDirectory: true)
        #expect(AppDatabase.automaticBackups(in: backups).isEmpty)
    }

    @Test func restoresOnlyDataTables() async throws {
        let db = try AppDatabase.inMemory()
        let tables = try await db.reader.read { try AppDatabase.restorableTables($0) }
        #expect(Set(["page", "block", "folder", "source", "highlight", "link", "readingSession", "pageSearch"])
            .isSubset(of: Set(tables)))
        #expect(!tables.contains { $0.hasPrefix("sync") || $0.hasPrefix("grdb_") || $0.hasPrefix("pageSearch_") })
    }
}
