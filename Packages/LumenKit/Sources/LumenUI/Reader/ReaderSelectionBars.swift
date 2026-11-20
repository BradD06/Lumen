import LumenCore
import LumenReader
import LumenStorage
import LumenThemes
import SwiftUI
import Translation

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
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(LumenMotion.quick, value: configuration.isPressed)
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
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: color.hex))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().strokeBorder(theme.textPrimary.opacity(isSelected ? 0.8 : 0), lineWidth: 1.5))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.title)
        .accessibilityLabel("Выделить: \(color.title)")
    }
}

/// Пузырь действий у выделения: цвета, «В заметки» акцентом, остальное тихими значками.
/// На Mac и iPad это стеклянная плашка в одну строку, на iPhone две строки: цвета сверху
/// и крупная кнопка «В заметки» снизу.
private struct HighlightActionBar<Extra: View>: View {
    var selectedColor: HighlightColor?
    var isCompact: Bool
    var onColor: (HighlightColor) -> Void
    var onExcerpt: () -> Void
    var onClose: () -> Void
    /// Что тянуть, если кнопку «В заметки» не нажать, а потащить на заметку.
    var drag: ExcerptDrag.Payload?
    var dragText = ""
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
                HStack(spacing: 4) {
                    swatches
                    Capsule().fill(theme.line).frame(width: 1, height: 20).padding(.horizontal, 2)
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

    @ViewBuilder
    private func excerptButton(expands: Bool) -> some View {
        let button = Button(action: onExcerpt) {
            Label("В заметки", systemImage: "quote.opening")
                .font(.system(size: expands ? 16 : 13.5, weight: .semibold))
        }
        .buttonStyle(ReaderPillButtonStyle(isProminent: true, expands: expands))
        .keyboardShortcut("e", modifiers: .command)
        if let drag {
            // Кнопку можно не только нажать, но и утащить на заметку: выписка встанет там.
            button
                .onDrag {
                    ExcerptDrag.itemProvider(for: drag)
                } preview: {
                    ExcerptDragPreview(text: dragText)
                }
                .help("Нажмите или перетащите на заметку, чтобы вставить цитату (⌘E)")
        } else {
            button.help("Выделить и вставить цитату в заметки (⌘E)")
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(ReaderPillButtonStyle(size: isCompact ? 46 : 30))
        .help("Закрыть")
    }
}

/// Плашка под выделенным текстом: покрасить, отправить в заметки, ссылка, перевод, копия.
struct SelectionBar: View {
    let model: ReaderModel
    var isCompact = false

    @State private var isTranslating = false
    /// Текст запоминается до показа перевода: выделение в книге к тому времени может сняться.
    @State private var textToTranslate = ""

    var body: some View {
        HighlightActionBar(
            selectedColor: nil,
            isCompact: isCompact,
            onColor: { color in Task { await model.highlightSelection(color) } },
            onExcerpt: { Task { await model.excerptSelection() } },
            onClose: { model.clearSelection() },
            drag: ExcerptDrag.Payload(sourceId: model.sourceId),
            dragText: model.selection?.text ?? ""
        ) {
            Button {
                Task { await model.copySelectionLink() }
            } label: {
                Image(systemName: "link")
            }
            .help("Выделить и скопировать ссылку на это место")
            .accessibilityLabel("Ссылка")
            Button {
                textToTranslate = model.selection?.text ?? ""
                isTranslating = !textToTranslate.isEmpty
            } label: {
                Image(systemName: "translate")
            }
            .help("Перевести")
            .accessibilityLabel("Перевести")
            .translationPresentation(isPresented: $isTranslating, text: textToTranslate)
            Button {
                if let text = model.selection?.text { copyToPasteboard(text) }
                model.showToast("Скопировано")
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Скопировать")
            .accessibilityLabel("Скопировать")
        }
    }
}

/// Плашка для уже сохранённого выделения: другой цвет, выписка, комментарий, удаление.
struct HighlightBar: View {
    let model: ReaderModel
    let highlight: Highlight
    var isCompact = false

    @State private var isEditingNote = false

    var body: some View {
        HighlightActionBar(
            selectedColor: highlight.color,
            isCompact: isCompact,
            onColor: { color in model.setColor(color, of: highlight.id) },
            onExcerpt: {
                Task { await model.addExcerpt(highlight) }
                model.activeHighlightId = nil
            },
            onClose: { model.activeHighlightId = nil },
            drag: ExcerptDrag.Payload(sourceId: model.sourceId, highlightId: highlight.id),
            dragText: highlight.text
        ) {
            Button {
                isEditingNote = true
            } label: {
                Image(systemName: highlight.note == nil ? "text.bubble" : "text.bubble.fill")
            }
            .help(highlight.note == nil ? "Добавить комментарий" : "Комментарий: \(highlight.note ?? "")")
            Button {
                model.deleteHighlight(highlight.id)
            } label: {
                Image(systemName: "trash")
            }
            .help("Удалить выделение")
        }
        .sheet(isPresented: $isEditingNote) {
            HighlightNoteSheet(highlight: highlight) { note in
                model.setNote(note, of: highlight.id)
            }
        }
    }
}


private struct ReaderPillButtonStyle: ButtonStyle {
    var isProminent = false
    /// Растянуть на всю ширину: крупная кнопка «В заметки» на iPhone.
    var expands = false
    var size: CGFloat = 30
    @Environment(\.lumenTheme) private var theme

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        let shape = RoundedRectangle(cornerRadius: expands ? 14 : 8, style: .continuous)
        return configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isProminent ? theme.onAccent : theme.textPrimary)
            .padding(.horizontal, isProminent ? 10 : 0)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(minWidth: size, minHeight: expands ? 46 : size)
            .background {
                if isProminent {
                    shape.fill(theme.accent)
                } else if configuration.isPressed {
                    shape.fill(theme.surface2)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(LumenMotion.quick, value: configuration.isPressed)
    }
}

private extension View {
    func readerBarStyle(_ theme: Theme, isCompact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: isCompact ? 24 : 12, style: .continuous)
        return self
            .padding(.leading, isCompact ? 14 : 6)
            .padding(.trailing, isCompact ? 12 : 5)
            .padding(.vertical, isCompact ? 12 : 5)
            .lumenGlass(shape, prominent: true)
    }
}
