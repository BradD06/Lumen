import LumenCore
import LumenThemes
import SwiftUI

/// Окно комментария к выделению: цитата сверху, под ней поле для своей мысли.
/// Пустой комментарий убирается.
struct HighlightNoteSheet: View {
    let highlight: Highlight
    var onSave: (String) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lumenTheme) private var theme

    init(highlight: Highlight, onSave: @escaping (String) -> Void) {
        self.highlight = highlight
        self.onSave = onSave
        _text = State(initialValue: highlight.note ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Capsule()
                        .fill(Color(hex: highlight.color.hex))
                        .frame(width: 4)
                    Text(highlight.text)
                        .font(.system(.callout, design: .serif))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(6)
                }
                TextField("Ваша мысль об этом месте", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focused($isFocused)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(ThemedBackground())
            .navigationTitle(highlight.note == nil ? "Комментарий" : "Изменить комментарий")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(text)
                        dismiss()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear { isFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// Комментарий под цитатой в списках выделений.
struct HighlightNoteLabel: View {
    let note: String
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Label {
            Text(note)
                .lineLimit(3)
        } icon: {
            Image(systemName: "text.bubble")
        }
        .font(.callout)
        .foregroundStyle(theme.textPrimary.opacity(0.85))
    }
}
