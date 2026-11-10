import LumenCore
import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Плавающая панель над выделенным текстом: жирный, курсив, подчёркнутый, зачёркнутый, код,
/// ссылка, цвет и тип блока. На Mac висит над блоком, на iPhone и iPad стоит над клавиатурой.
struct FormatBar: View {
    let model: PageEditorModel
    let blockId: UUID
    /// Выделение, по которому подсвечены кнопки. На iPhone и iPad его нет: кнопки берут
    /// выделение из поля в момент нажатия.
    var selection: TextSelectionInfo?
    /// Палитру цвета блока открывает сам блок.
    var onColor: (() -> Void)?

    @State private var isLinkEditorShown = false
    @State private var linkDraft = ""
    /// Выделение на момент нажатия «Ссылка»: пока открыто окно адреса, поле теряет фокус.
    @State private var linkTarget: TextSelectionInfo?
    @Environment(\.lumenTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let active = selection.map(model.marks(in:)) ?? []
        let link = selection.flatMap(model.link(in:))
        HStack(spacing: 2) {
            ForEach([FormatAction.bold, .italic, .underline, .strikethrough, .code]) { action in
                button(action.systemImage, title: action.title, shortcut: action.shortcut, isOn: action.mark.map(active.contains) ?? false) {
                    TextFormatting.perform(action, model: model, blockId: blockId)
                }
            }
            separator
            button("link", title: link == nil ? "Ссылка" : "Изменить ссылку", shortcut: nil, isOn: link != nil) {
                linkTarget = TextFormatting.currentSelection(blockId: blockId) ?? model.wholeText(of: blockId)
                linkDraft = linkTarget.flatMap(model.link(in:)) ?? ""
                isLinkEditorShown = linkTarget != nil
            }
            if let link, let url = URL(string: link) {
                button("arrow.up.forward.square", title: "Открыть ссылку", shortcut: nil, isOn: false) {
                    openURL(url)
                }
            }
            if let onColor {
                button("paintpalette", title: "Цвет текста и фона", shortcut: nil, isOn: false, action: onColor)
            }
            turnIntoMenu
            separator
            button(FormatAction.clear.systemImage, title: FormatAction.clear.title, shortcut: nil, isOn: false) {
                TextFormatting.perform(.clear, model: model, blockId: blockId)
            }
        }
        .padding(4)
        .background(theme.cardFill.opacity(0.55), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.textPrimary.opacity(0.14)))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Оформление текста")
        .accessibilityIdentifier("format-bar")
        .alert("Ссылка", isPresented: $isLinkEditorShown) {
            TextField("Адрес, например example.com", text: $linkDraft)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            Button("Готово") {
                if let linkTarget { model.setLink(linkDraft, in: linkTarget) }
            }
            if !linkDraft.isEmpty {
                Button("Убрать ссылку", role: .destructive) {
                    if let linkTarget { model.setLink(nil, in: linkTarget) }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Ссылка на сайт или ссылка lumen:// на страницу, книгу или цитату")
        }
    }

    private var turnIntoMenu: some View {
        Menu {
            if let block = model.findBlock(blockId) {
                ForEach(BlockType.allCases.filter { $0.isConvertible && $0 != .divider }) { type in
                    Button {
                        model.setType(blockId, type)
                    } label: {
                        Label(type.title, systemImage: type.symbolName)
                    }
                    .disabled(type == block.type)
                }
            }
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.textPrimary)
        .help("Превратить в другой блок")
        .accessibilityLabel("Превратить в")
    }

    private var separator: some View {
        Capsule()
            .fill(theme.textPrimary.opacity(0.15))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }

    private func button(_ symbol: String, title: String, shortcut: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: isOn ? .bold : .semibold))
                .foregroundStyle(isOn ? theme.vividCard(0).foreground : theme.textPrimary)
                .frame(width: 32, height: 30)
                .background(isOn ? AnyShapeStyle(theme.textPrimary) : AnyShapeStyle(.clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Панель над выделением на Mac

/// Блок с выделенным текстом и его место на странице.
struct FormatBarAnchor {
    var selection: TextSelectionInfo
    var bounds: Anchor<CGRect>
}

/// Строка с выделением сообщает своё место, а панель рисует редактор поверх всех строк.
/// Внутри строки панель висела над её границей: клики проходили сквозь неё в блок выше,
/// курсор уезжал туда, и панель пропадала.
struct FormatBarAnchorKey: PreferenceKey {
    static var defaultValue: FormatBarAnchor? { nil }

    static func reduce(value: inout FormatBarAnchor?, nextValue: () -> FormatBarAnchor?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    /// Панель оформления над блоком, в котором выделен текст.
    func floatingFormatBar(model: PageEditorModel) -> some View {
        overlayPreferenceValue(FormatBarAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let rect = proxy[anchor.bounds]
                    // Над первым блоком места может не хватить: тогда панель под ним.
                    let y = rect.minY >= 46 ? rect.minY - 44 : rect.maxY + 6
                    FormatBar(model: model, blockId: anchor.selection.blockId, selection: anchor.selection) {
                        model.colorPickerRequest = anchor.selection.blockId
                    }
                    .offset(x: rect.minX + BlockRow.handleInset, y: y)
                    .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Оформленный текст

enum RichTextRendering {
    private typealias SwiftUIAttributes = AttributeScopes.SwiftUIAttributes

    /// Фрагменты блока как оформленный текст для показа вне редактирования.
    static func attributed(_ runs: [TextRun], linkColor: Color) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.marks.contains(.bold) { intent.insert(.stronglyEmphasized) }
            if run.marks.contains(.italic) { intent.insert(.emphasized) }
            if run.marks.contains(.code) { intent.insert(.code) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            // Атрибуты SwiftUI названы явно: у UIKit и AppKit есть свои с теми же именами.
            if run.marks.contains(.underline) || run.link?.isEmpty == false {
                piece[SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
            }
            if run.marks.contains(.strikethrough) {
                piece[SwiftUIAttributes.StrikethroughStyleAttribute.self] = .single
            }
            if run.marks.contains(.code) {
                piece[SwiftUIAttributes.BackgroundColorAttribute.self] = Color.white.opacity(0.1)
            }
            if run.link?.isEmpty == false {
                piece[SwiftUIAttributes.ForegroundColorAttribute.self] = linkColor
            }
            result += piece
        }
        return result
    }
}

// MARK: - Действия оформления

/// Оформление по кнопке, сочетанию клавиш или пункту меню. Выделение берётся прямо из поля:
/// с ним оформляется выделенное, без него у курсора ставится пара значков (**|**), и дальше
/// текст печатается уже жирным. Если поля с курсором нет, оформляется весь блок.
@MainActor
enum TextFormatting {
    /// Выделение в поле с курсором, в символах текста без разметки. Пустое выделение не в счёт.
    static func currentSelection(blockId: UUID) -> TextSelectionInfo? {
        guard let live = ActiveTextField.selection() else { return nil }
        let parsed = InlineMarkup.parse(live.text)
        let start = parsed.plainOffset(forSource: live.range.lowerBound)
        let end = parsed.plainOffset(forSource: live.range.upperBound)
        guard end > start else { return nil }
        return TextSelectionInfo(blockId: blockId, range: start..<end)
    }

    static func perform(_ action: FormatAction, model: PageEditorModel, blockId: UUID) {
        guard model.wholeText(of: blockId) != nil else { return }
        let isFocusedBlock = model.focusedBlockId == blockId
        if isFocusedBlock, let live = ActiveTextField.selection() {
            let parsed = InlineMarkup.parse(live.text)
            let start = parsed.plainOffset(forSource: live.range.lowerBound)
            let end = parsed.plainOffset(forSource: live.range.upperBound)
            if end > start {
                model.apply(action, to: TextSelectionInfo(blockId: blockId, range: start..<end))
                return
            }
            guard let mark = action.mark, live.range.lowerBound <= live.text.count else { return }
            let marker = InlineMarkup.delimiter(for: mark)
            var text = live.text
            text.insert(contentsOf: marker + marker, at: text.index(text.startIndex, offsetBy: live.range.lowerBound))
            model.updateMarkup(blockId, to: text)
            let caret = live.range.lowerBound + marker.count
            ActiveTextField.select(caret..<caret, whenTextIs: text)
            return
        }
        if let whole = model.wholeText(of: blockId) {
            model.apply(action, to: whole)
        }
    }
}

/// Поле ввода, в котором сейчас курсор: его текст и выделение. Привязка `TextSelection`
/// у SwiftUI-поля на Mac останавливала набор текста (UI-тесты), поэтому выделение
/// читается у самого поля AppKit или UIKit.
@MainActor
enum ActiveTextField {
    /// Текст поля и выделение в символах (не в UTF-16).
    static func selection() -> (text: String, range: Range<Int>)? {
        #if os(macOS)
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isFieldEditor else { return nil }
        return characters(textView.string, textView.selectedRange())
        #else
        switch firstResponder() {
        case let textView as UITextView:
            return characters(textView.text ?? "", textView.selectedRange)
        case let textField as UITextField:
            guard let range = textField.selectedTextRange else { return nil }
            let start = textField.offset(from: textField.beginningOfDocument, to: range.start)
            let end = textField.offset(from: textField.beginningOfDocument, to: range.end)
            return characters(textField.text ?? "", NSRange(location: start, length: end - start))
        default:
            return nil
        }
        #endif
    }

    /// Ставит выделение, когда в поле уже появилась новая разметка.
    static func select(_ range: Range<Int>, whenTextIs expected: String) {
        Task { @MainActor in
            for delay in [16, 60, 150] {
                try? await Task.sleep(for: .milliseconds(delay))
                if apply(range, expected: expected) { return }
            }
        }
    }

    private static func apply(_ range: Range<Int>, expected: String) -> Bool {
        guard range.upperBound <= expected.count else { return true }
        let lower = expected.index(expected.startIndex, offsetBy: range.lowerBound)
        let upper = expected.index(expected.startIndex, offsetBy: range.upperBound)
        let nsRange = NSRange(lower..<upper, in: expected)
        #if os(macOS)
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isFieldEditor,
              textView.string == expected else { return false }
        textView.setSelectedRange(nsRange)
        return true
        #else
        switch firstResponder() {
        case let textView as UITextView:
            guard textView.text == expected else { return false }
            textView.selectedRange = nsRange
            return true
        case let textField as UITextField:
            guard textField.text == expected,
                  let start = textField.position(from: textField.beginningOfDocument, offset: nsRange.location),
                  let end = textField.position(from: start, offset: nsRange.length) else { return false }
            textField.selectedTextRange = textField.textRange(from: start, to: end)
            return true
        default:
            return false
        }
        #endif
    }

    private static func characters(_ text: String, _ nsRange: NSRange) -> (text: String, range: Range<Int>)? {
        guard let range = Range(nsRange, in: text) else { return nil }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        return (text, start..<end)
    }

    #if os(iOS)
    fileprivate static weak var found: UIResponder?

    /// Первый ответчик: действие без адресата доходит до него первым.
    private static func firstResponder() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.lumen_reportFirstResponder), to: nil, from: nil, for: nil)
        return found
    }
    #endif
}

#if os(iOS)
extension UIResponder {
    @objc fileprivate func lumen_reportFirstResponder() {
        ActiveTextField.found = self
    }
}
#endif

// MARK: - Меню по правой кнопке внутри текста

/// Пункты оформления в системном меню текста (правая кнопка, нажатие двумя пальцами).
/// Меню строит само поле ввода, поэтому пункты добавляются в него через подмену метода,
/// а действие уходит в редактор, у которого сейчас выделен текст.
@MainActor
enum TextFormatMenu {
    /// Редактор, в блоке которого сейчас курсор. Ставит блок при получении фокуса.
    static weak var editor: PageEditorModel?
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        #if os(macOS)
        swizzle(NSTextView.self, #selector(NSTextView.menu(for:)), #selector(NSTextView.lumen_menu(for:)))
        #else
        swizzle(UITextView.self, #selector(UIResponder.buildMenu(with:)), #selector(UITextView.lumen_buildMenu(with:)))
        #endif
    }

    /// Подмена только в этом классе: если метод унаследован, он сначала добавляется сюда.
    private static func swizzle(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(type, original),
              let replacementMethod = class_getInstanceMethod(type, replacement) else { return }
        if class_addMethod(type, original, method_getImplementation(replacementMethod), method_getTypeEncoding(replacementMethod)) {
            class_replaceMethod(type, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    /// Есть ли блок с курсором, текст которого можно оформить.
    static var hasTarget: Bool {
        guard let editor, let id = editor.focusedBlockId else { return false }
        return editor.wholeText(of: id) != nil
    }

    static func perform(_ action: FormatAction) {
        guard let editor, let id = editor.focusedBlockId else { return }
        TextFormatting.perform(action, model: editor, blockId: id)
    }

    static let actions: [FormatAction] = [.bold, .italic, .underline, .strikethrough, .code, .clear]
}

#if os(macOS)
/// Цель пунктов меню: NSMenuItem вызывает селектор у объекта.
@MainActor
private final class TextFormatMenuTarget: NSObject {
    static let shared = TextFormatMenuTarget()

    @objc func perform(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let action = FormatAction(rawValue: raw) else { return }
        TextFormatMenu.perform(action)
    }
}

extension NSTextView {
    @objc fileprivate func lumen_menu(for event: NSEvent) -> NSMenu? {
        // После подмены это вызов настоящего метода.
        let menu = lumen_menu(for: event)
        guard isFieldEditor, let menu, TextFormatMenu.hasTarget else { return menu }
        let format = NSMenu(title: "Формат")
        for action in TextFormatMenu.actions {
            let item = NSMenuItem(title: action.title, action: #selector(TextFormatMenuTarget.perform(_:)), keyEquivalent: "")
            item.target = TextFormatMenuTarget.shared
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: nil)
            format.addItem(item)
        }
        let formatItem = NSMenuItem(title: "Формат", action: nil, keyEquivalent: "")
        formatItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        formatItem.submenu = format
        menu.insertItem(formatItem, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }
}
#else
extension UITextView {
    @objc fileprivate func lumen_buildMenu(with builder: any UIMenuBuilder) {
        lumen_buildMenu(with: builder)
        guard builder.system == .context, isFirstResponder, TextFormatMenu.hasTarget,
              builder.menu(for: .standardEdit) != nil else { return }
        let actions = TextFormatMenu.actions.map { action in
            UIAction(title: action.title, image: UIImage(systemName: action.systemImage)) { _ in
                TextFormatMenu.perform(action)
            }
        }
        let format = UIMenu(title: "Формат", image: UIImage(systemName: "textformat"), children: actions)
        builder.insertChild(format, atStartOfMenu: .standardEdit)
    }
}
#endif
