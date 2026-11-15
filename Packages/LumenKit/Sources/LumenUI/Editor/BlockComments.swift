import LumenCore
import LumenThemes
import SwiftUI

/// Значок у блока с комментариями: сколько их не решено. Нажатие открывает комментарии.
struct BlockCommentBadge: View {
    let count: Int
    let action: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "text.bubble.fill")
                Text("\(count)")
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(theme.accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Комментарии к блоку")
        .keyHint("Комментарии", perform: action)
        .accessibilityLabel("Комментарии: \(count)")
    }
}

/// Комментарии к блоку: список, новый комментарий внизу. Решённые спрятаны, но их можно показать.
struct BlockCommentsPanel: View {
    let blockId: UUID
    let model: PageEditorModel

    @State private var draft = ""
    @State private var editingId: UUID?
    @State private var editingText = ""
    @State private var showsResolved = false
    @FocusState private var isDraftFocused: Bool
    @Environment(\.lumenTheme) private var theme

    private var comments: [BlockComment] { model.comments(of: blockId) }
    private var visible: [BlockComment] { comments.filter { showsResolved || !$0.isResolved } }
    private var resolvedCount: Int { comments.filter(\.isResolved).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Комментарии")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if resolvedCount > 0 {
                    Button(showsResolved ? "Скрыть решённые" : "Решённые: \(resolvedCount)") {
                        withAnimation(LumenMotion.standard) { showsResolved.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                }
            }
            if !visible.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(visible) { comment in
                            row(comment)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Новый комментарий", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isDraftFocused)
                    .onSubmit(send)
                    .padding(8)
                    .background(theme.contrast.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Добавить комментарий")
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { isDraftFocused = true }
    }

    private func send() {
        guard model.addComment(to: blockId, text: draft) != nil else { return }
        LumenSounds.play(.tap)
        draft = ""
        isDraftFocused = true
    }

    @ViewBuilder
    private func row(_ comment: BlockComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.createdAt.lumenRelative)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                if comment.editedAt != nil {
                    Text("· изменён")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button {
                    model.setCommentResolved(comment.id, in: blockId, !comment.isResolved)
                } label: {
                    Image(systemName: comment.isResolved ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        .foregroundStyle(comment.isResolved ? theme.textSecondary : theme.accent)
                }
                .buttonStyle(.plain)
                .help(comment.isResolved ? "Вернуть" : "Решено")
                Menu {
                    Button {
                        editingId = comment.id
                        editingText = comment.text
                    } label: {
                        Label("Изменить", systemImage: "pencil")
                    }
                    Button {
                        copyText(comment.text)
                    } label: {
                        Label("Скопировать", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        model.deleteComment(comment.id, in: blockId)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(theme.textSecondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
            }
            if editingId == comment.id {
                TextField("Комментарий", text: $editingText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .padding(6)
                    .background(theme.contrast.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit { finishEditing(comment) }
                HStack {
                    Spacer()
                    Button("Отмена") { editingId = nil }
                    Button("Сохранить") { finishEditing(comment) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            } else {
                Text(comment.text)
                    .font(.callout)
                    .foregroundStyle(theme.textPrimary)
                    .strikethrough(comment.isResolved)
                    .opacity(comment.isResolved ? 0.6 : 1)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func finishEditing(_ comment: BlockComment) {
        model.editComment(comment.id, in: blockId, text: editingText)
        editingId = nil
    }
}
