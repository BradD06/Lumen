import AVFoundation
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Звуки интерфейса в духе бумаги и книг: перелистывание, шорох, стук книги о стол.
/// Все синтезируются в коде из отфильтрованного шума и низких тонов, файлов со звуками нет.
public enum LumenSound: CaseIterable, Sendable {
    /// Карандашный тик по бумаге.
    case tap
    /// Плитку подняли: короткий шорох листа.
    case pickUp
    /// Плитку отпустили: книгу положили на стол.
    case drop
    /// Плитку положили в папку: лист скользит внутрь и мягко стукает картон.
    case dropIntoFolder
    /// Новая страница, папка или подстраница: мягкий бумажный хлопок.
    case create
    /// В корзину: бумагу сминают.
    case trash
    /// Из корзины: лист расправляют, шорох вверх.
    case restore
    /// Панель открылась: страницу перелистнули.
    case panelOpen
    /// Панель закрылась: страницу перелистнули обратно.
    case panelClose
    /// Галочка задачи: карандашный тик.
    case toggle
    /// Плитки разложили по сетке: колоду карточек перетасовали.
    case arrange
    /// Переход в папку или на страницу: лёгкий щелчок уголка страницы.
    case navigate

    /// Длительность в секундах: конец последнего голоса.
    var duration: Double {
        voices.map { $0.start + $0.length }.max() ?? 0
    }

    /// Пиковая громкость звука после нормализации, от 0 до 1.
    fileprivate var level: Double {
        switch self {
        case .navigate, .tap: 0.45
        case .toggle, .pickUp, .arrange: 0.55
        case .panelOpen, .panelClose, .restore: 0.6
        case .create, .trash, .dropIntoFolder: 0.7
        case .drop: 0.8
        }
    }

    /// Из чего собран звук.
    fileprivate var voices: [SoundVoice] {
        switch self {
        case .tap:
            [
                .rustle(at: 0, length: 0.03, band: 3000, to: 2800, decay: 150, width: 0.45),
                .tone(at: 0, length: 0.02, from: 2200, to: 2000, gain: 0.15, decay: 220),
            ]
        case .toggle:
            [
                .rustle(at: 0, length: 0.035, band: 4200, to: 3800, decay: 130, width: 0.4),
                .tone(at: 0, length: 0.02, from: 2600, to: 2400, gain: 0.12, decay: 200),
            ]
        case .navigate:
            [
                .rustle(at: 0, length: 0.08, band: 2500, to: 4500, attack: 0.01, decay: 30, crackle: 0.15),
                .rustle(at: 0.06, length: 0.03, band: 3200, to: 3000, gain: 0.6, decay: 120),
            ]
        case .pickUp:
            [.rustle(at: 0, length: 0.12, band: 1800, to: 3200, attack: 0.02, decay: 25, crackle: 0.2)]
        case .drop:
            [
                // Глухой деревянный стук: низкий тон быстро гаснет.
                .tone(at: 0, length: 0.16, from: 165, to: 115, gain: 1, decay: 38),
                .tone(at: 0, length: 0.05, from: 330, to: 230, gain: 0.25, decay: 80),
                .rustle(at: 0, length: 0.05, band: 700, to: 400, gain: 0.35, decay: 70, width: 1.2),
            ]
        case .dropIntoFolder:
            [
                .rustle(at: 0, length: 0.16, band: 1500, to: 2600, gain: 0.8, attack: 0.03, decay: 12, crackle: 0.1),
                .tone(at: 0.13, length: 0.13, from: 140, to: 100, gain: 0.9, decay: 40),
                .rustle(at: 0.13, length: 0.04, band: 500, to: 450, gain: 0.4, decay: 80, width: 1.2),
            ]
        case .create:
            [
                .tone(at: 0, length: 0.09, from: 320, to: 260, gain: 0.7, decay: 45),
                .rustle(at: 0, length: 0.04, band: 1200, to: 1100, gain: 0.6, decay: 90, width: 1.1),
                .rustle(at: 0.03, length: 0.08, band: 2400, to: 3200, gain: 0.35, decay: 40),
            ]
        case .trash:
            // Комок бумаги: короткие случайные шорохи разной высоты.
            zip(
                [0, 0.03, 0.055, 0.09, 0.12, 0.15, 0.19, 0.22],
                [2200, 3600, 1800, 4200, 2600, 3200, 2000, 3800]
            ).enumerated().map { index, grain in
                .rustle(
                    at: grain.0, length: 0.04, band: grain.1, to: grain.1 * 0.85,
                    gain: index.isMultiple(of: 2) ? 1 : 0.7, decay: 60, crackle: 0.4
                )
            }
        case .restore:
            [.rustle(at: 0, length: 0.22, band: 1400, to: 3600, attack: 0.05, decay: 9, crackle: 0.15)]
        case .panelOpen:
            [
                // Страница поднимается, проходит дугу и шлёпает краем.
                .rustle(at: 0, length: 0.26, band: 1200, to: 3800, attack: 0.12, decay: 6, crackle: 0.1),
                .rustle(at: 0.24, length: 0.06, band: 3500, to: 3000, gain: 0.7, decay: 60),
            ]
        case .panelClose:
            [
                .rustle(at: 0, length: 0.05, band: 3500, to: 3200, gain: 0.7, decay: 60),
                .rustle(at: 0.02, length: 0.28, band: 3500, to: 1100, attack: 0.05, decay: 10, crackle: 0.1),
            ]
        case .arrange:
            // Колода карточек: быстрые щелчки краёв друг о друга.
            zip([0, 0.04, 0.08, 0.12, 0.16], [3000, 3400, 2800, 3600, 3200]).map { start, band in
                .rustle(at: start, length: 0.05, band: band, to: band * 0.9, gain: 0.8, decay: 70, crackle: 0.25)
            }
        }
    }
}

/// Один голос звука: низкий тон (стук, хлопок) или полосовой шум (бумага).
private struct SoundVoice {
    enum Kind {
        case tone
        /// `width` это затухание фильтра: меньше значит уже полоса и «звонче» шорох.
        case rustle(width: Double, crackle: Double)
    }

    var kind: Kind
    var start: Double
    var length: Double
    /// Частота тона или середина полосы шума в начале и в конце.
    var from: Double
    var to: Double
    var gain: Double
    var attack: Double
    /// Скорость экспоненциального затухания, в единицах за секунду.
    var decay: Double

    static func tone(at start: Double, length: Double, from: Double, to: Double, gain: Double, decay: Double) -> SoundVoice {
        SoundVoice(kind: .tone, start: start, length: length, from: from, to: to, gain: gain, attack: 0.002, decay: decay)
    }

    static func rustle(
        at start: Double, length: Double, band: Double, to: Double,
        gain: Double = 1, attack: Double = 0.003, decay: Double, width: Double = 0.8, crackle: Double = 0
    ) -> SoundVoice {
        SoundVoice(
            kind: .rustle(width: width, crackle: crackle),
            start: start, length: length, from: band, to: to, gain: gain, attack: attack, decay: decay
        )
    }
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
        var mix = [Double](repeating: 0, count: Int(frames))

        var seed: UInt32 = 0x9E37_79B9
        func random() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / Double(UInt32.max)
        }

        for voice in sound.voices {
            let first = Int(voice.start * sampleRate)
            let count = min(Int(voice.length * sampleRate), mix.count - first)
            guard count > 0 else { continue }
            var phase = 0.0
            // Состояние полосового фильтра (state variable filter).
            var low = 0.0
            var band = 0.0
            for offset in 0..<count {
                let t = Double(offset) / sampleRate
                let progress = Double(offset) / Double(count)
                // Частота скользит по экспоненте: на слух это ровное движение.
                let frequency = voice.from * pow(voice.to / voice.from, progress)
                let value: Double
                switch voice.kind {
                case .tone:
                    phase += 2 * .pi * frequency / sampleRate
                    value = sin(phase) + 0.2 * sin(2 * phase)
                case .rustle(let width, let crackle):
                    var input = random() * 2 - 1
                    // Редкие щелчки внутри шума: бумага потрескивает.
                    if crackle > 0, random() < crackle * 0.004 {
                        input += random() < 0.5 ? -6 : 6
                    }
                    let f = 2 * sin(.pi * min(frequency, sampleRate / 7) / sampleRate)
                    low += f * band
                    let high = input - low - width * band
                    band += f * high
                    value = band
                }
                let attack = min(t / voice.attack, 1)
                let release = min(Double(count - offset) / (0.004 * sampleRate), 1)
                mix[first + offset] += voice.gain * attack * release * exp(-voice.decay * t) * value
            }
        }

        // Голоса разной природы громче или тише друг друга, поэтому звук приводится к своему уровню.
        let peak = mix.map(abs).max() ?? 0
        let scale = peak > 0 ? sound.level / peak : 0
        for index in mix.indices {
            samples[index] = Float(max(-1, min(1, mix[index] * scale)))
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
