import LumenThemes
import SwiftUI

/// Командная строка внизу окна для тем без боковой панели («Монохром»).
/// Нажатие или ⌘K открывает палитру: перейти, создать, найти. Справа подсказки главных клавиш.
struct CommandLineBar: View {
    /// Где сейчас: «lumen / входящие», чтобы без сайдбара было видно, куда попал.
    let location: String
    var onOpen: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text("⌘K")
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
                Text("что сделать? перейти, создать, найти")
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                ViewThatFits(in: .horizontal) {
                    hints(full: true)
                    hints(full: false)
                    Text(location).foregroundStyle(theme.textSecondary)
                }
            }
            .font(.system(.callout, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.menuFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.cardStroke, lineWidth: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .accessibilityLabel("Командная строка")
        .accessibilityHint("Открывает поиск и команды, как ⌘K")
        .accessibilityIdentifier("commandLineBar")
    }

    private func hints(full: Bool) -> some View {
        HStack(spacing: 14) {
            Text(location).foregroundStyle(theme.textPrimary)
            if full {
                hint("⌘N", "заметка")
                hint("⇧⌘N", "задача")
                hint("⌘O", "книга")
            }
            hint("⌘[", "назад")
        }
        .fixedSize()
    }

    private func hint(_ keys: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(theme.contrast.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(title)
        }
        .foregroundStyle(theme.textSecondary)
    }
}
