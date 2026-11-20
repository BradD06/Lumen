import Foundation
import LumenCore
import LumenReader
import LumenStorage
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Чтение книги вслух. Одно на всё приложение: книга звучит дальше, даже когда ушли с её экрана.
/// Держит модель читалки (с её веб-видом): из него берётся текст главы, в нём подсвечивается
/// звучащая фраза, через него открывается следующая глава. Открыли эту книгу снова — голос
/// переходит в новый экран читалки (`adopt`).
@MainActor
@Observable
final class ReadAloud {
    static let shared = ReadAloud()

    /// Таймер сна: выключить через время или в конце главы.
    enum SleepTimer: Equatable, Hashable {
        case off
        case minutes(Int)
        case chapterEnd

        static let choices: [SleepTimer] = [.off, .minutes(15), .minutes(30), .minutes(60), .chapterEnd]

        var title: String {
            switch self {
            case .off: "Выкл"
            case .minutes(let value): value >= 60 ? "\(value / 60) ч" : "\(value) мин"
            case .chapterEnd: "Конец главы"
            }
        }
    }

    static let rateKey = "readAloud.rate"
    static let voiceKey = "readAloud.voice"
    static let followKey = "readAloud.follow"
    static let highlightKey = "readAloud.highlight"

    /// Какая книга звучит; `nil`, когда плеера нет.
    private(set) var sourceId: UUID?
    /// Книга целиком: обложка для плеера и экрана блокировки.
    private(set) var source: Source?
    private(set) var attachments: AttachmentStore?
    private(set) var bookTitle = ""
    private(set) var chapterTitle = ""
    private(set) var parts: [SpeechPart] = []
    private(set) var index = 0
    private(set) var isPaused = false
    /// Текст главы ещё готовится (открывается следующая глава, PDF переходит в «Текст»).
    private(set) var isPreparing = false
    private(set) var sleepTimer: SleepTimer = .off
    private(set) var sleepDeadline: Date?
    /// Голос выбранного языка книги.
    private(set) var language: String?

    /// Остров в читалке показывает разделы, а не плеер: нажали «Разделы».
    var showsRooms = false

    var isActive: Bool { sourceId != nil }
    var isPlaying: Bool { isActive && !isPaused }

    var rate: Double = ReadAloud.storedRate {
        didSet {
            UserDefaults.standard.set(rate, forKey: Self.rateKey)
            player.rate = rate
            updateNowPlaying()
        }
    }

    var voiceId: String? = UserDefaults.standard.string(forKey: ReadAloud.voiceKey) {
        didSet {
            UserDefaults.standard.set(voiceId, forKey: Self.voiceKey)
            player.voiceId = voiceId
        }
    }

    /// Звучащая часть.
    var current: SpeechPart? { parts.indices.contains(index) ? parts[index] : nil }

    /// Сколько секунд глава уже звучит и сколько ей осталось, примерно.
    var elapsed: Double { SpeechText.estimatedSeconds(of: parts.prefix(index), rate: rate) }
    var remaining: Double { SpeechText.estimatedSeconds(of: parts.dropFirst(index), rate: rate) }
    var chapterFraction: Double { parts.isEmpty ? 0 : Double(index) / Double(parts.count) }

    @ObservationIgnored private var reader: ReaderModel?
    @ObservationIgnored private let player = SpeechVoicePlayer()
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var remoteCommandsInstalled = false
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    /// Голос ждёт, пока PDF перейдёт в «Текст», и начнёт с места на экране, а не с начала главы.
    @ObservationIgnored private var startsAtPlace = false
    /// Глава, текст которой звучит. Если читатель сам ушёл в другую, подсветка и место не трогаются.
    @ObservationIgnored private var chapterSection: Int?

    private static var storedRate: Double {
        let value = UserDefaults.standard.double(forKey: rateKey)
        return value == 0 ? 1 : min(max(value, SpeechVoicePlayer.rates.lowerBound), SpeechVoicePlayer.rates.upperBound)
    }

    private init() {
        player.rate = rate
        player.voiceId = voiceId
        player.onPart = { [weak self] number in self?.didStart(number) }
        player.onFinish = { [weak self] in self?.chapterFinished() }
    }

    // MARK: Управление

    /// Начать читать открытую книгу с места на экране (или с выделенного текста).
    func start(_ reader: ReaderModel) async {
        if sourceId != nil, sourceId != reader.sourceId { stop() }
        guard reader.canReadAloud else { return }
        self.reader = reader
        sourceId = reader.sourceId
        source = reader.source
        attachments = reader.database.attachments
        bookTitle = reader.source?.displayTitle ?? ""
        isPaused = false
        showsRooms = false
        artwork = nil
        installRemoteCommands()
        listenChapters(of: reader)
        if !reader.isTextReady {
            // PDF в оригинале: сначала переходим в «Текст», глава сама сообщит о готовности,
            // и голос начнёт с того же места.
            isPreparing = true
            startsAtPlace = true
            reader.switchToTextForSpeech()
            return
        }
        let offset = await reader.speechStartOffset()
        await loadChapter(from: offset)
        reader.clearSelection()
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func pause() {
        guard isActive, !isPaused else { return }
        isPaused = true
        player.pause()
        updateNowPlaying()
    }

    func resume() {
        guard isActive, isPaused else { return }
        isPaused = false
        if player.isPlaying {
            player.resume()
        } else if !parts.isEmpty {
            player.play(parts, from: index)
        }
        updateNowPlaying()
    }

    /// Фраза назад.
    func previous() {
        guard isActive, !parts.isEmpty else { return }
        jump(to: max(index - 1, 0))
    }

    func next() {
        guard isActive, !parts.isEmpty else { return }
        if index + 1 < parts.count {
            jump(to: index + 1)
        } else {
            chapterFinished()
        }
    }

    func stop() {
        player.stop()
        reader?.web.clearSpoken()
        reader?.onChapterReady = nil
        reader = nil
        sourceId = nil
        source = nil
        artwork = nil
        showsRooms = false
        parts = []
        index = 0
        isPaused = false
        isPreparing = false
        setSleepTimer(.off)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    func setSleepTimer(_ timer: SleepTimer) {
        sleepTimer = timer
        sleepTask?.cancel()
        sleepTask = nil
        sleepDeadline = nil
        guard case .minutes(let minutes) = timer else { return }
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepDeadline = deadline
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TimeInterval(minutes * 60)))
            guard !Task.isCancelled, let self else { return }
            self.pause()
            self.sleepTimer = .off
            self.sleepDeadline = nil
        }
    }

    /// Звучащую фразу в заметки выпиской со ссылкой на место.
    func excerptCurrent() async {
        guard let reader, let part = current, part.spoken != SpeechText.codeNotice else { return }
        await reader.excerptSpoken(part)
    }

    /// Эту книгу открыли снова: подсветка и следующие главы идут через новый экран.
    func adopt(_ reader: ReaderModel) {
        guard reader.sourceId == sourceId, reader !== self.reader else { return }
        self.reader?.onChapterReady = nil
        self.reader = reader
        listenChapters(of: reader)
    }

    /// Глава в читалке загрузилась: голос берёт её текст (следующая глава или PDF перешёл
    /// в «Текст»), а если голос уже читает её, подсветка встаёт на звучащую фразу.
    private func listenChapters(of reader: ReaderModel) {
        reader.onChapterReady = { [weak self, weak reader] in
            guard let self, let reader, self.reader === reader else { return }
            if self.isPreparing {
                let atPlace = self.startsAtPlace
                self.startsAtPlace = false
                Task {
                    let offset = atPlace ? await reader.speechStartOffset() : 0
                    await self.loadChapter(from: offset)
                }
            } else if let part = self.current {
                self.mark(part, follow: true)
            }
        }
    }

    // MARK: Внутри

    /// Перейти к фразе этой главы (из полного плеера на iPhone).
    func jump(to number: Int) {
        guard parts.indices.contains(number) else { return }
        index = number
        if isPaused {
            mark(parts[number], follow: true)
        }
        player.jump(to: number)
        if !player.isPlaying, !isPaused { player.play(parts, from: number) }
    }

    /// Берёт текст открытой главы и читает с места `offset`.
    private func loadChapter(from offset: Int) async {
        guard let reader else { return }
        isPreparing = true
        let blocks = await reader.web.speechBlocks()
        guard self.reader === reader else { return }
        isPreparing = false
        chapterSection = reader.section
        parts = SpeechText.parts(from: blocks)
        language = SpeechText.language(of: parts)
        player.language = language
        chapterTitle = reader.currentChapterTitle
        guard !parts.isEmpty else {
            // Пустая глава (обложка, картинка): сразу следующая.
            chapterFinished()
            return
        }
        index = SpeechText.index(of: offset, in: parts) ?? 0
        if isPaused {
            mark(parts[index], follow: true)
        } else {
            player.play(parts, from: index)
        }
        updateNowPlaying()
    }

    private func didStart(_ number: Int) {
        guard parts.indices.contains(number) else { return }
        index = number
        let part = parts[number]
        mark(part, follow: UserDefaults.standard.object(forKey: Self.followKey) as? Bool ?? true)
        if let reader, reader.section == chapterSection { reader.listened(to: part) }
        updateNowPlaying()
    }

    private func mark(_ part: SpeechPart, follow: Bool) {
        guard let reader, reader.section == chapterSection else { return }
        if UserDefaults.standard.object(forKey: Self.highlightKey) as? Bool ?? true {
            reader.web.markSpoken(start: part.start, end: part.end, follow: follow)
        } else if follow {
            reader.web.scroll(toOffset: part.start)
        }
    }

    private func chapterFinished() {
        guard let reader else { return }
        reader.web.clearSpoken()
        if sleepTimer == .chapterEnd {
            setSleepTimer(.off)
            isPaused = true
            player.stop()
            updateNowPlaying()
            return
        }
        isPreparing = true
        if !reader.openNextSectionForSpeech() {
            // Книга кончилась.
            stop()
        }
    }

    // MARK: Экран блокировки, наушники, часы

    private func installRemoteCommands() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard isActive else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle.isEmpty ? bookTitle : chapterTitle,
            MPMediaItemPropertyAlbumTitle: bookTitle,
            MPMediaItemPropertyArtist: "Lumen",
            MPMediaItemPropertyPlaybackDuration: elapsed + remaining,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
        if let artwork = coverArtwork() { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = isPaused ? .paused : .playing
        #endif
    }

    /// Обложка для экрана блокировки и центра управления: читается с диска один раз.
    private func coverArtwork() -> MPMediaItemArtwork? {
        if let artwork { return artwork }
        guard let name = source?.shownCover, let url = attachments?.url(for: name),
              let image = PlatformImage(contentsOfFile: url.path) else { return nil }
        nonisolated(unsafe) let picture = image
        let made = MPMediaItemArtwork(boundsSize: image.size) { _ in picture }
        artwork = made
        return made
    }
}
