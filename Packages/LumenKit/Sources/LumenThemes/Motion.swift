import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Общие движения Lumen: каждая анимация берёт кривую отсюда, поэтому всё движется одинаково.
/// Это пружины: если движение прервать на полпути (быстро навёл и убрал мышь, дважды нажал),
/// новое продолжает с той же скоростью, без рывка, как у кривых с фиксированным временем.
/// С «Уменьшить движение» в системе вместо пружин короткое мягкое затухание.
@MainActor
public enum LumenMotion {
    /// Наведение, нажатие, мелкие переключатели: отклик сразу, без отскока.
    public static var quick: Animation {
        reduceMotion ? fade : .spring(duration: 0.22, bounce: 0)
    }

    /// Обычные переходы: вкладки, панели, списки, появление плашек и меню.
    public static var standard: Animation {
        reduceMotion ? fade : .spring(duration: 0.34, bounce: 0.06)
    }

    /// Крупные предметы: карточки, листы, книга, которая выдвигается с полки.
    public static var gentle: Animation {
        reduceMotion ? fade : .spring(duration: 0.5, bounce: 0.14)
    }

    /// Смена экрана в панели: новый экран проявляется, старый быстро гаснет.
    /// В UI-тестах экраны меняются сразу, чтобы старый не мешал искать кнопки нового.
    public static var screen: Animation? {
        if isUITesting { return nil }
        return reduceMotion ? fade : .spring(duration: 0.3, bounce: 0)
    }

    /// Только прозрачность.
    public static let fade = Animation.easeInOut(duration: 0.18)

    /// Включено ли в системе «Уменьшить движение».
    public static var reduceMotion: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        UIAccessibility.isReduceMotionEnabled
        #endif
    }

    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
}

extension AnyTransition {
    /// Новый экран проявляется и чуть подрастает, старый просто быстро гаснет:
    /// два экрана не просвечивают друг сквозь друга.
    @MainActor
    public static var lumenScreen: AnyTransition {
        if LumenMotion.reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    /// Плашки и подсказки: появляются с лёгким увеличением, без «Уменьшить движение» и просто гаснут с ним.
    @MainActor
    public static var lumenPop: AnyTransition {
        LumenMotion.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94))
    }
}
