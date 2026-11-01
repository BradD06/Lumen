import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Что делает касание листа в рукописной заметке.
enum NotebookTool: String, CaseIterable, Identifiable {
    /// Писать и рисовать.
    case draw
    /// Выбрать текст или картинку, двигать и менять размер. Палец листает тетрадь.
    case select
    /// Нажатие на пустое место ставит текстовый блок.
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draw: "Перо"
        case .select: "Выделение"
        case .text: "Текст"
        }
    }

    var symbolName: String {
        switch self {
        case .draw: "pencil.tip"
        case .select: "hand.point.up.left"
        case .text: "textformat"
        }
    }
}

/// Как часть холста тетради лежит на экране: какая точка холста в левом верхнем углу
/// и сколько пунктов экрана в пункте холста.
struct NotebookViewport: Equatable {
    var origin: CGPoint = .zero
    var scale: CGFloat = 1

    func toScreen(_ rect: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - origin.x) * scale,
            y: (rect.minY - origin.y) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    func toCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale + origin.x, y: point.y / scale + origin.y)
    }
}

/// Один текст или картинка, как они выглядят на листе.
struct NotebookItemView: View {
    let item: NotebookItem
    let scale: CGFloat
    let isDark: Bool
    let attachments: AttachmentStore

    var body: some View {
        switch item.kind {
        case .image:
            if let name = item.attachment {
                AttachmentImage(name: name, attachments: attachments, contentMode: .fill)
                    .frame(width: item.width * scale, height: item.height * scale)
                    .clipped()
            }
        case .text:
            Text(item.text)
                .font(.system(size: item.fontSize * scale, weight: item.isBold ? .semibold : .regular))
                .foregroundStyle((HexColor(hex: item.color) ?? HexColor(red: 0, green: 0, blue: 0)).display(isDark: isDark))
                .fixedSize(horizontal: false, vertical: true)
                .padding(TextBoxMetrics.padding * scale)
                .frame(width: item.width * scale, alignment: .topLeading)
                .frame(height: item.height * scale, alignment: .topLeading)
        }
    }
}

/// Тексты и картинки части холста: только показ, касания проходят к холсту.
struct NotebookItemsLayer: View {
    let items: [NotebookItem]
    let viewport: NotebookViewport
    let isDark: Bool
    let attachments: AttachmentStore
    /// Текст, который сейчас правят: вместо него поле ввода в слое правки.
    var hiddenId: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(items.filter { $0.id != hiddenId }) { item in
                let frame = viewport.toScreen(item.frame)
                NotebookItemView(item: item, scale: viewport.scale, isDark: isDark, attachments: attachments)
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Слой правки текстов и картинок: выделение, перетаскивание, размер, набор текста.
/// Ловит касания только на элементах, остальное достаётся холсту под ним.
struct NotebookItemsEditor: View {
    let model: PageEditorModel
    let items: [NotebookItem]
    let viewport: NotebookViewport
    let isDark: Bool
    let tool: NotebookTool
    @Binding var selection: UUID?
    @Binding var editingId: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            ForEach(items) { item in
                NotebookItemHandle(
                    model: model,
                    item: item,
                    viewport: viewport,
                    isDark: isDark,
                    tool: tool,
                    selection: $selection,
                    editingId: $editingId
                )
            }
        }
    }
}

/// Один элемент в слое правки: рамка выделения, ручка размера, панель действий и поле текста.
private struct NotebookItemHandle: View {
    let model: PageEditorModel
    let item: NotebookItem
    let viewport: NotebookViewport
    let isDark: Bool
    let tool: NotebookTool
    @Binding var selection: UUID?
    @Binding var editingId: UUID?

    @State private var dragStart: CGRect?
    @State private var isPaletteShown = false
    @State private var draft = ""
    /// Набор текста подряд это один шаг отмены: записывается только первая правка.
    @State private var hasTyped = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.lumenTheme) private var theme

    private var isSelected: Bool { selection == item.id }
    private var isEditing: Bool { editingId == item.id }
    private var frame: CGRect { viewport.toScreen(item.frame) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isEditing {
                textField
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: frame.width, height: frame.height)
                    .contentShape(Rectangle())
                    .onTapGesture { tapped() }
                    .gesture(moveGesture)
            }
            if isSelected || isEditing {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: isEditing ? [4, 3] : []))
                    .frame(width: frame.width, height: frame.height)
                    .allowsHitTesting(false)
            }
            if isSelected, !isEditing {
                resizeHandle
                    .offset(x: frame.width - 11, y: frame.height - 11)
                actionBar
                    .fixedSize()
                    .offset(y: -46)
            }
        }
        .offset(x: frame.minX, y: frame.minY)
        .onChange(of: isEditing) { _, editing in
            if editing { beginEditing() }
        }
        .onAppear {
            if isEditing { beginEditing() }
        }
    }

    private func beginEditing() {
        draft = item.text
        hasTyped = false
        isFieldFocused = true
    }

    private func tapped() {
        if tool == .text, item.kind == .text {
            selection = item.id
            editingId = item.id
        } else if isSelected, item.kind == .text {
            editingId = item.id
        } else {
            selection = item.id
        }
    }

    private var textField: some View {
        TextField("Текст", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: item.fontSize * viewport.scale, weight: item.isBold ? .semibold : .regular))
            .foregroundStyle((HexColor(hex: item.color) ?? HexColor(red: 0, green: 0, blue: 0)).display(isDark: isDark))
            .padding(TextBoxMetrics.padding * viewport.scale)
            .frame(width: frame.width, alignment: .topLeading)
            .frame(minHeight: frame.height, alignment: .topLeading)
            .focused($isFieldFocused)
            .onChange(of: draft) { _, text in
                guard text != item.text else { return }
                let isFirst = !hasTyped
                hasTyped = true
                model.updateNotebookItem(item.id, recordsUndo: isFirst) { item in
                    item.text = text
                    item = TextBoxMetrics.fitted(item)
                }
            }
            .onChange(of: isFieldFocused) { _, focused in
                if !focused { finishEditing() }
            }
            .onSubmit { finishEditing() }
            .onKeyPress(.escape) {
                finishEditing()
                return .handled
            }
    }

    private func finishEditing() {
        guard editingId == item.id else { return }
        editingId = nil
        model.removeIfEmpty(item.id)
        if model.notebookItem(item.id) == nil, selection == item.id {
            selection = nil
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let start = dragStart ?? item.frame
                let isFirst = dragStart == nil
                dragStart = start
                selection = item.id
                let moved = start.offsetBy(dx: value.translation.width / viewport.scale, dy: value.translation.height / viewport.scale)
                model.updateNotebookItem(item.id, recordsUndo: isFirst) { $0.frame = moved }
            }
            .onEnded { _ in dragStart = nil }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(theme.accent)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? item.frame
                        let isFirst = dragStart == nil
                        dragStart = start
                        var width = max(start.width + value.translation.width / viewport.scale, NotebookItem.minSize)
                        var height = max(start.height + value.translation.height / viewport.scale, NotebookItem.minSize)
                        if item.kind == .image, start.width > 0 {
                            // Картинка тянется без искажения: высота следует за шириной.
                            height = width * start.height / start.width
                            width = max(width, NotebookItem.minSize)
                        }
                        model.updateNotebookItem(item.id, recordsUndo: isFirst) { item in
                            item.frame = CGRect(x: start.minX, y: start.minY, width: width, height: height)
                            item = TextBoxMetrics.fitted(item)
                        }
                    }
                    .onEnded { _ in dragStart = nil }
            )
            #if os(macOS)
            .pointerStyle(.frameResize(position: .bottomTrailing))
            #endif
            .accessibilityLabel("Изменить размер")
    }

    /// Панель над выделенным элементом.
    private var actionBar: some View {
        HStack(spacing: 4) {
            if item.kind == .text {
                barButton("Править текст", "character.cursor.ibeam") { editingId = item.id }
                barButton("Меньше", "textformat.size.smaller") { changeFont(by: -2) }
                barButton("Больше", "textformat.size.larger") { changeFont(by: 2) }
                barButton(item.isBold ? "Обычный" : "Жирный", "bold") {
                    model.updateNotebookItem(item.id) { item in
                        item.isBold.toggle()
                        item = TextBoxMetrics.fitted(item)
                    }
                }
                Button {
                    isPaletteShown = true
                } label: {
                    Circle()
                        .fill((HexColor(hex: item.color) ?? HexColor(red: 0, green: 0, blue: 0)).swiftUIColor)
                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                        .frame(width: 20, height: 20)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Цвет текста")
                .popover(isPresented: $isPaletteShown) {
                    ColorPalette(selection: HexColor(hex: item.color) ?? HexColor(red: 0, green: 0, blue: 0)) { color in
                        model.updateNotebookItem(item.id) { $0.color = color.hex }
                    }
                    .padding(16)
                    .presentationCompactAdaptation(.popover)
                }
                Divider().frame(height: 20)
            }
            barButton("Дублировать", "plus.square.on.square") {
                if let copy = model.duplicateNotebookItem(item.id) {
                    selection = copy.id
                }
            }
            barButton("Удалить", "trash") {
                selection = nil
                model.removeNotebookItem(item.id)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.textSecondary.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }

    private func changeFont(by delta: Double) {
        model.updateNotebookItem(item.id) { item in
            let range = NotebookItem.fontSizeRange
            item.fontSize = min(max(item.fontSize + delta, range.lowerBound), range.upperBound)
            item = TextBoxMetrics.fitted(item)
        }
    }

    private func barButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout.weight(.medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textPrimary)
        .help(title)
        .accessibilityLabel(title)
    }
}
