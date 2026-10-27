import LumenCore
import LumenThemes
import SwiftUI

/// Один блок страницы: маркер (точка, номер, чекбокс) и текстовое поле.
struct BlockRow: View {
    let block: Block
    let number: Int
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
            if let query = slashQuery, isFocused {
                SlashMenu(query: query) { type in
                    model.setType(block.id, type)
                }
            }
        }
        .padding(.vertical, verticalPadding)
        .contextMenu {
            Menu("Превратить в") {
                ForEach(BlockType.allCases) { type in
                    Button {
                        model.setType(block.id, type)
                    } label: {
                        Label(type.title, systemImage: type.symbolName)
                    }
                }
            }
            Button(role: .destructive) {
                model.deleteBlock(block.id)
            } label: {
                Label("Удалить блок", systemImage: "trash")
            }
        }
    }

    private var isFocused: Bool {
        focus.wrappedValue == .block(block.id)
    }

    /// Текст после `/` в пустом абзаце открывает меню выбора типа блока.
    private var slashQuery: String? {
        guard block.type == .paragraph, block.text.hasPrefix("/") else { return nil }
        return String(block.text.dropFirst())
    }

    @ViewBuilder
    private var content: some View {
        switch block.type {
        case .divider:
            Rectangle()
                .fill(theme.textSecondary.opacity(0.35))
                .frame(height: 1)
                .padding(.vertical, 10)
                .contentShape(Rectangle().inset(by: -8))

        case .bulletedList:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.accent)
                field
            }

        case .numberedList:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
                field
            }

        case .todo:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    model.toggleChecked(block.id)
                } label: {
                    Image(systemName: block.content.isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(block.content.isChecked ? theme.accent : theme.textSecondary)
                }
                .buttonStyle(.plain)
                field
                    .strikethrough(block.content.isChecked)
                    .opacity(block.content.isChecked ? 0.55 : 1)
            }

        case .quote:
            HStack(spacing: 12) {
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 3)
                field
                    .italic()
            }
            .fixedSize(horizontal: false, vertical: true)

        case .callout:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("💡")
                field
            }
            .lumenCard(padding: 12)

        case .code:
            field
                .padding(12)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .paragraph, .heading1, .heading2, .heading3:
            field
        }
    }

    private var field: some View {
        TextField(
            placeholder,
            text: Binding(get: { block.text }, set: { model.updateText(block.id, to: $0) }),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(font)
        .foregroundStyle(theme.textPrimary)
        .focused(focus, equals: .block(block.id))
        .onSubmit { model.submit(block.id) }
        .onKeyPress(.delete) {
            model.backspaceInEmptyBlock(block.id) ? .handled : .ignored
        }
    }

    private var placeholder: String {
        switch block.type {
        case .paragraph: isFocused ? "Пишите или нажмите / для команд" : ""
        case .heading1: "Заголовок 1"
        case .heading2: "Заголовок 2"
        case .heading3: "Заголовок 3"
        case .bulletedList, .numberedList: "Пункт списка"
        case .todo: "Задача"
        case .quote: "Цитата"
        case .callout: "Выноска"
        case .code: "Код"
        case .divider: ""
        }
    }

    private var font: Font {
        switch block.type {
        case .heading1: .system(size: 30, weight: .bold)
        case .heading2: .system(size: 24, weight: .semibold)
        case .heading3: .system(size: 19, weight: .semibold)
        case .code: .system(.callout, design: .monospaced)
        default: .system(size: 17)
        }
    }

    private var verticalPadding: CGFloat {
        switch block.type {
        case .heading1: 10
        case .heading2: 8
        case .heading3: 6
        default: 2
        }
    }
}

/// Меню типов блоков по `/`.
struct SlashMenu: View {
    let query: String
    var onSelect: (BlockType) -> Void

    @Environment(\.lumenTheme) private var theme

    private var types: [BlockType] {
        BlockType.allCases.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if types.isEmpty {
                Text("Ничего не найдено")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .padding(8)
            }
            ForEach(types) { type in
                Button {
                    onSelect(type)
                } label: {
                    Label(type.title, systemImage: type.symbolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 300)
        .lumenCard(padding: 6)
    }
}
