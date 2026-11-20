import AVFoundation
import Foundation

/// Голос Apple из системы: имя, язык и качество для списка голосов.
public struct SpeechVoiceInfo: Hashable, Sendable, Identifiable {
    public enum Quality: Int, Comparable, Sendable {
        case standard
        case enhanced
        case premium

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .standard: "Обычный"
            case .enhanced: "Улучшенный"
            case .premium: "Премиум"
            }
        }
    }

    public var id: String
    public var name: String
    public var language: String
    public var quality: Quality

    /// Язык по-русски: «русский», «английский (США)».
    public var languageTitle: String {
        Locale(identifier: "ru").localizedString(forIdentifier: language) ?? language
    }
}

/// Голоса Apple на этом устройстве. Улучшенные и премиум скачиваются в настройках системы.
public enum SpeechVoices {
    public static func all() -> [SpeechVoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices()
            // Голоса-шутки (Bells, Bubbles…) и «личный голос» для книги не годятся.
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .map(info)
            .sorted { ($0.language, -$0.quality.rawValue, $0.name) < ($1.language, -$1.quality.rawValue, $1.name) }
    }

    /// Голоса для языка книги («ru», «en-US»), лучшие сверху.
    public static func voices(for language: String) -> [SpeechVoiceInfo] {
        let prefix = String(language.prefix(2)).lowercased()
        return all()
            .filter { $0.language.lowercased().hasPrefix(prefix) }
            .sorted { ($0.quality, $1.name) > ($1.quality, $0.name) }
    }

    /// Голос по умолчанию для языка: лучший из скачанных.
    public static func best(for language: String) -> SpeechVoiceInfo? {
        voices(for: language).first
    }

    public static func voice(id: String) -> SpeechVoiceInfo? {
        AVSpeechSynthesisVoice(identifier: id).map(info)
    }

    static func info(_ voice: AVSpeechSynthesisVoice) -> SpeechVoiceInfo {
        let quality: SpeechVoiceInfo.Quality = switch voice.quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
        return SpeechVoiceInfo(id: voice.identifier, name: voice.name, language: voice.language, quality: quality)
    }
}

/// Читает части текста голосом Apple по очереди и говорит, какая звучит.
/// Держит в очереди синтезатора пару частей вперёд, чтобы между ними не было пауз;
/// смена скорости или голоса начинает текущую часть заново.
@MainActor
public final class SpeechVoicePlayer: NSObject {
    /// Началась часть с этим номером.
    public var onPart: ((Int) -> Void)?
    /// Части кончились.
    public var onFinish: (() -> Void)?

    public private(set) var parts: [SpeechPart] = []
    public private(set) var index = 0
    public private(set) var isPlaying = false
    public private(set) var isPaused = false

    /// Скорость относительно обычной: 0.5…3.
    public var rate: Double = 1 {
        didSet { if rate != oldValue { restartCurrent() } }
    }
    public var voiceId: String? {
        didSet { if voiceId != oldValue { restartCurrent() } }
    }
    /// Язык, если голос не выбран: берётся лучший голос этого языка.
    public var language: String?

    public static let rates: ClosedRange<Double> = 0.5...3

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = Delegate()
    /// Части, уже отданные синтезатору, и их номера. Ссылки держим, пока синтезатор не отчитался:
    /// иначе адрес освободившейся реплики мог бы достаться новой и опоздавшее событие спутало бы номер.
    private var queued: [ObjectIdentifier: (utterance: AVSpeechUtterance, index: Int)] = [:]
    private var retired: [AVSpeechUtterance] = []
    /// Скорость или голос поменяли на паузе: после «Продолжить» часть начнётся заново.
    private var needsRestart = false
    private var nextToQueue = 0
    private static let lookahead = 2

    public override init() {
        super.init()
        synthesizer.delegate = delegate
        delegate.player = self
    }

    /// Читать `parts` начиная с `index`.
    public func play(_ parts: [SpeechPart], from index: Int) {
        stopSynthesizer()
        self.parts = parts
        guard parts.indices.contains(index) else {
            isPlaying = false
            onFinish?()
            return
        }
        self.index = index
        nextToQueue = index
        isPlaying = true
        isPaused = false
        activateAudio()
        fill()
    }

    public func pause() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        // На границе слова пауза звучит естественнее, но может ждать до секунды.
        if !synthesizer.pauseSpeaking(at: .word) { synthesizer.pauseSpeaking(at: .immediate) }
    }

    public func resume() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        if needsRestart || !synthesizer.continueSpeaking() {
            play(parts, from: index)
        }
    }

    public func stop() {
        stopSynthesizer()
        isPlaying = false
        isPaused = false
    }

    /// Перейти к части `index` той же главы.
    public func jump(to index: Int) {
        guard isPlaying, parts.indices.contains(index) else { return }
        if isPaused {
            self.index = index
            needsRestart = true
            onPart?(index)
        } else {
            play(parts, from: index)
        }
    }

    private func restartCurrent() {
        guard isPlaying else { return }
        if isPaused {
            needsRestart = true
        } else {
            play(parts, from: index)
        }
    }

    private func stopSynthesizer() {
        needsRestart = false
        retired = Array((retired + queued.values.map(\.utterance)).suffix(16))
        queued = [:]
        if synthesizer.isSpeaking || synthesizer.isPaused { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// Держит в очереди синтезатора текущую часть и пару следующих.
    private func fill() {
        while nextToQueue < parts.count, nextToQueue < index + Self.lookahead + 1 {
            let part = parts[nextToQueue]
            let utterance = AVSpeechUtterance(string: part.spoken)
            utterance.rate = Self.utteranceRate(rate)
            if let voice = voiceId.flatMap(AVSpeechSynthesisVoice.init(identifier:))
                ?? language.flatMap({ SpeechVoices.best(for: $0) }).flatMap({ AVSpeechSynthesisVoice(identifier: $0.id) }) {
                utterance.voice = voice
            }
            if part.isHeading { utterance.postUtteranceDelay = 0.45 }
            queued[ObjectIdentifier(utterance)] = (utterance, nextToQueue)
            synthesizer.speak(utterance)
            nextToQueue += 1
        }
    }

    /// Множитель скорости → скорость синтезатора. Обычная 0.5, в 2 раза быстрее примерно 0.75.
    static func utteranceRate(_ multiplier: Double) -> Float {
        let value = multiplier <= 1
            ? Double(AVSpeechUtteranceDefaultSpeechRate) * multiplier
            : Double(AVSpeechUtteranceDefaultSpeechRate) + (Double(AVSpeechUtteranceMaximumSpeechRate) - Double(AVSpeechUtteranceDefaultSpeechRate)) * (multiplier - 1) / 2
        return Float(min(max(value, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
    }

    private func activateAudio() {
        #if os(iOS)
        // Книга играет и в фоне, и при выключенном звонке.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    fileprivate func didStart(_ id: ObjectIdentifier) {
        guard let number = queued[id]?.index else { return }
        index = number
        onPart?(number)
    }

    fileprivate func didFinish(_ id: ObjectIdentifier) {
        guard let number = queued.removeValue(forKey: id)?.index else { return }
        if number + 1 >= parts.count {
            isPlaying = false
            isPaused = false
            onFinish?()
            return
        }
        index = max(index, number + 1)
        fill()
    }

    /// Делегат синтезатора отдельно: его методы приходят не на главном потоке.
    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        @MainActor weak var player: SpeechVoicePlayer?

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
            let id = ObjectIdentifier(utterance)
            Task { @MainActor in self.player?.didStart(id) }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            let id = ObjectIdentifier(utterance)
            Task { @MainActor in self.player?.didFinish(id) }
        }
    }
}
