import Foundation
import GRDB
import Testing
import LumenCore
@testable import LumenStorage

/// Два устройства без iCloud: записи из очереди одного передаются прямо во второе,
/// так же, как их передал бы движок синхронизации.
struct SyncRepositoryTests {
    let phone: AppDatabase
    let mac: AppDatabase

    init() throws {
        phone = try AppDatabase.inMemory()
        mac = try AppDatabase.inMemory()
    }

    /// Отправляет всё из очереди `from` в `to`. `reversed` перемешивает порядок, как бывает в сети.
    private func send(from: AppDatabase, to: AppDatabase, reversed: Bool = false) async throws {
        var saved: [SyncRecord] = []
        var deleted: [SyncRecordID] = []
        for change in try await from.pendingSyncChanges() {
            let id = try #require(change.id)
            if change.isDeletion {
                deleted.append(id)
            } else if let found = try await from.syncRecord(for: id) {
                saved.append(found.record)
            }
            try await from.markSynced(id, version: change.version)
        }
        try await to.applyRemoteChanges(saved: reversed ? saved.reversed() : saved, deleted: deleted)
    }

    private func block(_ pageId: UUID, _ text: String, key: String = "m") -> Block {
        Block(pageId: pageId, type: .paragraph, content: BlockContent(runs: [TextRun(text)]), sortKey: key)
    }

    @Test func everyLocalChangeIsLogged() async throws {
        let page = try await phone.createPage(title: "Конспект")
        let changes = try await phone.pendingSyncChanges()
        #expect(changes.contains { $0.tableName == "page" && $0.recordId == page.id && !$0.isDeletion })
        #expect(changes.contains { $0.tableName == "block" })

        let first = try #require(changes.first { $0.recordId == page.id })
        try await phone.renamePage(page.id, title: "Конспект 2")
        let renamed = try #require(try await phone.pendingSyncChanges().first { $0.recordId == page.id })
        #expect(renamed.version > first.version)
    }

    @Test func recordsArriveInAnyOrder() async throws {
        let folder = try await phone.createFolder(name: "Учёба")
        let page = try await phone.createPage(title: "Лекция", folderId: folder.id)
        let child = try await phone.createPage(title: "Подстраница", parentId: page.id)
        try await phone.saveBlock(block(page.id, "Теорема Пифагора"))

        // Блоки и подстраница приходят раньше своих страниц и папки.
        try await send(from: phone, to: mac, reversed: true)

        let received = try #require(try await mac.page(page.id))
        #expect(received.title == "Лекция")
        #expect(received.folderId == folder.id)
        #expect(try await mac.page(child.id)?.parentId == page.id)
        #expect(try await mac.blocks(of: page.id).map(\.text).contains("Теорема Пифагора"))
        #expect(try await mac.search("Пифагора").map(\.pageId) == [page.id])

        // Принятое не уходит обратно, а очередь отправителя пуста.
        #expect(try await mac.pendingSyncChanges().isEmpty)
        #expect(try await phone.pendingSyncChanges().isEmpty)
        #expect(try await mac.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM syncIncoming") } == 0)
    }

    @Test func deletionsAndClearedFieldsTravel() async throws {
        let page = try await phone.createPage(title: "Заметка")
        try await phone.setIcon(page.id, icon: "📘")
        let extra = block(page.id, "Удалю", key: "z")
        try await phone.saveBlock(extra)
        try await send(from: phone, to: mac)
        #expect(try await mac.page(page.id)?.icon == "📘")

        try await phone.setIcon(page.id, icon: nil)
        try await phone.deleteBlock(extra.id)
        try await send(from: phone, to: mac)

        #expect(try await mac.page(page.id)?.icon == nil)
        #expect(!(try await mac.blocks(of: page.id).map(\.id).contains(extra.id)))
    }

    @Test func newerLocalEditWins() async throws {
        let page = try await phone.createPage(title: "Черновик")
        try await send(from: phone, to: mac)
        let stale = try #require(try await phone.syncRecord(for: SyncRecordID(table: .page, id: page.id))).record

        try await Task.sleep(for: .milliseconds(20))
        try await mac.renamePage(page.id, title: "Чистовик")
        try await mac.applyRemoteChanges(saved: [stale], deleted: [])

        #expect(try await mac.page(page.id)?.title == "Чистовик")
        #expect(try await mac.pendingSyncChanges().contains { $0.recordId == page.id })
    }

    @Test func editAfterSendingStaysQueued() async throws {
        let page = try await phone.createPage(title: "Раз")
        let id = SyncRecordID(table: .page, id: page.id)
        let sentVersion = try #require(try await phone.syncRecord(for: id)?.version)
        try await phone.renamePage(page.id, title: "Два")
        try await phone.markSynced(id, version: sentVersion)
        #expect(try await phone.pendingSyncChanges().contains { $0.recordId == page.id })
    }

    @Test func recordNamesRoundTrip() {
        let id = SyncRecordID(table: .highlight, id: UUID())
        #expect(SyncRecordID(recordName: id.recordName) == id)
        #expect(SyncRecordID(recordName: "nope") == nil)
        #expect(SyncTable(recordType: "Block") == .block)
    }

    @Test func enqueueAllCoversExistingRows() async throws {
        _ = try await phone.createPage(title: "Старая")
        try await phone.writer.write { try $0.execute(sql: "DELETE FROM syncChange") }
        try await phone.enqueueAllForSync()
        let tables = Set(try await phone.pendingSyncChanges().map(\.tableName))
        #expect(tables == ["page", "block"])
    }
}
