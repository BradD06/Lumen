import Foundation

/// Открытые сейчас экраны одного вида, по id того, что в них открыто. Ссылки слабые:
/// закрытый экран сам пропадает из списка.
@MainActor
final class OpenScreens<Model: AnyObject> {
    private struct Entry {
        weak var model: Model?
    }

    private var entries: [UUID: Entry] = [:]

    func register(_ model: Model, id: UUID) {
        entries = entries.filter { $0.value.model != nil }
        entries[id] = Entry(model: model)
    }

    func unregister(_ model: Model, id: UUID) {
        if entries[id]?.model === model {
            entries[id] = nil
        }
    }

    func model(for id: UUID) -> Model? {
        entries[id]?.model
    }
}

/// Редакторы страниц, открытые сейчас в панелях окна. По ним читалка находит заметку,
/// открытую рядом с книгой, и вставляет выписку прямо в её редактор: так выписка сразу
/// видна, а редактор не перезапишет её своей копией страницы при сохранении.
@MainActor
enum OpenPageEditors {
    static let shared = OpenScreens<PageEditorModel>()
}

/// Книги, открытые сейчас в панелях окна. Ссылка на место в заметке прокручивает уже
/// открытую книгу, а не открывает её заново.
@MainActor
enum OpenReaders {
    static let shared = OpenScreens<ReaderModel>()
}
