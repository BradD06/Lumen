import Foundation
import GRDB
import LumenCore
import ZIPFoundation

/// Что лежит в резервной копии. Показывается после сохранения и восстановления.
public struct BackupSummary: Codable, Hashable, Sendable {
    public var createdAt: Date
    public var pageCount: Int
    public var sourceCount: Int
    /// Сколько файлов (книг, картинок, обложек) лежит в копии.
    public var fileCount: Int
    /// Копия только базы, без файлов: такие делаются автоматически, файлы при этом остаются на месте.
    public var includesFiles: Bool

    public init(createdAt: Date, pageCount: Int, sourceCount: Int, fileCount: Int, includesFiles: Bool) {
        self.createdAt = createdAt
        self.pageCount = pageCount
        self.sourceCount = sourceCount
        self.fileCount = fileCount
        self.includesFiles = includesFiles
    }
}

public enum BackupError: LocalizedError, Equatable, Sendable {
    /// Файл не zip-архив Lumen и не база SQLite.
    case notABackup
    /// Копию сделала более новая версия Lumen: эта версия её не поймёт.
    case newerVersion

    public var errorDescription: String? {
        switch self {
        case .notABackup:
            "Это не резервная копия Lumen. Выберите zip-файл, который сохранил Lumen."
        case .newerVersion:
            "Копию сделала более новая версия Lumen. Обновите приложение и попробуйте снова."
        }
    }
}

/// Копия, которую Lumen сделал сам: перед обновлением схемы базы или перед восстановлением.
public struct AutomaticBackup: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// Перед тем как новая версия приложения поменяла схему базы.
        case beforeUpdate = "before-update"
        /// Перед восстановлением другой копии: так можно вернуть то, что было.
        case beforeRestore = "before-restore"

        public var title: String {
            switch self {
            case .beforeUpdate: "Перед обновлением приложения"
            case .beforeRestore: "Перед восстановлением копии"
            }
        }
    }

    public var url: URL
    public var kind: Kind
    public var date: Date

    public var id: URL { url }
}

/// Описание копии, лежит в архиве рядом с базой.
struct BackupManifest: Codable {
    static let currentFormat = 1

    var app = "Lumen"
    var format = BackupManifest.currentFormat
    var summary: BackupSummary
}

// MARK: - Сохранение

extension AppDatabase {
    static let backupDatabaseName = "lumen.sqlite"
    static let backupManifestName = "manifest.json"
    static let backupFilesFolder = "Attachments"

    /// Папка автоматических копий: рядом с папкой вложений.
    public var backupsFolder: URL {
        attachments.folder.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    /// Имя файла копии, например «Lumen копия 2026-10-31 11-42.zip».
    public static func backupFileName(date: Date = Date()) -> String {
        "Lumen копия \(stamp(date, format: "yyyy-MM-dd HH-mm")).zip"
    }

    /// Сохраняет всю базу в zip-архив: страницы, папки, книги с выделениями, время чтения.
    /// С `includeFiles` в архив кладутся и вложения: файлы книг, картинки и обложки.
    /// Пока делается копия, база открыта как обычно, в архив попадает её состояние на момент начала.
    @discardableResult
    public func writeBackup(to destination: URL, includeFiles: Bool = true) async throws -> BackupSummary {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("LumenBackup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // VACUUM INTO пишет целостный снимок базы одним файлом, без журнала WAL рядом.
        let databasePath = staging.appendingPathComponent(Self.backupDatabaseName).path
        try await writer.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [databasePath])
        }

        var fileCount = 0
        if includeFiles {
            let filesFolder = staging.appendingPathComponent(Self.backupFilesFolder, isDirectory: true)
            try fileManager.createDirectory(at: filesFolder, withIntermediateDirectories: true)
            for file in attachmentFiles() {
                let target = filesFolder.appendingPathComponent(file.lastPathComponent)
                // Книги бывают большими: жёсткая ссылка не копирует данные, а если не вышло, копируем.
                do {
                    try fileManager.linkItem(at: file, to: target)
                } catch {
                    try fileManager.copyItem(at: file, to: target)
                }
                fileCount += 1
            }
        }

        let counts = try await reader.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page WHERE deletedAt IS NULL") ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source WHERE deletedAt IS NULL") ?? 0
            )
        }
        let summary = BackupSummary(
            createdAt: Date(),
            pageCount: counts.0,
            sourceCount: counts.1,
            fileCount: fileCount,
            includesFiles: includeFiles
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(BackupManifest(summary: summary))
            .write(to: staging.appendingPathComponent(Self.backupManifestName))

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.zipItem(at: staging, to: destination, shouldKeepParent: false, compressionMethod: .deflate)
        return summary
    }

    /// Сохраняет копию во временную папку под понятным именем. Дальше её переносят, куда скажет человек.
    public func writeBackupToTemporaryFile(includeFiles: Bool = true) async throws -> (url: URL, summary: BackupSummary) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumenExport-\(UUID().uuidString)", isDirectory: true)
        let url = folder.appendingPathComponent(Self.backupFileName())
        let summary = try await writeBackup(to: url, includeFiles: includeFiles)
        return (url, summary)
    }

    private func attachmentFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: attachments.folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}

// MARK: - Восстановление

/// Распакованная и проверенная копия во временной папке. База в ней уже приведена к текущей схеме.
struct PreparedBackup {
    var folder: URL
    var databaseURL: URL
    var filesFolder: URL?
    var manifest: BackupManifest?

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

extension AppDatabase {
    /// Заменяет всё содержимое базы содержимым копии. Перед этим текущая база сохраняется
    /// в автоматическую копию «перед восстановлением», так что вернуть всё как было можно всегда.
    /// Файлы-вложения из копии добавляются к текущим, а не заменяют их.
    ///
    /// Принимает zip-архив из `writeBackup` и голый файл базы SQLite (автоматические копии перед обновлением).
    @discardableResult
    public func restoreBackup(from archive: URL) async throws -> BackupSummary {
        let prepared = try Self.prepareBackup(at: archive)
        defer { prepared.remove() }

        let safetyCopy = Self.automaticBackupURL(in: backupsFolder, kind: .beforeRestore, fileExtension: "zip")
        try await writeBackup(to: safetyCopy, includeFiles: false)
        Self.pruneAutomaticBackups(in: backupsFolder, kind: .beforeRestore)

        return try await apply(prepared)
    }

    /// Восстановление, когда сама база не открывается. Повреждённые файлы базы переносятся в
    /// `Backups/Повреждённая …` (ничего не удаляется), на их месте создаётся новая база,
    /// и если указана копия, в неё переносится содержимое копии.
    public static func recoverDefault(from archive: URL?) async throws -> AppDatabase {
        // Сначала проверяем копию: если она не подходит, старую базу трогать незачем.
        let prepared = try archive.map { try prepareBackup(at: $0) }
        defer { prepared?.remove() }

        let folder = try defaultFolder()
        try setAsideDatabase(at: folder.appendingPathComponent(databaseFileName))
        let database = try makeDefault()
        if let prepared {
            try await database.apply(prepared)
        }
        return database
    }

    /// Переносит файлы базы (с журналом WAL) в отдельную папку внутри `Backups`.
    static func setAsideDatabase(at url: URL) throws {
        let fileManager = FileManager.default
        let backups = url.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        let target = backups.appendingPathComponent("Повреждённая \(stamp(Date()))", isDirectory: true)
        var isCreated = false
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: file.path) else { continue }
            if !isCreated {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                isCreated = true
            }
            try fileManager.moveItem(at: file, to: target.appendingPathComponent(file.lastPathComponent))
        }
    }

    /// Распаковывает копию во временную папку, проверяет и обновляет её схему до текущей.
    static func prepareBackup(at archive: URL) throws -> PreparedBackup {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("LumenRestore-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var prepared = PreparedBackup(folder: folder, databaseURL: folder.appendingPathComponent(backupDatabaseName))
        do {
            if isSQLiteFile(archive) {
                try fileManager.copyItem(at: archive, to: prepared.databaseURL)
            } else {
                let unpacked = folder.appendingPathComponent("unpacked", isDirectory: true)
                do {
                    try fileManager.unzipItem(at: archive, to: unpacked)
                } catch {
                    throw BackupError.notABackup
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                guard let data = try? Data(contentsOf: unpacked.appendingPathComponent(backupManifestName)),
                      let manifest = try? decoder.decode(BackupManifest.self, from: data),
                      manifest.app == "Lumen"
                else { throw BackupError.notABackup }
                guard manifest.format <= BackupManifest.currentFormat else { throw BackupError.newerVersion }
                prepared.manifest = manifest
                let database = unpacked.appendingPathComponent(backupDatabaseName)
                guard fileManager.fileExists(atPath: database.path) else { throw BackupError.notABackup }
                try fileManager.moveItem(at: database, to: prepared.databaseURL)
                let files = unpacked.appendingPathComponent(backupFilesFolder, isDirectory: true)
                if fileManager.fileExists(atPath: files.path) {
                    prepared.filesFolder = files
                }
            }
            try migrateBackupDatabase(at: prepared.databaseURL)
            return prepared
        } catch {
            prepared.remove()
            throw error
        }
    }

    /// Проверяет, что это база Lumen, и догоняет её схему до текущей версии теми же миграциями,
    /// что и основная база: копия от старой версии приложения восстанавливается без потерь.
    private static func migrateBackupDatabase(at url: URL) throws {
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: url.path, configuration: configuration)
        } catch {
            throw BackupError.notABackup
        }
        let state = try queue.read { db -> (isLumen: Bool, isNewer: Bool) in
            guard (try? db.tableExists("grdb_migrations")) == true, (try? db.tableExists("page")) == true else {
                return (false, false)
            }
            return (true, try migrator.hasBeenSuperseded(db))
        }
        guard state.isLumen else { throw BackupError.notABackup }
        guard !state.isNewer else { throw BackupError.newerVersion }
        try migrator.migrate(queue)
    }

    private static func isSQLiteFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 16)) ?? Data()
        return header == Data("SQLite format 3\u{0}".utf8)
    }

    /// Переносит строки из подготовленной копии в эту базу одной транзакцией:
    /// если что-то пойдёт не так, база останется такой, какой была.
    /// Открытые экраны сразу видят новое содержимое, потому что всё идёт обычной записью.
    private func apply(_ prepared: PreparedBackup) async throws -> BackupSummary {
        let path = prepared.databaseURL.path
        try await writer.writeWithoutTransaction { db in
            try db.execute(sql: "ATTACH DATABASE ? AS lumenBackup", arguments: [path])
            defer { try? db.execute(sql: "DETACH DATABASE lumenBackup") }
            try db.inTransaction {
                // Ссылки между таблицами проверяются в конце транзакции: порядок вставки не важен.
                try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
                let tables = try Self.restorableTables(db)
                for table in tables {
                    try db.execute(sql: "DELETE FROM main.\(table.quotedDatabaseIdentifier)")
                }
                for table in tables {
                    let backupColumns = Set(try String.fetchAll(
                        db,
                        sql: "SELECT name FROM pragma_table_info(?, 'lumenBackup')",
                        arguments: [table]
                    ))
                    guard !backupColumns.isEmpty else { continue }
                    let columns = try String
                        .fetchAll(db, sql: "SELECT name FROM pragma_table_info(?, 'main')", arguments: [table])
                        .filter { backupColumns.contains($0) }
                        .map(\.quotedDatabaseIdentifier)
                        .joined(separator: ", ")
                    try db.execute(sql: """
                        INSERT INTO main.\(table.quotedDatabaseIdentifier) (\(columns))
                        SELECT \(columns) FROM lumenBackup.\(table.quotedDatabaseIdentifier)
                        """)
                }
                return .commit
            }
        }

        // Файлы с теми же именами уже совпадают: имена уникальные, файлы не меняются после добавления.
        var fileCount = 0
        if let filesFolder = prepared.filesFolder {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: attachments.folder, withIntermediateDirectories: true)
            let files = (try? fileManager.contentsOfDirectory(at: filesFolder, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                let target = attachments.url(for: file.lastPathComponent)
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.copyItem(at: file, to: target)
                }
                fileCount += 1
            }
        }

        let counts = try await reader.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page WHERE deletedAt IS NULL") ?? 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source WHERE deletedAt IS NULL") ?? 0
            )
        }
        return BackupSummary(
            createdAt: prepared.manifest?.summary.createdAt ?? Date(),
            pageCount: counts.0,
            sourceCount: counts.1,
            fileCount: fileCount,
            includesFiles: prepared.filesFolder != nil
        )
    }

    /// Таблицы с данными: всё, кроме служебных таблиц SQLite, GRDB, синхронизации
    /// и внутренних таблиц полнотекстового индекса (сам индекс переносится как обычная таблица).
    static func restorableTables(_ db: Database) throws -> [String] {
        let rows = try Row.fetchAll(db, sql: "SELECT name, sql FROM main.sqlite_master WHERE type = 'table'")
        let tables = rows.map { (name: $0["name"] as String, sql: ($0["sql"] as String?) ?? "") }
        let virtual = tables.filter { $0.sql.uppercased().hasPrefix("CREATE VIRTUAL TABLE") }.map(\.name)
        return tables.map(\.name).filter { name in
            !name.hasPrefix("sqlite_")
                && !name.hasPrefix("grdb_")
                && !name.hasPrefix("sync")
                && !virtual.contains { name.hasPrefix("\($0)_") }
        }
    }
}

// MARK: - Автоматические копии

extension AppDatabase {
    /// Копирует базу перед миграциями, если они есть. Новая пустая база не копируется.
    static func copyBeforeMigrating(_ writer: any DatabaseWriter, into folder: URL) throws {
        let needsCopy = try writer.read { db in
            guard try db.tableExists("grdb_migrations") else { return false }
            return try !migrator.hasCompletedMigrations(db)
        }
        guard needsCopy else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = automaticBackupURL(in: folder, kind: .beforeUpdate, fileExtension: "sqlite")
        try writer.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [url.path])
        }
        pruneAutomaticBackups(in: folder, kind: .beforeUpdate)
    }

    /// Автоматические копии в папке, новые первыми.
    public static func automaticBackups(in folder: URL) -> [AutomaticBackup] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.compactMap { url -> AutomaticBackup? in
            let name = url.lastPathComponent
            guard let kind = [AutomaticBackup.Kind.beforeUpdate, .beforeRestore].first(where: {
                name.hasPrefix($0.rawValue + " ")
            }) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return AutomaticBackup(url: url, kind: kind, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    /// Автоматические копии рядом с основной базой приложения.
    public static func defaultAutomaticBackups() -> [AutomaticBackup] {
        guard let folder = try? defaultFolder() else { return [] }
        return automaticBackups(in: folder.appendingPathComponent("Backups", isDirectory: true))
    }

    /// Оставляет несколько последних копий одного вида, чтобы они не занимали место бесконечно.
    static func pruneAutomaticBackups(in folder: URL, kind: AutomaticBackup.Kind, keep: Int = 5) {
        for old in automaticBackups(in: folder).filter({ $0.kind == kind }).dropFirst(keep) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    /// Новое имя автоматической копии. Две копии в одну секунду не затирают друг друга.
    static func automaticBackupURL(in folder: URL, kind: AutomaticBackup.Kind, fileExtension: String) -> URL {
        let base = "\(kind.rawValue) \(stamp(Date()))"
        var url = folder.appendingPathComponent("\(base).\(fileExtension)")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(index).\(fileExtension)")
            index += 1
        }
        return url
    }

    static func stamp(_ date: Date, format: String = "yyyy-MM-dd HH-mm-ss") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
