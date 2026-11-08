#if os(macOS)
import AppKit

/// Клавиши читалки на Mac.
/// Стрелки ← → ↑ ↓ листают книгу, когда курсор не стоит в тексте (например, в заметке рядом).
/// ⌥⌘→ переводит курсор в заметки сбоку от книги, ⌥⌘← возвращает клавиши книге.
@MainActor
final class ReaderKeys {
    enum Action: Equatable {
        case turn(forward: Bool)
        case focusNotes
        case focusBook
    }

    /// Книга в активной панели: в неактивной стрелки не трогаем.
    var isActive = true
    /// Заметки открыты сбоку от книги внутри читалки (не во второй панели окна).
    var hasNotesBeside = false
    /// Окно разделено на две панели: тогда ⌥⌘← → переключают панели, это делает окно.
    var isSplitScreen = false

    private var monitor: Any?

    func install(model: ReaderModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak model] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let model else { return false }
                return self.handle(event, model: model)
            }
            return handled ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent, model: ReaderModel) -> Bool {
        guard isActive, let action = Self.action(keyCode: event.keyCode, flags: event.modifierFlags) else { return false }
        // Только главное окно без листа поверх: в поповерах и диалогах стрелки свои.
        guard let window = event.window, window === NSApp.mainWindow, window.attachedSheet == nil else { return false }
        switch action {
        case .turn(let forward):
            guard !Self.responderUsesArrows(window.firstResponder) else { return false }
            model.turnPage(forward: forward)
            return true
        case .focusNotes:
            guard hasNotesBeside, !isSplitScreen, let notes = model.notes else { return false }
            notes.focusAgain()
            return true
        case .focusBook:
            guard hasNotesBeside, !isSplitScreen else { return false }
            window.makeFirstResponder(nil)
            return true
        }
    }

    /// Текст, списки и таблицы сами ходят стрелками: им клавиши оставляем.
    private static func responderUsesArrows(_ responder: NSResponder?) -> Bool {
        if let text = responder as? NSTextView { return text.isEditable }
        return responder is NSTableView || responder is NSCollectionView || responder is NSTextField
    }

    /// Что значит клавиша: стрелки без модификаторов листают, ⌥⌘ со стрелкой переводят курсор.
    nonisolated static func action(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Action? {
        let modifiers = flags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        // 123 ←, 124 →, 125 ↓, 126 ↑.
        if modifiers.isEmpty {
            switch keyCode {
            case 124, 125: return .turn(forward: true)
            case 123, 126: return .turn(forward: false)
            default: return nil
            }
        }
        if modifiers == [.command, .option] {
            switch keyCode {
            case 124: return .focusNotes
            case 123: return .focusBook
            default: return nil
            }
        }
        return nil
    }
}
#endif
