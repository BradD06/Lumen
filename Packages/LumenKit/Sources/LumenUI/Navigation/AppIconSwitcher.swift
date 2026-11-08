import LumenThemes
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Значок приложения меняется вместе с темой. На iPhone и iPad это запасной значок
/// (iOS сама показывает об этом короткое сообщение), на Mac значок в Dock, пока приложение открыто.
@MainActor
enum AppIconSwitcher {
    static func apply(_ theme: Theme) {
        #if os(iOS)
        let application = UIApplication.shared
        let name = theme.appIconSuffix.map { "AppIcon-\($0)" }
        guard application.supportsAlternateIcons, application.alternateIconName != name else { return }
        Task {
            do {
                try await application.setAlternateIconName(name)
            } catch {
                lumenLog.error("App icon change failed: \(String(describing: error), privacy: .public)")
            }
        }
        #elseif os(macOS)
        // nil возвращает основной значок из сборки.
        NSApp.applicationIconImage = theme.appIconSuffix.flatMap { NSImage(named: "DockIcon-\($0)") }
        #endif
    }
}
