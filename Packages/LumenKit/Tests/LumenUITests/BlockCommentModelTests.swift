import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct BlockCommentModelTests {
    let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    private func open() async throws -> (PageEditorModel, UUID) {
        let page = try await db.createQuickNote("Страница\nТеорема Ферма")
        let model = PageEditorModel(database: db, pageId: page.id)
        await model.load()
        return (model, model.blocks[0].id)
    }

    @Test func commentsAreAddedEditedAndSaved() async throws {
        let (model, id) = try await open()
        #expect(model.addComment(to: id, text: "   ") == nil, "Пустой комментарий не добавляется")
        let first = try #require(model.addComment(to: id, text: " Проверить доказательство "))
        model.addComment(to: id, text: "Найти источник")
        #expect(model.comments(of: id).map(\.text) == ["Проверить доказательство", "Найти источник"])

        model.editComment(first.id, in: id, text: "Проверить вывод")
        #expect(model.comments(of: id).first?.text == "Проверить вывод")
        #expect(model.comments(of: id).first?.editedAt != nil)

        model.setCommentResolved(first.id, in: id, true)
        #expect(model.findBlock(id)?.content.openComments.map(\.text) == ["Найти источник"])
        #expect(model.commentedBlocks.map(\.id) == [id])

        await model.flush()
        let saved = try await db.blocks(of: model.pageId).first { $0.id == id }
        #expect(saved?.content.comments?.count == 2)
        #expect(saved?.content.comments?.first?.isResolved == true)
        let found = try await db.search("источник")
        #expect(found.contains { $0.pageId == model.pageId })
    }

    @Test func deletingAndUndo() async throws {
        let (model, id) = try await open()
        let comment = try #require(model.addComment(to: id, text: "Вопрос"))
        model.deleteComment(comment.id, in: id)
        #expect(model.findBlock(id)?.content.comments == nil, "Без комментариев поле пустое")
        model.undo()
        #expect(model.comments(of: id).map(\.id) == [comment.id])
        model.undo()
        #expect(model.comments(of: id).isEmpty)
    }
}
