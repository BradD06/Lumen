import LumenCore
import LumenThemes
import SwiftUI

/// Режим фокуса: в редакторе гаснет всё, кроме абзаца с курсором, а окно прячет
/// сайдбар и вкладки. Один на приложение, включается кнопкой на странице или ⇧⌘F.
@MainActor
@Observable
final class FocusModeState {
    static let shared = FocusModeState()

    var isOn = false

    func toggle() {
        LumenSounds.play(isOn ? .panelClose : .panelOpen)
        withAnimation(.easeInOut(duration: 0.3)) { isOn.toggle() }
    }
}

/// Узкая полоса значков с подписями слева на iPad, когда сайдбар спрятан (например, в
/// вертикальном положении): разделы, «Создать», поиск и настройки всегда на виду.
struct IconRail: View {
    let selection: SidebarItem?
    var inboxCount: Int = 0
    var onSelect: (SidebarItem) -> Void
    var onCreate: (CreateKind) -> Void
    var onSearch: () -> Void
    var onSettings: () -> Void

    @State private var isCreating = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            Button {
                isCreating = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.vividCard(0).foreground)
                    .frame(width: 54, height: 54)
                    .background(
                        LinearGradient(colors: theme.vividCard(0).colors, startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(color: (theme.vividCard(0).colors.last ?? .orange).opacity(0.4), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Создать")
            .popover(isPresented: $isCreating) {
                CreateMenuList { kind in
                    isCreating = false
                    onCreate(kind)
                }
                .presentationCompactAdaptation(.popover)
            }
            .padding(.bottom, 10)

            item("Сегодня", "sun.max", .home)
            item("Входящие", "tray", .inbox, badge: inboxCount)
            item("Задачи", "checklist", .tasks)
            item("Библиотека", "books.vertical", .library(nil))
            railButton("Поиск", "magnifyingglass", isSelected: false, action: onSearch)
            Spacer()
            railButton("Настройки", "gearshape", isSelected: false, action: onSettings)
        }
        .padding(.vertical, 16)
        .frame(width: 88)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.textPrimary.opacity(0.08)).frame(width: 1)
        }
    }

    private func item(_ title: String, _ image: String, _ target: SidebarItem, badge: Int = 0) -> some View {
        railButton(title, image, isSelected: selection == target, badge: badge) { onSelect(target) }
    }

    private func railButton(_ title: String, _ image: String, isSelected: Bool, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: image)
                    .font(.title3)
                    .frame(height: 24)
                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? theme.accent : theme.textPrimary)
            .frame(width: 76, height: 58)
            .background(isSelected ? theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(theme.vividCard(2).foreground)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(theme.vividCard(2).colors.first ?? .purple, in: Capsule())
                        .offset(x: -10, y: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyHint(title, perform: action)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge)" : title)
    }
}
