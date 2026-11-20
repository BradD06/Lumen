import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension View {
    /// Применяет оформление «Острова»: светлая или тёмная тема, цвета, шрифт.
    /// Вешается один раз на корень окна, всё внутри (и листы) берёт тему из окружения.
    public func lumenThemed() -> some View {
        modifier(LumenThemeHost())
    }
}

extension View {
    /// Верхняя полоса окна (заголовок, кнопки) в цвет фона, а не системная серая.
    func themedToolbar() -> some View {
        modifier(ThemedToolbar())
    }
}

private struct ThemedToolbar: ViewModifier {
    @Environment(\.lumenTheme) private var theme

    func body(content: Content) -> some View {
        let fill = theme.background
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
    @Setting(AppearanceMode.storageKey) private var mode = AppearanceMode.system
    @Setting(CoverTint.enabledKey) private var followsCover = true
    /// Светлая или тёмная сейчас система (или то, что попросили у окна).
    @Environment(\.colorScheme) private var systemScheme
    private let coverTint = CoverTint.shared

    private var theme: Theme {
        let base = mode.theme(system: systemScheme)
        // Окно в цвет обложки открытой заметки, если это включено в Настройках.
        guard followsCover, let cover = coverTint.color else { return base }
        return base.tinted(by: cover)
    }

    func body(content: Content) -> some View {
        let theme = self.theme
        return content
            .environment(\.lumenTheme, theme)
            .fontDesign(theme.fontDesign)
            .tint(theme.accent)
            #if os(macOS)
            .background(WindowChrome(color: theme.background))
            #endif
            .task { AppIcon.resetToPrimary() }
            .task(id: mode) { WindowAppearance.apply(mode) }
    }
}

/// Светлая, тёмная или как в системе: просим у самого окна, а не через `preferredColorScheme`.
/// Тот не умеет вернуться к «как в системе»: окно остаётся в последней выбранной схеме.
@MainActor
enum WindowAppearance {
    static func apply(_ mode: AppearanceMode) {
        #if os(macOS)
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        #else
        let style: UIUserInterfaceStyle = switch mode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
        #endif
    }
}

/// Раздел «Оформление» в Настройках: как в системе, светлая или тёмная, и окно в цвет обложки.
struct AppearanceSection: View {
    @Setting(AppearanceMode.storageKey) private var mode = AppearanceMode.system
    @Setting(CoverTint.enabledKey) private var followsCover = true

    var body: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(AppearanceMode.allCases) { option in
                    AppearanceSwatch(mode: option, isSelected: option == mode) {
                        mode = option
                    }
                    .keyHint("Оформление: \(option.title)") { mode = option }
                }
            }
            .padding(.vertical, 4)
            Toggle("Окно в цвет обложки заметки", isOn: $followsCover)
                .accessibilityIdentifier("settings.coverTint")
                .keyHint("Окно в цвет обложки") { followsCover.toggle() }
        } header: {
            Text("Оформление")
        } footer: {
            Text(followsCover
                ? "Открыта заметка с обложкой: фон окна и акцент берут цвет обложки."
                : "Окно всегда в цветах темы, какая бы обложка ни была у заметки.")
        }
    }
}

/// Плитка выбора: кусочек фона, белый (или графитовый) лист и остров внизу.
/// «Как в системе» показывает обе темы пополам.
private struct AppearanceSwatch: View {
    @Environment(\.lumenTheme) private var current
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? current.accent : current.cardStroke, lineWidth: isSelected ? 2 : 1)
                    }
                Text(mode.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? current.textPrimary : current.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Оформление: \(mode.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("appearance.\(mode.rawValue)")
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .light: ThemeMiniature(theme: .light)
        case .dark: ThemeMiniature(theme: .dark)
        case .system:
            HStack(spacing: 0) {
                ThemeMiniature(theme: .light)
                ThemeMiniature(theme: .dark)
            }
        }
    }
}

/// Маленький экран темы: фон, лист с двумя строчками и капсула острова.
private struct ThemeMiniature: View {
    let theme: Theme

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.background
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(theme.textPrimary.opacity(0.8)).frame(width: 30, height: 4)
                Capsule().fill(theme.textSecondary.opacity(0.5)).frame(width: 40, height: 3)
                Capsule().fill(theme.textSecondary.opacity(0.5)).frame(width: 26, height: 3)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.sheet, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
            HStack(spacing: 3) {
                Circle().fill(theme.surface2).frame(width: 7, height: 7)
                Circle().fill(theme.textTertiary).frame(width: 5, height: 5)
                Circle().fill(theme.accent).frame(width: 7, height: 7)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(theme.glassFill, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.cardStroke))
            .padding(.bottom, 4)
        }
    }
}

/// Раньше значок менялся вместе с темой. Теперь значок один:
/// на iPhone и iPad снимаем запасной значок, если его когда-то поставили.
@MainActor
enum AppIcon {
    static func resetToPrimary() {
        #if os(iOS)
        let application = UIApplication.shared
        guard application.supportsAlternateIcons, application.alternateIconName != nil else { return }
        Task {
            try? await application.setAlternateIconName(nil)
        }
        #endif
    }
}
