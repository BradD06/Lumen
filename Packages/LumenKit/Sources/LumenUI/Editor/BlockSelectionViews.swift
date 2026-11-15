import LumenCore
import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Пункты меню для выделенных блоков: в контекстном меню и под «…» на панели выделения.
struct BlockSelectionMenuItems: View {
    let model: PageEditorModel

    private static let types = BlockType.allCases.filter { $0.isConvertible && $0.hasText }

    var body: some View {
        Button {
            model.copySelection()
        } label: {
            Label("Скопировать", systemImage: "doc.on.doc")
        }
        Button {
            model.cutSelection()
        } label: {
            Label("Вырезать", systemImage: "scissors")
        }
        Button {
            model.duplicateSelection()
        } label: {
            Label("Дублировать", systemImage: "plus.square.on.square")
        }
        Button {
            model.wrapSelectionInSynced()
        } label: {
            Label("Сделать синхронным", systemImage: "arrow.triangle.2.circlepath")
        }
        Menu {
            ForEach(Self.types) { type in
                Button {
                    model.setTypeForSelection(type)
                } label: {
                    Label(type.title, systemImage: type.symbolName)
                }
            }
        } label: {
            Label("Превратить в", systemImage: "arrow.triangle.2.circlepath")
        }
        Menu {
            Section("Цвет текста") {
                Button("Обычный") { model.setSelectionTextColor(nil) }
                ForEach(BlockColor.allCases) { color in
                    Button(color.title) { model.setSelectionTextColor(color) }
                }
            }
            Section("Фон") {
                Button("Без фона") { model.setSelectionBackgroundColor(nil) }
                ForEach(BlockColor.allCases) { color in
                    Button(color.title) { model.setSelectionBackgroundColor(color) }
                }
            }
        } label: {
            Label("Цвет текста и фона", systemImage: "paintpalette")
        }
        Divider()
        Menu {
            Button {
                model.moveSelection(by: -1)
            } label: {
                Label("Вверх", systemImage: "arrow.up")
            }
            Button {
                model.moveSelection(by: 1)
            } label: {
                Label("Вниз", systemImage: "arrow.down")
            }
            Button {
                model.indentSelection()
            } label: {
                Label("Вложить в блок выше", systemImage: "increase.indent")
            }
            Button {
                model.outdentSelection()
            } label: {
                Label("Вынести на уровень выше", systemImage: "decrease.indent")
            }
        } label: {
            Label("Переместить", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
        }
        Divider()
        Button(role: .destructive) {
            model.deleteSelection()
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}

/// Панель под страницей, пока выделены блоки: сколько выбрано и частые действия.
/// Стоит в отступе снизу, а не поверх текста: на Mac кнопку над полем ввода клик не достаёт.
struct BlockSelectionBar: View {
    let model: PageEditorModel

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            Text("Выделено: \(BlockSelection.blocksCaption(model.selectionRoots.count))")
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .padding(.leading, 12)
                .padding(.trailing, 6)
            barButton("Скопировать", systemImage: "doc.on.doc") { model.copySelection() }
            barButton("Дублировать", systemImage: "plus.square.on.square") { model.duplicateSelection() }
            barButton("Удалить", systemImage: "trash") {
                LumenSounds.play(.trash)
                model.deleteSelection()
            }
            Menu {
                BlockSelectionMenuItems(model: model)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Ещё действия с выделенными блоками")
            .accessibilityLabel("Ещё")
            barButton("Снять выделение", systemImage: "xmark") { model.clearSelection() }
        }
        .padding(4)
        .lumenGlass(Capsule())
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("block-selection-bar")
    }

    private func barButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Выделенный блок вместе с вложенными: мягкая подсветка цветом схемы.
struct BlockSelectionHighlight: View {
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(theme.accent.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
            )
            // Ручка слева остаётся вне подсветки, как в Notion.
            .padding(.leading, BlockRow.handleInset - 4)
            .padding(.trailing, -4)
            .padding(.vertical, -2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if os(macOS)
/// Рамка выделения на Mac: потяните мышью с полей или с пустого места страницы,
/// и все блоки, которых коснулась рамка, выделятся. Поля текста свои щелчки забирают сами.
struct BlockMarqueeSelection: ViewModifier {
    let model: PageEditorModel
    var onBegin: () -> Void

    @State private var rect: CGRect?
    @Environment(\.lumenTheme) private var theme

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(EditorSpace.blocks))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(EditorSpace.blocks))
                    .onChanged { value in
                        guard model.draggingBlockId == nil, model.activeDrawingId == nil else { return }
                        if rect == nil {
                            // Начали на ручке блока: это перетаскивание блока, а не рамка.
                            let startsOnHandle = model.blockFrames.values.contains { frame in
                                CGRect(x: frame.minX, y: frame.minY, width: BlockRow.handleInset, height: frame.height)
                                    .contains(value.startLocation)
                            }
                            guard !startsOnHandle else { return }
                            onBegin()
                        }
                        let area = CGRect(
                            x: min(value.startLocation.x, value.location.x),
                            y: min(value.startLocation.y, value.location.y),
                            width: abs(value.location.x - value.startLocation.x),
                            height: abs(value.location.y - value.startLocation.y)
                        )
                        rect = area
                        let touched = model.blockFrames.filter { $0.value.intersects(area) }.map(\.key)
                        if touched.isEmpty {
                            model.clearSelection()
                        } else {
                            model.selectBlocks(touched)
                        }
                    }
                    .onEnded { _ in
                        if rect != nil {
                            let order = model.visibleBlockIds.filter { model.isSelected($0) }
                            model.selectionAnchor = order.first
                            model.selectionHead = order.last
                        }
                        rect = nil
                    }
            )
            .overlay(alignment: .topLeading) {
                if let rect {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.accent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(theme.accent.opacity(0.55), lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Окно, в котором стоит редактор: клавиши выделения работают только в нём.
final class EditorWindowBox {
    weak var window: NSWindow?
}

struct EditorWindowReader: NSViewRepresentable {
    let box: EditorWindowBox

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.box = box
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.box = box
        box.window = view.window
    }

    final class ReaderView: NSView {
        var box: EditorWindowBox?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Клавиши редактора на Mac для выделения блоков. Коды клавиш физические: русская раскладка не мешает.
@MainActor
enum BlockSelectionKeys {
    /// Блоки выделены, курсора в тексте нет.
    static func handleSelection(_ model: PageEditorModel, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch (keyCode, flags) {
        case (51, []), (117, []):
            LumenSounds.play(.trash)
            model.deleteSelection()
        case (53, []):
            model.clearSelection()
        case (36, []), (76, []):
            model.editSelection()
        case (8, [.command]):
            model.copySelection()
        case (7, [.command]):
            model.cutSelection()
        case (9, [.command]):
            return model.pasteBlocks(after: model.selectionRoots.last)
        case (2, [.command]):
            model.duplicateSelection()
        case (0, [.command]):
            model.selectAllBlocks()
        case (126, []):
            model.moveSelectionCursor(by: -1, extend: false)
        case (125, []):
            model.moveSelectionCursor(by: 1, extend: false)
        case (126, [.shift]):
            model.moveSelectionCursor(by: -1, extend: true)
        case (125, [.shift]):
            model.moveSelectionCursor(by: 1, extend: true)
        case (126, [.command, .option]):
            model.moveSelection(by: -1)
        case (125, [.command, .option]):
            model.moveSelection(by: 1)
        case (48, []):
            model.indentSelection()
        case (48, [.shift]):
            model.outdentSelection()
        default:
            return false
        }
        return true
    }

    /// Курсор в тексте блока: Esc выделяет блок, второй ⌘A все блоки, ⇧↑ в начале и ⇧↓ в конце
    /// текста переходят к выделению блоков, ⌘V вставляет скопированные блоки.
    static func handleText(_ model: PageEditorModel, textView: NSTextView, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard !textView.hasMarkedText(), model.focusedBlockId != nil else { return false }
        let selected = textView.selectedRange()
        let length = (textView.string as NSString).length
        switch (keyCode, flags) {
        case (53, []):
            return model.selectFocusedBlock()
        case (0, [.command]):
            guard selected.location == 0, selected.length == length else { return false }
            model.selectAllBlocks()
            return true
        case (126, [.shift]):
            guard selected.location == 0 else { return false }
            guard model.selectFocusedBlock() else { return false }
            model.moveSelectionCursor(by: -1, extend: true)
            return true
        case (125, [.shift]):
            guard NSMaxRange(selected) == length else { return false }
            guard model.selectFocusedBlock() else { return false }
            model.moveSelectionCursor(by: 1, extend: true)
            return true
        case (9, [.command]):
            guard BlockPasteboard.hasBlocks else { return false }
            return model.pasteBlocks(after: model.focusedBlockId)
        default:
            return false
        }
    }
}
#endif
