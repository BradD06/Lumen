import LumenCore
import LumenThemes
import SwiftUI

/// Режим фокуса: в редакторе гаснет всё, кроме абзаца с курсором, а окно прячет
/// комнаты и вкладки. Один на приложение, включается кнопкой на странице или ⇧⌘F.
@MainActor
@Observable
final class FocusModeState {
    static let shared = FocusModeState()

    var isOn = false
    /// Фокус включили лампой на полке главного экрана: вокруг темнеет, внизу таймер.
    private(set) var isLampLit = false

    /// Таймер учёбы: когда закончится. `nil`, пока он не запущен.
    private(set) var timerEnd: Date?
    private var timerTask: Task<Void, Never>?

    /// Сколько длится один заход, как в помодоро.
    nonisolated static let studyMinutes = 25

    func toggle() {
        LumenSounds.play(isOn ? .panelClose : .panelOpen)
        withAnimation(.easeInOut(duration: 0.3)) {
            isOn.toggle()
            if !isOn { isLampLit = false }
        }
    }

    /// Лампа: включает фокус и таймер учёбы, ещё раз нажали, и свет вернулся.
    func toggleLamp() {
        LumenSounds.play(.lamp)
        if isLampLit {
            stopTimer()
            withAnimation(.easeInOut(duration: 0.5)) {
                isLampLit = false
                isOn = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.5)) {
                isLampLit = true
                isOn = true
            }
            startTimer(silently: true)
        }
    }

    func startTimer(silently: Bool = false) {
        if !silently { LumenSounds.play(.toggle) }
        timerTask?.cancel()
        let duration = Self.studyMinutes * 60
        timerEnd = Date.now.addingTimeInterval(TimeInterval(duration))
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.finishTimer()
        }
    }

    func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        timerEnd = nil
    }

    private func finishTimer() {
        timerTask = nil
        timerEnd = nil
        LumenSounds.play(.panelOpen)
        NoticeCenter.shared.show("\(Self.studyMinutes) минут прошли. Пора сделать перерыв")
    }

    /// Сколько осталось, «24:59».
    nonisolated static func remaining(until end: Date, now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

