import LumenThemes
import SwiftUI

/// Командная строка внизу окна для тем без боковой панели («Монохром»).
/// Нажатие или ⌘K открывает палитру: перейти, создать, найти. ⌘J ставит буквы на всё, что можно нажать.
/// Справа подсказки главных клавиш.
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
        .keyHint("Командная строка", perform: onOpen)
        .accessibilityLabel("Командная строка")
        .accessibilityHint("Открывает поиск и команды, как ⌘K")
        .accessibilityIdentifier("commandLineBar")
    }

    private func hints(full: Bool) -> some View {
        HStack(spacing: 14) {
            Text(location).foregroundStyle(theme.textPrimary)
            hint("⌘J", "нажать")
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

extension SidebarItem {
    /// Короткое «где я» для командной строки «Монохрома»: «сегодня», «книга».
    static func commandLinePlace(_ item: SidebarItem?) -> String {
        switch item {
        case .home, nil: "сегодня"
        case .inbox: "входящие"
        case .tasks: "задачи"
        case .library: "библиотека"
        case .trash: "корзина"
        case .page: "страница"
        case .source: "книга"
        case .sourceInfo: "о книге"
        }
    }
}

#if os(iOS)

/// «Монохром» на iPhone: вместо вкладок одна строка внизу, как приглашение терминала.
/// Нажатие открывает команды и поиск (то же, что ⌘K на Mac), «+» сразу начинает заметку.
struct PhoneCommandBar: View {
    let location: String
    var onOpen: () -> Void
    var onNewNote: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Text("›")
                        .fontWeight(.bold)
                        .foregroundStyle(theme.accent)
                    Text(location)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text("что сделать?")
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Командная строка, \(location)")
            .accessibilityHint("Открывает поиск и команды: перейти, создать, найти")
            .accessibilityIdentifier("commandLineBar")

            Button(action: onNewNote) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Новая заметка")
        }
        .font(.system(.callout, design: .monospaced))
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 46)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.menuFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                )
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

#endif
