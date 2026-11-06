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
    let selection: TextSelectionInfo
    /// Палитру цвета блока открывает сам блок.
    var onColor: (() -> Void)?

    @State private var isLinkEditorShown = false
    @State private var linkDraft = ""
    /// Выделение на момент нажатия «Ссылка»: пока открыто окно адреса, поле теряет фокус.
    @State private var linkTarget: TextSelectionInfo?
    @Environment(\.lumenTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let active = model.marks(in: selection)
        let link = model.link(in: selection)
        HStack(spacing: 2) {
            ForEach([FormatAction.bold, .italic, .underline, .strikethrough, .code]) { action in
                button(action.systemImage, title: action.title, shortcut: action.shortcut, isOn: action.mark.map(active.contains) ?? false) {
                    model.apply(action, to: selection)
                }
            }
            separator
            button("link", title: link == nil ? "Ссылка" : "Изменить ссылку", shortcut: nil, isOn: link != nil) {
                linkTarget = selection
                linkDraft = link ?? ""
                isLinkEditorShown = true
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
                model.apply(.clear, to: selection)
            }
            .disabled(active.isEmpty && link == nil)
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
            if link != nil {
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
            if let block = model.findBlock(selection.blockId) {
                ForEach(BlockType.allCases.filter { $0.isConvertible && $0 != .divider }) { type in
                    Button {
                        model.setType(selection.blockId, type)
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

    /// Что оформлять: выделение, а без него весь блок с курсором.
    static var target: TextSelectionInfo? {
        guard let editor else { return nil }
        if let selection = editor.textSelection { return selection }
        return editor.focusedBlockId.flatMap(editor.wholeText(of:))
    }

    static func perform(_ action: FormatAction) {
        guard let editor, let target else { return }
        editor.apply(action, to: target)
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
        guard isFieldEditor, let menu, TextFormatMenu.target != nil else { return menu }
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
        guard builder.system == .context, isFirstResponder, TextFormatMenu.target != nil,
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
