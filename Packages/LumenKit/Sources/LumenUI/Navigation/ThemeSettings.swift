import LumenThemes
import SwiftUI

extension View {
    /// Применяет тему, выбранную в Настройках: цвета, светлый или тёмный режим, начертание шрифта.
    /// Вешается один раз на корень окна, всё внутри (и листы) берёт тему из окружения.
    public func lumenThemed() -> some View {
        modifier(LumenThemeHost())
    }
}

extension View {
    /// Верхняя полоса окна (заголовок, кнопки) в цвет темы, а не системная серая.
    func themedToolbar() -> some View {
        modifier(ThemedToolbar())
    }
}

private struct ThemedToolbar: ViewModifier {
    @Environment(\.lumenTheme) private var theme

    func body(content: Content) -> some View {
        let fill = theme.backgroundStops.first ?? .clear
        #if os(macOS)
        content
            .toolbarBackground(fill, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbarColorScheme(theme.colorScheme, for: .windowToolbar)
        #else
        content
            .toolbarBackground(fill, for: .navigationBar, .tabBar)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar, .tabBar)
        #endif
    }
}

private struct LumenThemeHost: ViewModifier {
    @AppStorage(Theme.storageKey) private var themeId = Theme.sunset.id

    func body(content: Content) -> some View {
        let theme = Theme.named(themeId)
        content
            .environment(\.lumenTheme, theme)
            .fontDesign(theme.fontDesign)
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
            #if os(macOS)
            .background(WindowChrome(color: theme.backgroundStops.first ?? .clear))
            #endif
            .animation(.easeInOut(duration: 0.25), value: themeId)
            // Значок приложения тоже под тему.
            .onChange(of: themeId, initial: true) { _, id in
                AppIconSwitcher.apply(Theme.named(id))
            }
    }
}

/// Список тем в Настройках: маленькое превью, название и строка о характере темы.
struct ThemePicker: View {
    @AppStorage(Theme.storageKey) private var themeId = Theme.sunset.id

    var body: some View {
        ForEach(Theme.all) { theme in
            let isSelected = theme.id == Theme.named(themeId).id
            Button {
                themeId = theme.id
            } label: {
                HStack(spacing: 14) {
                    ThemePreview(theme: theme)
                        .frame(width: 76, height: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.name)
                            .font(.body.weight(.semibold))
                            .fontDesign(theme.fontDesign)
                        Text(theme.caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyHint("Тема: \(theme.name)") { themeId = theme.id }
            .accessibilityIdentifier("theme.\(theme.id)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// Миниатюра темы: её фон, свечение, стеклянная карточка, яркая карточка и акцент.
private struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack(alignment: .topLeading) {
            theme.backgroundGradient
            RadialGradient(
                colors: [theme.glow.opacity(theme.glowStrength), theme.glow.opacity(0)],
                center: UnitPoint(x: 0.9, y: 0), startRadius: 0, endRadius: 50
            )
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: min(theme.cardRadius / 3, 6), style: .continuous)
                    .fill(theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: min(theme.cardRadius / 3, 6), style: .continuous)
                            .strokeBorder(theme.cardStroke, lineWidth: 0.5)
                    )
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(theme.textPrimary).frame(width: 18, height: 3)
                            Capsule().fill(theme.textSecondary).frame(width: 12, height: 2)
                            Circle().fill(theme.accent).frame(width: 6, height: 6)
                        }
                        .padding(5)
                    }
                RoundedRectangle(cornerRadius: min(theme.cardRadius / 3, 6), style: .continuous)
                    .fill(LinearGradient(colors: theme.vividCard(0).colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 18)
            }
            .padding(7)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
