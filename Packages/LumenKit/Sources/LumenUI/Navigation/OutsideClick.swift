import SwiftUI

#if os(macOS)
import AppKit

extension View {
    /// Mac: щелчок по окну, к которому прикреплён этот лист, закрывает лист.
    /// Системный лист на Mac так не умеет, а поиск ⌘K должен закрываться, как Spotlight.
    func dismissesOnOutsideClick(_ action: @escaping () -> Void) -> some View {
        background(OutsideClickCatcher(action: action))
    }
}

private struct OutsideClickCatcher: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class CatcherView: NSView {
        var action: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                let windowNumber = event.windowNumber
                let handled = MainActor.assumeIsolated {
                    self?.handleClick(windowNumber: windowNumber) ?? false
                }
                return handled ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        /// Только окно под листом: клики в самом листе, в его меню и в других окнах не трогаем.
        private func handleClick(windowNumber: Int) -> Bool {
            guard let parent = window?.sheetParent, parent.windowNumber == windowNumber else { return false }
            action()
            return true
        }
    }
}
#else
extension View {
    /// На iPad лист и так закрывается касанием мимо него, на iPhone он на весь экран.
    func dismissesOnOutsideClick(_ action: @escaping () -> Void) -> some View { self }
}
#endif
