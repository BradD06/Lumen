import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct YouTubeModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func openEmptyParagraph() async throws -> (PageEditorModel, UUID) {
        let page = try await db.createQuickNote("Страница\nа")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let id = model.blocks[0].id
        model.updateText(id, to: "")
        return (model, id)
    }

    @Test func pastedLinkBecomesVideo() async throws {
        let (model, id) = try await openEmptyParagraph()
        model.updateMarkup(id, to: "https://youtu.be/dQw4w9WgXcQ?t=42")

        let block = try #require(model.findBlock(id))
        #expect(block.type == .video)
        #expect(block.text.isEmpty)
        #expect(block.content.attachment == nil)
        #expect(block.content.bookmark?.url == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s")
        // Курсор ждёт в новом абзаце под роликом.
        let next = try #require(model.focusRequest)
        #expect(next != id)
        #expect(model.findBlock(next)?.type == .paragraph)

        // ⌘Z возвращает ссылку обычным текстом.
        model.undo()
        #expect(model.findBlock(id)?.type == .paragraph)
        #expect(model.findBlock(id)?.text == "https://youtu.be/dQw4w9WgXcQ?t=42")
        #expect(model.findBlock(next) == nil)
    }

    @Test func otherTextStaysText() async throws {
        let (model, id) = try await openEmptyParagraph()
        model.updateMarkup(id, to: "https://example.com/watch?v=dQw4w9WgXcQ")
        #expect(model.findBlock(id)?.type == .paragraph)

        // Ссылка внутри уже написанного текста тоже остаётся текстом.
        model.updateText(id, to: "Смотри")
        model.updateMarkup(id, to: "Смотри https://youtu.be/dQw4w9WgXcQ")
        #expect(model.findBlock(id)?.type == .paragraph)
    }

    @Test func videoBlockTakesLinkInsteadOfFile() async throws {
        let (model, id) = try await openEmptyParagraph()
        model.setType(id, .video)
        #expect(!model.setVideoLink(id, address: "просто текст"))
        #expect(model.findBlock(id)?.content.bookmark == nil)

        #expect(model.setVideoLink(id, address: "youtube.com/shorts/abcdefghijk"))
        let block = try #require(model.findBlock(id))
        #expect(block.content.bookmark?.url == "https://www.youtube.com/shorts/abcdefghijk")
        #expect(block.content.bookmark?.siteName == "YouTube")

        // «Другое видео» снова показывает выбор файла или ссылки.
        model.removeAttachment(id)
        #expect(model.findBlock(id)?.content.bookmark == nil)
        model.undo()
        #expect(model.findBlock(id)?.content.bookmark != nil)
    }
}
