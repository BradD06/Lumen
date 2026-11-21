import AVFoundation
import Foundation

/// Читает части главы голосом ElevenLabs: каждая фраза приходит mp3-файлом (или из кеша)
/// и играет через `AVAudioPlayer`. Пока звучит фраза, следующие две скачиваются по очереди
/// (бесплатный тариф не любит много запросов сразу), поэтому между фразами нет пауз.
/// Не получилось (нет сети, ключ, кончились знаки) — `onFailure`, и читалка переходит на голос Apple.
@MainActor
public final class NeuralVoicePlayer: NSObject, SpeechPlaying {
    public var onPart: ((Int) -> Void)?
    public var onFinish: (() -> Void)?
    public var onFailure: ((NeuralVoiceError) -> Void)?

    public private(set) var parts: [SpeechPart] = []
    public private(set) var index = 0
    public private(set) var isPlaying = false
    public private(set) var isPaused = false

    /// Скорость меняется сразу, без новой загрузки: тот же звук играет быстрее, тон не меняется.
    public var rate: Double = 1 {
        didSet { audio?.rate = Float(Self.playbackRate(rate)) }
    }
    public var language: String?
    public var voiceId: String? {
        didSet { if voiceId != oldValue { restart() } }
    }
    public var model: NeuralVoiceModel = .multilingual {
        didSet { if model != oldValue { restart() } }
    }
    /// Ключ берётся при каждой загрузке: его могли сменить в настройках.
    public var apiKey: () -> String? = { nil }

    /// `AVAudioPlayer` ускоряет без смены тона только до 2×.
    public static let rates: ClosedRange<Double> = 0.5...2
    private static let lookahead = 2

    private var audio: AVAudioPlayer?
    private var audioIndex: Int?
    private var loads: [Int: Task<Data, any Error>] = [:]
    /// Растёт при каждом переходе: опоздавшая загрузка старой фразы ничего не включит.
    private var generation = 0
    private var startTask: Task<Void, Never>?
    private let delegate = Delegate()

    public override init() {
        super.init()
        delegate.player = self
    }

    nonisolated static func playbackRate(_ rate: Double) -> Double {
        min(max(rate, rates.lowerBound), rates.upperBound)
    }

    public func play(_ parts: [SpeechPart], from index: Int) {
        // Та же глава: уже скачанные фразы пригодятся.
        halt(keepLoads: parts == self.parts)
        self.parts = parts
        guard parts.indices.contains(index) else {
            isPlaying = false
            isPaused = false
            onFinish?()
            return
        }
        isPlaying = true
        isPaused = false
        SpeechAudio.activate()
        start(index)
    }

    public func pause() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        audio?.pause()
    }

    public func resume() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        if let audio {
            audio.play()
        } else {
            start(index)
        }
    }

    public func stop() {
        halt(keepLoads: false)
        isPlaying = false
        isPaused = false
    }

    public func jump(to number: Int) {
        guard isPlaying, parts.indices.contains(number) else { return }
        halt(keepLoads: true)
        if isPaused {
            index = number
            onPart?(number)
        } else {
            start(number)
        }
    }

    /// Сменили голос или модель: скачанное не годится, текущая фраза звучит заново.
    private func restart() {
        guard isPlaying else { return }
        halt(keepLoads: false)
        if !isPaused { start(index) }
    }

    private func halt(keepLoads: Bool) {
        generation += 1
        startTask?.cancel()
        startTask = nil
        audio?.stop()
        audio = nil
        audioIndex = nil
        if !keepLoads {
            loads.values.forEach { $0.cancel() }
            loads = [:]
        }
    }

    /// Скачать (или взять из кеша) фразу `number` и сыграть её.
    private func start(_ number: Int, delay: Double = 0) {
        generation += 1
        let current = generation
        index = number
        audio?.stop()
        audio = nil
        audioIndex = nil
        startTask?.cancel()
        startTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, self.generation == current else { return }
            do {
                let data = try await self.load(number)
                guard self.generation == current, self.isPlaying else { return }
                let player = try AVAudioPlayer(data: data)
                player.enableRate = true
                player.rate = Float(Self.playbackRate(self.rate))
                player.delegate = self.delegate
                player.prepareToPlay()
                self.audio = player
                self.audioIndex = number
                if !self.isPaused { player.play() }
                self.onPart?(number)
                self.prefetch(after: number, generation: current)
            } catch {
                guard self.generation == current, !(error is CancellationError) else { return }
                self.fail(.wrap(error))
            }
        }
    }

    private func load(_ number: Int) async throws -> Data {
        if let task = loads[number] { return try await task.value }
        guard let key = apiKey(), !key.isEmpty else { throw NeuralVoiceError.noKey }
        guard let voiceId else { throw NeuralVoiceError.noVoice }
        let speech = NeuralSpeechRequest(
            text: parts[number].spoken,
            voiceId: voiceId,
            model: model,
            language: language,
            previous: number > 0 ? parts[number - 1].spoken : nil,
            next: number + 1 < parts.count ? parts[number + 1].spoken : nil
        )
        let task = Task { try await NeuralVoiceCache.audio(for: speech, key: key) }
        loads[number] = task
        do {
            return try await task.value
        } catch {
            if loads[number] == task { loads[number] = nil }
            throw error
        }
    }

    /// Следующие фразы скачиваются по одной, пока звучит эта; дальние загрузки отменяются.
    private func prefetch(after number: Int, generation current: Int) {
        for key in Array(loads.keys) where key < number || key > number + Self.lookahead {
            loads[key]?.cancel()
            loads[key] = nil
        }
        Task { [weak self] in
            for next in (number + 1)...(number + Self.lookahead) {
                guard let self, self.generation == current, next < self.parts.count else { return }
                _ = try? await self.load(next)
            }
        }
    }

    private func fail(_ error: NeuralVoiceError) {
        halt(keepLoads: false)
        isPlaying = false
        isPaused = false
        onFailure?(error)
    }

    fileprivate func finished(_ id: ObjectIdentifier) {
        guard let audio, ObjectIdentifier(audio) == id, let number = audioIndex else { return }
        self.audio = nil
        audioIndex = nil
        if number + 1 >= parts.count {
            isPlaying = false
            isPaused = false
            onFinish?()
            NeuralVoiceCache.trim()
            return
        }
        // После заголовка пауза побольше, между фразами чуть-чуть, как у чтеца.
        start(number + 1, delay: parts[number].isHeading ? 0.45 : 0.06)
    }

    /// Делегат отдельно: его методы приходят не на главном потоке.
    private final class Delegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
        @MainActor weak var player: NeuralVoicePlayer?

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            let id = ObjectIdentifier(player)
            Task { @MainActor in self.player?.finished(id) }
        }

        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
            let id = ObjectIdentifier(player)
            Task { @MainActor in self.player?.finished(id) }
        }
    }
}

/// «Послушать» в настройках: одна фраза выбранным голосом.
@MainActor
public final class NeuralVoiceSample {
    public static let text = "Это голос для ваших книг в Lumen. Так будет звучать каждая глава."

    private var player: AVAudioPlayer?

    public init() {}

    public func play(voiceId: String, model: NeuralVoiceModel, key: String) async throws {
        let speech = NeuralSpeechRequest(text: Self.text, voiceId: voiceId, model: model, language: "ru")
        let data = try await NeuralVoiceCache.audio(for: speech, key: key)
        player?.stop()
        SpeechAudio.activate()
        player = try AVAudioPlayer(data: data)
        player?.play()
    }

    public func stop() {
        player?.stop()
        player = nil
    }
}
