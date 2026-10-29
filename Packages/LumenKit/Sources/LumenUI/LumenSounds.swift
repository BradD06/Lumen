import AVFoundation
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Звуки интерфейса. Все синтезируются в коде: файлов со звуками в приложении нет.
public enum LumenSound: CaseIterable, Sendable {
    /// Мягкий щелчок.
    case tap
    /// Плитку подняли на холсте библиотеки.
    case pickUp
    /// Плитку отпустили.
    case drop
    /// Плитку положили в папку: шорох бумаги и мягкий стук.
    case dropIntoFolder
    /// Новая страница, папка или подстраница.
    case create
    /// В корзину: шорох вниз.
    case trash
    /// Из корзины обратно.
    case restore
    case panelOpen
    case panelClose
    /// Галочка задачи.
    case toggle
    /// Плитки разложили по сетке.
    case arrange
    /// Почти неслышный тик при переходе в папку или на страницу.
    case navigate

    /// Длительность в секундах: конец последнего голоса.
    var duration: Double {
        voices.map { $0.start + $0.length }.max() ?? 0
    }

    /// Из чего собран звук: тоны со скольжением частоты и мягкий шум.
    fileprivate var voices: [SoundVoice] {
        switch self {
        case .tap:
            [SoundVoice(start: 0, length: 0.05, from: 1800, to: 1200, gain: 0.5, decay: 90, noise: 0.5)]
        case .navigate:
            [SoundVoice(start: 0, length: 0.04, from: 2400, to: 2000, gain: 0.22, decay: 120, noise: 0.3)]
        case .pickUp:
            [SoundVoice(start: 0, length: 0.12, from: 420, to: 760, gain: 0.45, decay: 25)]
        case .drop:
            [SoundVoice(start: 0, length: 0.14, from: 260, to: 140, gain: 0.6, decay: 35, noise: 0.25)]
        case .dropIntoFolder:
            [
                SoundVoice(start: 0, length: 0.12, from: 900, to: 500, gain: 0.35, decay: 20, noise: 0.9),
                SoundVoice(start: 0.08, length: 0.14, from: 520, to: 330, gain: 0.5, decay: 30),
            ]
        case .create:
            [
                SoundVoice(start: 0, length: 0.08, from: 500, to: 900, gain: 0.4, decay: 30),
                SoundVoice(start: 0.06, length: 0.1, from: 760, to: 1300, gain: 0.35, decay: 35),
            ]
        case .trash:
            [SoundVoice(start: 0, length: 0.25, from: 700, to: 180, gain: 0.4, decay: 12, noise: 0.8)]
        case .restore:
            [
                SoundVoice(start: 0, length: 0.1, from: 523, to: 523, gain: 0.35, decay: 28),
                SoundVoice(start: 0.08, length: 0.12, from: 784, to: 784, gain: 0.35, decay: 26),
            ]
        case .panelOpen:
            [SoundVoice(start: 0, length: 0.22, from: 300, to: 1200, gain: 0.3, decay: 10, noise: 0.85)]
        case .panelClose:
            [SoundVoice(start: 0, length: 0.2, from: 1100, to: 280, gain: 0.3, decay: 12, noise: 0.85)]
        case .toggle:
            [
                SoundVoice(start: 0, length: 0.04, from: 1500, to: 1400, gain: 0.4, decay: 80, noise: 0.3),
                SoundVoice(start: 0.03, length: 0.06, from: 1047, to: 1047, gain: 0.35, decay: 45),
            ]
        case .arrange:
            [
                SoundVoice(start: 0, length: 0.06, from: 1300, to: 1200, gain: 0.3, decay: 60, noise: 0.5),
                SoundVoice(start: 0.05, length: 0.06, from: 1100, to: 1000, gain: 0.3, decay: 60, noise: 0.5),
                SoundVoice(start: 0.1, length: 0.06, from: 1500, to: 1400, gain: 0.3, decay: 60, noise: 0.5),
            ]
        }
    }
}

/// Один голос звука: тон, частота которого плавно скользит, с затуханием и долей шума.
private struct SoundVoice {
    var start: Double
    var length: Double
    var from: Double
    var to: Double
    var gain: Double
    /// Скорость экспоненциального затухания, в единицах за секунду.
    var decay: Double
    /// 0 это чистый тон, 1 только шум.
    var noise: Double = 0
}

public enum LumenSounds {
    /// Ключ настройки «Звуки». По умолчанию звуки включены.
    public static let enabledKey = "sounds.enabled"

    static let sampleRate = 44_100.0

    /// Проигрывает звук, если звуки включены. Ошибки звука молча пропускаются.
    /// На iPhone и iPad вместе со звуком лёгкая отдача, если она к нему подходит.
    @MainActor
    public static func play(_ sound: LumenSound) {
        guard UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true else { return }
        SoundEngine.shared.play(sound)
        #if os(iOS)
        haptic(for: sound)
        #endif
    }

    #if os(iOS)
    @MainActor
    private static func haptic(for sound: LumenSound) {
        switch sound {
        case .pickUp: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .drop, .dropIntoFolder: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .create, .restore: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .trash: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .toggle, .tap, .arrange: UISelectionFeedbackGenerator().selectionChanged()
        case .panelOpen, .panelClose, .navigate: break
        }
    }
    #endif

    /// Звук одним буфером, моно. Шум детерминированный, чтобы звук не менялся от раза к разу.
    static func render(_ sound: LumenSound) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount((sound.duration * sampleRate).rounded())
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for index in 0..<Int(frames) { samples[index] = 0 }

        var seed: UInt32 = 0x9E37_79B9
        for voice in sound.voices {
            let first = Int(voice.start * sampleRate)
            let count = min(Int(voice.length * sampleRate), Int(frames) - first)
            guard count > 0 else { continue }
            var phase = 0.0
            var filtered = 0.0
            for offset in 0..<count {
                let t = Double(offset) / sampleRate
                let progress = Double(offset) / Double(count)
                // Частота скользит по экспоненте: на слух это ровное движение.
                let frequency = voice.from * pow(voice.to / voice.from, progress)
                phase += 2 * .pi * frequency / sampleRate
                // Немного второй гармоники делает тон теплее.
                let tone = sin(phase) + 0.25 * sin(2 * phase)
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let white = Double(seed) / Double(UInt32.max) * 2 - 1
                // Простой фильтр низких частот: шум становится мягким шорохом.
                filtered += 0.3 * (white - filtered)
                let attack = min(t / 0.004, 1)
                let release = min(Double(count - offset) / (0.005 * sampleRate), 1)
                let envelope = attack * release * exp(-voice.decay * t)
                let value = voice.gain * envelope * ((1 - voice.noise) * tone + voice.noise * filtered * 2)
                samples[first + offset] += Float(value)
            }
        }
        for index in 0..<Int(frames) {
            samples[index] = max(-1, min(1, samples[index]))
        }
        return buffer
    }
}

/// Движок со своей очередью: звук готовится и запускается не на главном потоке.
private final class SoundEngine: @unchecked Sendable {
    static let shared = SoundEngine()

    private let queue = DispatchQueue(label: "Lumen.sounds", qos: .userInteractive)
    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [LumenSound: AVAudioPCMBuffer] = [:]
    /// В UI-тестах звук не нужен.
    private let isDisabled = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    func play(_ sound: LumenSound) {
        guard !isDisabled else { return }
        queue.async { self.playNow(sound) }
    }

    private func playNow(_ sound: LumenSound) {
        guard let engine = startedEngine() else { return }
        let buffer: AVAudioPCMBuffer
        if let cached = buffers[sound] {
            buffer = cached
        } else {
            guard let rendered = LumenSounds.render(sound) else { return }
            buffers[sound] = rendered
            buffer = rendered
        }
        guard engine.isRunning || (try? engine.start()) != nil else { return }
        // Несколько плееров по кругу: быстрые звуки подряд не обрывают друг друга.
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
    }

    private func startedEngine() -> AVAudioEngine? {
        if let engine { return engine }
        #if os(iOS)
        // Звуки интерфейса не глушат музыку и молчат в беззвучном режиме.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        #endif
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: LumenSounds.sampleRate, channels: 1) else {
            return nil
        }
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.25
        do {
            try engine.start()
        } catch {
            players = []
            return nil
        }
        self.engine = engine
        return engine
    }
}

/// Переключатель «Звуки» для меню приложения.
public struct SoundCommands: Commands {
    @AppStorage(LumenSounds.enabledKey) private var isEnabled = true

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .appSettings) {
            Toggle("Звуки", isOn: $isEnabled)
        }
    }
}
