import Foundation
import GRDB
import Testing
import LumenCore
@testable import LumenStorage

/// Два устройства и общая папка на диске вместо iCloud Drive: облако только возит файлы,
/// так что обычная временная папка ведёт себя так же.
struct FolderSyncTests {
    let folder: URL
    let phone: AppDatabase
    let mac: AppDatabase
    let phoneSync: FolderSyncEngine
    let macSync: FolderSyncEngine

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumenFolderSync-\(UUID().uuidString)", isDirectory: true)
        phone = try AppDatabase.inMemory()
        mac = try AppDatabase.inMemory()
        let root = FolderSyncEngine.dataFolder(in: folder)
        phoneSync = FolderSyncEngine(database: phone, root: root, deviceId: "phone", deviceName: "iPhone")
        macSync = FolderSyncEngine(database: mac, root: root, deviceId: "mac", deviceName: "Mac")
    }

    private func block(_ pageId: UUID, _ text: String, key: String = "m", attachment: String? = nil) -> Block {
        Block(pageId: pageId, type: .paragraph, content: BlockContent(runs: [TextRun(text)], attachment: attachment), sortKey: key)
    }

    @Test func notesTravelThroughTheFolder() async throws {
        let notes = try await phone.createFolder(name: "Учёба")
        let page = try await phone.createPage(title: "Лекция", folderId: notes.id)
        try await phone.saveBlock(block(page.id, "Теорема Пифагора"))

        let sent = try await phoneSync.sync()
        #expect(sent.sent > 0)
        let received = try await macSync.sync()
        #expect(received.received > 0)
        #expect(received.otherDevices.map(\.name) == ["iPhone"])

        #expect(try await mac.page(page.id)?.folderId == notes.id)
        #expect(try await mac.blocks(of: page.id).map(\.text).contains("Теорема Пифагора"))
        #expect(try await mac.search("Пифагора").map(\.pageId) == [page.id])

        // Принятое не уезжает обратно, и повторный круг ничего не делает.
        #expect(received.sent == 0)
        let again = try await phoneSync.sync()
        #expect(again.sent == 0 && again.received == 0)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Lumen Sync/format.json").path))
    }

    @Test func laterEditWinsOnBothDevices() async throws {
        let page = try await phone.createPage(title: "Черновик")
        _ = try await phoneSync.sync()
        _ = try await macSync.sync()

        try await phone.renamePage(page.id, title: "С телефона")
        try await Task.sleep(for: .milliseconds(20))
        try await mac.renamePage(page.id, title: "С ноутбука")

        // Ноутбук принимает правку телефона раньше, чем отправляет свою: его правка новее и остаётся.
        _ = try await phoneSync.sync()
        _ = try await macSync.sync()
        _ = try await phoneSync.sync()

        #expect(try await mac.page(page.id)?.title == "С ноутбука")
        #expect(try await phone.page(page.id)?.title == "С ноутбука")
    }

    @Test func deletionIsNotUndoneByAnOldCopy() async throws {
        let page = try await phone.createPage(title: "Удалю")
        _ = try await phoneSync.sync()
        _ = try await macSync.sync()
        let stale = try #require(try await mac.folderSyncSnapshot().first { $0.id == SyncRecordID(table: .page, id: page.id) })

        try await Task.sleep(for: .milliseconds(20))
        try await mac.trashPage(page.id)
        try await mac.deleteForever(.page(page.id))
        _ = try await macSync.sync()
        _ = try await phoneSync.sync()
        #expect(try await phone.page(page.id) == nil)

        // Старая копия страницы (например из сжатой копии другого устройства) её не воскрешает.
        #expect(try await phone.applyFolderEntries([stale]) == 0)
        #expect(try await phone.page(page.id) == nil)
    }

    @Test func picturesTravelWithTheirNotes() async throws {
        let page = try await phone.createPage(title: "С картинкой")
        let name = try phone.attachments.save(Data("картинка".utf8), fileExtension: "png")
        try await phone.saveBlock(block(page.id, "", key: "n", attachment: name))
        // Файл, на который никто не ссылается, в папку не едет.
        _ = try phone.attachments.save(Data("мусор".utf8))

        let sent = try await phoneSync.sync()
        #expect(sent.filesSent == 1)
        let received = try await macSync.sync()
        #expect(received.filesReceived == 1)
        #expect(mac.attachments.data(for: name) == Data("картинка".utf8))
    }

    @Test func oldChangesAreCompacted() async throws {
        let root = FolderSyncEngine.dataFolder(in: folder)
        let compacting = FolderSyncEngine(database: phone, root: root, deviceId: "phone", deviceName: "iPhone", compactAfter: 2)
        var pages: [UUID] = []
        for index in 0 ..< 4 {
            pages.append(try await phone.createPage(title: "Страница \(index)").id)
            _ = try await compacting.sync()
        }
        let deviceFolder = root.appendingPathComponent("devices/phone")
        let snapshots = FolderFiles.list(deviceFolder).filter { $0.hasPrefix("snapshot-") }
        #expect(snapshots.count == 1)
        #expect(FolderFiles.list(deviceFolder.appendingPathComponent("changes")).count <= 2)

        // Новое устройство читает сжатую копию и всё, что после неё.
        let tablet = try AppDatabase.inMemory()
        _ = try await FolderSyncEngine(database: tablet, root: root, deviceId: "tablet", deviceName: "iPad").sync()
        for id in pages {
            #expect(try await tablet.page(id) != nil)
        }
    }

    @Test func readingTimeIsLogged() async throws {
        // Время чтения теперь в журнале правок и с часами, как и остальные таблицы.
        let tables = try await phone.reader.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'sync_readingSession_%'")
        }
        #expect(Set(tables) == [
            "sync_readingSession_insert", "sync_readingSession_update", "sync_readingSession_delete",
            "sync_readingSession_clock_insert", "sync_readingSession_clock_update", "sync_readingSession_clock_delete",
        ])
    }

    @Test func entriesAreReadableJSON() throws {
        let id = SyncRecordID(table: .page, id: UUID())
        let entry = FolderSyncEntry(id: id, changedAt: "2026-11-08 08:31:02.123", fields: [
            "title": .text("Лекция"),
            "canvasX": .double(12.5),
            "isFavorite": .integer(1),
            "icon": .null,
            "parentId": .data(Data([1, 2, 3])),
        ])
        let json = try JSONEncoder().encode(entry)
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.contains("\"record\":\"page.\(id.id.uuidString)\""))
        #expect(try JSONDecoder().decode(FolderSyncEntry.self, from: json) == entry)

        let deleted = FolderSyncEntry(id: id, changedAt: "2026-11-08 08:31:02.123", fields: nil)
        let deletedJSON = try JSONEncoder().encode(deleted)
        #expect(String(decoding: deletedJSON, as: UTF8.self).contains("\"deleted\":true"))
        #expect(try JSONDecoder().decode(FolderSyncEntry.self, from: deletedJSON) == deleted)
    }

    @Test func pickedFolderGetsOwnSubfolder() {
        let drive = URL(fileURLWithPath: "/tmp/iCloud Drive", isDirectory: true)
        #expect(FolderSyncEngine.dataFolder(in: drive).lastPathComponent == "Lumen Sync")
        let ready = drive.appendingPathComponent("Lumen Sync", isDirectory: true)
        #expect(FolderSyncEngine.dataFolder(in: ready) == ready)
    }
}
