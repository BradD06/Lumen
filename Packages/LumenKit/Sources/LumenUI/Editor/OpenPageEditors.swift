import Foundation

/// Редакторы страниц, открытые сейчас в панелях окна. По ним читалка находит заметку,
/// открытую рядом с книгой, и вставляет выписку прямо в её редактор: так выписка сразу
/// видна, а редактор не перезапишет её своей копией страницы при сохранении.
@MainActor
final class OpenPageEditors {
    static let shared = OpenPageEditors()

    private struct Entry {
        weak var model: PageEditorModel?
    }

    private var entries: [UUID: Entry] = [:]

    func register(_ model: PageEditorModel) {
        entries = entries.filter { $0.value.model != nil }
        entries[model.pageId] = Entry(model: model)
    }

    func unregister(_ model: PageEditorModel) {
        if entries[model.pageId]?.model === model {
            entries[model.pageId] = nil
        }
    }

    func model(for pageId: UUID) -> PageEditorModel? {
        entries[pageId]?.model
    }
}
