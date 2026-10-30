#if os(iOS)
import UIKit

extension Notification.Name {
    /// Стирание в пустом текстовом поле. Объект уведомления — само поле.
    static let lumenBackspaceInEmptyField = Notification.Name("lumen.backspaceInEmptyField")
}

/// Экранная клавиатура iPhone в пустом поле ничего не меняет и SwiftUI об этом не узнаёт:
/// `onKeyPress` ловит только аппаратную клавиатуру. Поэтому `deleteBackward` полей подменяется
/// и сообщает о стирании в пустом поле, а редактор удаляет пустой блок (PageEditorView).
@MainActor
enum EmptyBackspace {
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        exchange(UITextView.self, #selector(UITextView.deleteBackward), #selector(UITextView.lumen_deleteBackward))
        exchange(UITextField.self, #selector(UITextField.deleteBackward), #selector(UITextField.lumen_deleteBackward))
    }

    private static func exchange(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(type, original),
              let replacementMethod = class_getInstanceMethod(type, replacement) else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

extension UITextView {
    @objc fileprivate func lumen_deleteBackward() {
        if text.isEmpty, markedTextRange == nil {
            NotificationCenter.default.post(name: .lumenBackspaceInEmptyField, object: self)
        }
        // После обмена реализаций это вызов настоящего deleteBackward.
        lumen_deleteBackward()
    }
}

extension UITextField {
    @objc fileprivate func lumen_deleteBackward() {
        if text?.isEmpty ?? true, markedTextRange == nil {
            NotificationCenter.default.post(name: .lumenBackspaceInEmptyField, object: self)
        }
        lumen_deleteBackward()
    }
}
#endif
