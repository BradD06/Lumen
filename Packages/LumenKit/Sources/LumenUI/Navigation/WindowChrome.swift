#if os(macOS)
import AppKit
import SwiftUI

/// Заголовок окна на Mac в цвет темы, в том числе на весь экран.
/// `toolbarBackground` красит полосу только в обычном окне: на весь экран macOS выносит
/// панель инструментов в отдельное окно со своей серой подложкой. Здесь красим и его.
struct WindowChrome: NSViewRepresentable {
    var color: Color

    func makeNSView(context: Context) -> ChromeView {
        ChromeView()
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.color = NSColor(color)
    }

    final class ChromeView: NSView {
        var color: NSColor = .windowBackgroundColor {
            didSet { apply() }
        }
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // Панель на весь экран появляется и пропадает вместе с режимом, перекрашиваем каждый раз.
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            apply()
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        private func apply() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.backgroundColor = color
            // Окно с панелью инструментов на весь экран: своё у каждого приложения, ищем по имени класса.
            for other in NSApp.windows where String(describing: type(of: other)).contains("FullScreen") {
                other.backgroundColor = color
                other.isOpaque = true
                if let content = other.contentView {
                    Self.flatten(content, color: color)
                }
            }
        }

        /// Серая «стеклянная» подложка панели прячется, под ней фон окна в цвет темы.
        private static func flatten(_ view: NSView, color: NSColor) {
            if let effect = view as? NSVisualEffectView {
                effect.isHidden = true
            }
            for child in view.subviews {
                flatten(child, color: color)
            }
        }
    }
}
#endif
