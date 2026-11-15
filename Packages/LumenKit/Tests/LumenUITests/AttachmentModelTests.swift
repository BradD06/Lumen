import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct AttachmentModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func openBlock(_ type: BlockType) async throws -> (PageEditorModel, UUID) {
        let page = try await db.createQuickNote("Страница\nа")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        let id = model.blocks[0].id
        model.setType(id, type)
        return (model, id)
    }

    @Test func fileIsCopiedIntoAttachments() async throws {
        let (model, id) = try await openBlock(.file)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("Конспект \(UUID().uuidString).txt")
        try Data("привет".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        await model.attachFile(id, from: source)
        let block = try #require(model.findBlock(id))
        #expect(block.content.file?.name == source.lastPathComponent)
        #expect(block.content.file?.size == 12)
        let url = try #require(model.attachmentURL(of: block))
        #expect(try Data(contentsOf: url) == Data("привет".utf8))
        #expect(url.pathExtension == "txt")

        model.removeAttachment(id)
        #expect(model.findBlock(id)?.content.attachment == nil)
        model.undo()
        #expect(model.findBlock(id)?.content.file?.name == source.lastPathComponent)
    }

    @Test func bookmarkNeedsAnAddress() async throws {
        let (model, id) = try await openBlock(.bookmark)
        #expect(model.findBlock(id)?.type == .bookmark)
        #expect(model.focusRequest == nil, "Курсор в поле адреса закладки")
        let added = await model.setBookmark(id, address: "просто текст")
        #expect(!added)
        #expect(model.findBlock(id)?.content.bookmark == nil)
    }

    @Test func blockTypesAcceptTheirFiles() {
        let pdf = URL(fileURLWithPath: "/tmp/a.pdf")
        let movie = URL(fileURLWithPath: "/tmp/a.mov")
        #expect(PageEditorModel.acceptsFile(pdf, for: .pdf))
        #expect(!PageEditorModel.acceptsFile(movie, for: .pdf))
        #expect(PageEditorModel.acceptsFile(movie, for: .video))
        #expect(PageEditorModel.acceptsFile(movie, for: .file))
        #expect(!PageEditorModel.acceptsFile(pdf, for: .audio))
    }
}
