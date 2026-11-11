import LumenThemes
import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Применяет оформление «Кабинета»: цвета, тёмный режим, шрифт с засечками.
    /// Вешается один раз на корень окна, всё внутри (и листы) берёт тему из окружения.
    public func lumenThemed() -> some View {
        modifier(LumenThemeHost())
    }
}

extension View {
    /// Верхняя полоса окна (заголовок, кнопки) в цвет кабинета, а не системная серая.
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
    private let theme = Theme.study

    func body(content: Content) -> some View {
        content
            .environment(\.lumenTheme, theme)
            .fontDesign(theme.fontDesign)
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
            #if os(macOS)
            .background(WindowChrome(color: theme.backgroundStops.first ?? .clear))
            #endif
            .task { AppIcon.resetToPrimary() }
    }
}

/// Раньше значок менялся вместе с темой. Тем больше нет, и значок «Кабинета» стал основным:
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
