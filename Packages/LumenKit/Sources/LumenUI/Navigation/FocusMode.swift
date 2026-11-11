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

    /// Таймер учёбы: когда закончится. `nil`, пока он не запущен.
    private(set) var timerEnd: Date?
    private var timerTask: Task<Void, Never>?

    /// Сколько длится один заход, как в помодоро.
    nonisolated static let studyMinutes = 25

    func toggle() {
        LumenSounds.play(isOn ? .panelClose : .panelOpen)
        withAnimation(.easeInOut(duration: 0.3)) { isOn.toggle() }
    }

    func startTimer() {
        LumenSounds.play(.toggle)
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

