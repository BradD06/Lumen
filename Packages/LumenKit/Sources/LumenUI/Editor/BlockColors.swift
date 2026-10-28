import LumenCore
import LumenThemes
import SwiftUI

/// Оттенки цветов блоков, подобранные под тёмную тему: яркий текст и приглушённый фон.
extension BlockColor {
    var textColor: Color {
        switch self {
        case .gray: Color(hex: 0xA8A29E)
        case .brown: Color(hex: 0xC9A27E)
        case .orange: Color(hex: 0xFFA26B)
        case .yellow: Color(hex: 0xFFD66B)
        case .green: Color(hex: 0x9EDB7A)
        case .blue: Color(hex: 0x7CC4FF)
        case .purple: Color(hex: 0xC8A2FF)
        case .pink: Color(hex: 0xFF9ECF)
        case .red: Color(hex: 0xFF7F7F)
        }
    }

    var backgroundColor: Color {
        textColor.opacity(0.2)
    }
}

extension View {
    /// Фон блока, если он выбран в меню «Цвет». Цвет текста задаёт само поле.
    @ViewBuilder
    func blockBackground(_ color: BlockColor?) -> some View {
        if let background = color {
            self
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(background.backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            self
        }
    }
}

/// Палитра «Цвет»: образцы цвета текста и фона, как в Notion. Нарисована самим SwiftUI,
/// поэтому цвета видны всегда, в отличие от значков в системном меню.
/// Цвет текста и фон независимы, их можно задать вместе.
struct BlockColorPicker: View {
    let block: Block
    let model: PageEditorModel

    @Environment(\.lumenTheme) private var theme

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Текст") {
                swatch(title: "По умолчанию", isSelected: block.content.textColor == nil) {
                    model.setTextColor(block.id, nil)
                } label: {
                    letter(theme.textPrimary)
                }
                ForEach(BlockColor.allCases) { color in
                    swatch(title: color.title, isSelected: block.content.textColor == color) {
                        model.setTextColor(block.id, color)
                    } label: {
                        letter(color.textColor)
                    }
                }
            }
            section("Фон") {
                swatch(title: "Без фона", isSelected: block.content.backgroundColor == nil) {
                    model.setBackgroundColor(block.id, nil)
                } label: {
                    Image(systemName: "nosign")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
                ForEach(BlockColor.allCases) { color in
                    swatch(title: color.title, isSelected: block.content.backgroundColor == color) {
                        model.setBackgroundColor(block.id, color)
                    } label: {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color.textColor.opacity(0.6))
                            .padding(4)
                    }
                }
            }
        }
        .padding(14)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                content()
            }
        }
    }

    private func letter(_ color: Color) -> some View {
        Text("A")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(color)
    }

    private func swatch(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        // Палитра остаётся открытой: можно выбрать и цвет текста, и фон, а закрыть кликом мимо.
        Button(action: action) {
            label()
                .frame(width: 30, height: 30)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isSelected ? theme.accent : Color.gray.opacity(0.35), lineWidth: isSelected ? 2 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
