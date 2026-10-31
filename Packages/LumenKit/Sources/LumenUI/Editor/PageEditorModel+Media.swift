import Foundation
import LumenCore
import LumenStorage

/// Выписки из книг, ссылки на места в книге, картинки, обложка и фон.
extension PageEditorModel {
    // MARK: Выписки из книг

    func source(_ id: UUID?) -> Source? {
        guard let id else { return nil }
        return links.sources.first { $0.id == id }
    }

    /// Книга, к которой это страница заметок.
    var notesSource: Source? { source(page?.sourceId) }

    func openExcerpt(_ reference: ExcerptReference) {
        guard reference.isPlace, let locator = reference.locator else {
            openSource(reference.sourceId, highlight: reference.highlightId)
            return
        }
        if openPlaceInReader?(reference) == true { return }
        // Другая книга откроется там, где остановились, поэтому место из ссылки сначала становится местом чтения.
        Task {
            await flush()
            try? await database.setReadingLocator(reference.sourceId, locator: locator)
            openSourceRequest = SourceRequest(sourceId: reference.sourceId, highlightId: nil)
        }
    }

    func openSource(_ sourceId: UUID, highlight: UUID? = nil) {
        Task {
            await flush()
            openSourceRequest = SourceRequest(sourceId: sourceId, highlightId: highlight)
        }
    }

    /// Ссылка на место в книге в конец страницы. Вставляется как выписка без текста.
    func appendPlaceLink(_ reference: ExcerptReference) {
        appendExcerpt(text: "", reference: reference)
    }

    /// Вставляет выписку в конец страницы, а после неё пустой абзац, чтобы сразу дописать мысль.
    /// Если страница пустая, выписка встаёт на место пустого абзаца.
    func appendExcerpt(text: String, reference: ExcerptReference) {
        recordUndo()
        let content = BlockContent(runs: [TextRun(text)], excerpt: reference)
        let topLevel = children(of: nil)
        if topLevel.count == 1, let only = topLevel.first, only.type == .paragraph, only.text.isEmpty {
            update(only.id) {
                $0.type = .excerpt
                $0.content = content
            }
            insertBlock(in: nil, after: only.id, type: .paragraph)
            return
        }
        // Пустой абзац в конце остаётся последним: выписка встаёт перед ним.
        if let last = topLevel.last, last.type == .paragraph, last.text.isEmpty, children(of: last.id).isEmpty {
            let previous = topLevel.dropLast().last
            insertBlock(in: nil, after: previous?.id, type: .excerpt, content: content)
        } else {
            let excerpt = insertBlock(in: nil, after: topLevel.last?.id, type: .excerpt, content: content)
            insertBlock(in: nil, after: excerpt.id, type: .paragraph)
        }
    }

    // MARK: Картинки

    /// Сохраняет картинку во вложения и показывает её в блоке.
    func setImage(_ id: UUID, data: Data, fileExtension: String?) {
        guard findBlock(id) != nil else { return }
        do {
            let name = try database.attachments.save(data, fileExtension: fileExtension)
            recordUndo()
            update(id) { $0.content.attachment = name }
        } catch {
            NoticeCenter.shared.report("Не удалось сохранить картинку", error)
        }
    }

    func setCoverImage(data: Data) {
        do {
            setCover(.image(try database.attachments.save(data)))
        } catch {
            NoticeCenter.shared.report("Не удалось сохранить обложку", error)
        }
    }

    func setBackgroundImage(data: Data) {
        do {
            setBackground(.image(try database.attachments.save(data)))
        } catch {
            NoticeCenter.shared.report("Не удалось сохранить фон", error)
        }
    }
}
