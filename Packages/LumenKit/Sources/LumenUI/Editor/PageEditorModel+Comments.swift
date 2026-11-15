import Foundation
import LumenCore

/// Комментарии к блокам: добавить, поправить, отметить решённым, удалить.
/// Каждая правка отдельный шаг отмены.
extension PageEditorModel {
    func comments(of id: UUID) -> [BlockComment] {
        findBlock(id)?.content.comments ?? []
    }

    @discardableResult
    func addComment(to id: UUID, text: String, now: Date = Date()) -> BlockComment? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, findBlock(id) != nil else { return nil }
        let comment = BlockComment(text: text, createdAt: now)
        changeComments(id) { $0.append(comment) }
        return comment
    }

    func editComment(_ commentId: UUID, in id: UUID, text: String, now: Date = Date()) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let old = comments(of: id).first(where: { $0.id == commentId }), old.text != text else { return }
        changeComments(id) { comments in
            guard let index = comments.firstIndex(where: { $0.id == commentId }) else { return }
            comments[index].text = text
            comments[index].editedAt = now
        }
    }

    func setCommentResolved(_ commentId: UUID, in id: UUID, _ resolved: Bool) {
        guard comments(of: id).contains(where: { $0.id == commentId && $0.isResolved != resolved }) else { return }
        changeComments(id) { comments in
            guard let index = comments.firstIndex(where: { $0.id == commentId }) else { return }
            comments[index].isResolved = resolved
        }
    }

    func deleteComment(_ commentId: UUID, in id: UUID) {
        guard comments(of: id).contains(where: { $0.id == commentId }) else { return }
        changeComments(id) { $0.removeAll { $0.id == commentId } }
    }

    /// Блоки страницы с комментариями, по порядку документа: для списка всех комментариев.
    var commentedBlocks: [Block] {
        blocks.filter { !($0.content.comments ?? []).isEmpty }
    }

    private func changeComments(_ id: UUID, _ change: (inout [BlockComment]) -> Void) {
        recordUndo()
        update(id) { block in
            var comments = block.content.comments ?? []
            change(&comments)
            block.content.comments = comments.isEmpty ? nil : comments
        }
    }
}
