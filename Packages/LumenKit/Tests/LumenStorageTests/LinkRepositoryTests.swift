import Foundation
import Testing
import LumenCore
@testable import LumenStorage

struct LinkRepositoryTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func backlinks(_ pageId: UUID) async throws -> [UUID] {
        try await db.reader.read { try PageLinksSnapshot.fetch($0, pageId: pageId) }.backlinks.map(\.id)
    }

    @Test func linkBlockCreatesBacklink() async throws {
        let target = try await db.createPage(title: "Матанализ")
        let source = try await db.createPage(title: "План на неделю")
        let link = Block(pageId: source.id, type: .page, content: BlockContent(pageId: target.id), sortKey: "V")
        try await db.saveBlock(link)

        #expect(try await backlinks(target.id) == [source.id])
        #expect(try await backlinks(source.id).isEmpty)

        // Блок превратили обратно в текст: ссылка пропадает.
        var plain = link
        plain.type = .paragraph
        plain.content = BlockContent(text: "просто текст")
        try await db.saveBlock(plain)
        #expect(try await backlinks(target.id).isEmpty)
    }

    @Test func deletedBlockOrTrashedPageHasNoBacklink() async throws {
        let target = try await db.createPage(title: "Цель")
        let source = try await db.createPage(title: "Источник")
        let link = Block(pageId: source.id, type: .page, content: BlockContent(pageId: target.id), sortKey: "V")
        try await db.saveBlock(link)

        try await db.trashPage(source.id)
        #expect(try await backlinks(target.id).isEmpty)
        try await db.restorePage(source.id)
        #expect(try await backlinks(target.id) == [source.id])

        try await db.deleteBlock(link.id)
        #expect(try await backlinks(target.id).isEmpty)
    }

    @Test func linkToMissingPageIsIgnored() async throws {
        let source = try await db.createPage(title: "Источник")
        let link = Block(pageId: source.id, type: .page, content: BlockContent(pageId: UUID()), sortKey: "V")
        try await db.saveBlock(link)
        #expect(try await db.blocks(of: source.id).contains { $0.id == link.id })
    }

    @Test func backgroundIsSaved() async throws {
        let page = try await db.createPage(title: "Фон")
        let background = PageBackground.wallpaper(Wallpaper(palette: 1, layers: 4, hasSun: true, seed: 99))
        try await db.setBackground(page.id, background: background)
        #expect(try await db.page(page.id)?.pageBackground == background)
        try await db.setBackground(page.id, background: nil)
        #expect(try await db.page(page.id)?.background == nil)
    }

    @Test func coverIsSaved() async throws {
        let page = try await db.createPage(title: "С обложкой")
        try await db.setCover(page.id, cover: .gradient(2))
        #expect(try await db.page(page.id)?.pageCover == .gradient(2))
        try await db.setCover(page.id, cover: nil)
        #expect(try await db.page(page.id)?.cover == nil)
    }

    @Test func attachmentsRoundTrip() throws {
        let data = Data([1, 2, 3, 4])
        let name = try db.attachments.save(data, fileExtension: "PNG")
        #expect(name.hasSuffix(".png"))
        #expect(db.attachments.data(for: name) == data)
        #expect(db.attachments.data(for: "../\(name)") == data, "Путь за пределы папки отбрасывается")
    }
}
