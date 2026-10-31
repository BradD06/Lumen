import LumenCore
import LumenReader
import LumenStorage
import LumenThemes
import SwiftUI

/// Круглая кнопка на листе книги: перелистнуть главу.
struct SheetRoundButtonStyle: ButtonStyle {
    let ink: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: 30, height: 30)
            .background(ink.opacity(configuration.isPressed ? 0.16 : 0.09), in: Circle())
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.35)
    }
}

// MARK: - Действия с выделением

/// Цветной кружок для выбора цвета выделения.
private struct HighlightSwatch: View {
    let color: HighlightColor
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: color.hex))
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(
                    isSelected ? AnyShapeStyle(Color.white.opacity(0.95)) : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .center)),
                    lineWidth: isSelected ? 2.5 : 1
                ))
                .shadow(color: Color(hex: color.hex).opacity(0.45), radius: 5, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.title)
        .accessibilityLabel("Выделить: \(color.title)")
    }
}

/// Мягкая плашка действий над выделением. На Mac и iPad это капсула в одну строку,
/// на iPhone две строки: цвета сверху и крупная кнопка «В заметки» снизу.
private struct HighlightActionBar<Extra: View>: View {
    var selectedColor: HighlightColor?
    var isCompact: Bool
    var onColor: (HighlightColor) -> Void
    var onExcerpt: () -> Void
    var onClose: () -> Void
    @ViewBuilder var extra: () -> Extra
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if isCompact {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        swatches
                        Spacer(minLength: 4)
                        extra()
                    }
                    HStack(spacing: 10) {
                        excerptButton(expands: true)
                        closeButton
                    }
                }
            } else {
                HStack(spacing: 10) {
                    swatches
                    Capsule().fill(.white.opacity(0.15)).frame(width: 1, height: 22)
                    excerptButton(expands: false)
                    extra()
                    closeButton
                }
            }
        }
        .buttonStyle(ReaderPillButtonStyle())
        .readerBarStyle(theme, isCompact: isCompact)
    }

    private var swatches: some View {
        ForEach(HighlightColor.allCases) { color in
            HighlightSwatch(color: color, isSelected: color == selectedColor) { onColor(color) }
        }
    }

    private func excerptButton(expands: Bool) -> some View {
        Button(action: onExcerpt) {
            Label("В заметки", systemImage: "quote.opening")
                .font(.system(size: expands ? 16 : 14, weight: .heavy, design: .rounded))
        }
        .buttonStyle(ReaderPillButtonStyle(isProminent: true, expands: expands))
        .keyboardShortcut("e", modifiers: .command)
        .help("Выделить и вставить цитату в заметки (⌘E)")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(ReaderPillButtonStyle(size: isCompact ? 46 : 34))
        .help("Закрыть")
    }
}

/// Плашка под выделенным текстом: покрасить, отправить в заметки, скопировать.
struct SelectionBar: View {
    let model: ReaderModel
    var isCompact = false

    var body: some View {
        HighlightActionBar(
            selectedColor: nil,
            isCompact: isCompact,
            onColor: { color in Task { await model.highlightSelection(color) } },
            onExcerpt: { Task { await model.excerptSelection() } },
            onClose: { model.clearSelection() }
        ) {
            Button {
                if let text = model.selection?.text { copyToPasteboard(text) }
                model.showToast("Скопировано")
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Скопировать")
        }
    }
}

/// Плашка для уже сохранённого выделения: другой цвет, выписка, удаление.
struct HighlightBar: View {
    let model: ReaderModel
    let highlight: Highlight
    var isCompact = false

    var body: some View {
        HighlightActionBar(
            selectedColor: highlight.color,
            isCompact: isCompact,
            onColor: { color in model.setColor(color, of: highlight.id) },
            onExcerpt: {
                model.addExcerpt(highlight)
                model.activeHighlightId = nil
            },
            onClose: { model.activeHighlightId = nil }
        ) {
            Button {
                model.deleteHighlight(highlight.id)
            } label: {
                Image(systemName: "trash")
            }
            .help("Удалить выделение")
        }
    }
}


private struct ReaderPillButtonStyle: ButtonStyle {
    var isProminent = false
    /// Растянуть на всю ширину: крупная кнопка «В заметки» на iPhone.
    var expands = false
    var size: CGFloat = 34
    @Environment(\.lumenTheme) private var theme

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isProminent ? ReaderStyle.onPeach : theme.textPrimary)
            .padding(.horizontal, isProminent ? 14 : 0)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(minWidth: size, minHeight: expands ? 46 : size)
            .background {
                if isProminent {
                    Capsule()
                        .fill(ReaderStyle.peachGradient)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                        .shadow(color: ReaderStyle.peachDeep.opacity(0.55), radius: 8, y: 4)
                } else {
                    Circle().fill(.white.opacity(0.08))
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

private extension View {
    func readerBarStyle(_ theme: Theme, isCompact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: isCompact ? 30 : 28, style: .continuous)
        return self
            .padding(.leading, isCompact ? 14 : 14)
            .padding(.trailing, isCompact ? 12 : 8)
            .padding(.vertical, isCompact ? 12 : 8)
            .background(theme.cardFill.opacity(0.5), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            ))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }
}
