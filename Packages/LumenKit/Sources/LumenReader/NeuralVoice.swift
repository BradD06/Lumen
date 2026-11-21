import CryptoKit
import Foundation
import Security

/// Голос ElevenLabs из списка голосов аккаунта.
public struct NeuralVoiceInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Пол, акцент, для чего голос: «женский · американский · для книг».
    public var details: String
    /// Голос хорош для книг (ElevenLabs помечает его как narration / audiobook).
    public var isNarration: Bool
    /// Стандартный голос ElevenLabs (`premade`): работает на любом тарифе, и на бесплатном.
    public var isPremade: Bool
    /// Голос из библиотеки, а тариф бесплатный: через API ElevenLabs его не озвучит (ошибка 402).
    public var needsPaidPlan = false

    public init(id: String, name: String, details: String = "", isNarration: Bool = false, isPremade: Bool = true) {
        self.id = id
        self.name = name
        self.details = details
        self.isNarration = isNarration
        self.isPremade = isPremade
    }

    /// Подпись в списке: с пометкой, если голос недоступен на тарифе.
    public var shownDetails: String {
        guard needsPaidPlan else { return details }
        return details.isEmpty ? "нужен платный тариф" : details + " · нужен платный тариф"
    }

    /// На бесплатном тарифе голоса из библиотеки помечаются и уходят в конец списка.
    public static func marking(_ voices: [NeuralVoiceInfo], tier: String?) -> [NeuralVoiceInfo] {
        guard tier?.lowercased() == "free" else { return voices }
        let marked = voices.map { voice in
            var voice = voice
            voice.needsPaidPlan = !voice.isPremade
            return voice
        }
        return marked.filter { !$0.needsPaidPlan } + marked.filter(\.needsPaidPlan)
    }
}

/// Сколько знаков тарифа ElevenLabs потрачено в этом месяце.
public struct NeuralVoiceAccount: Hashable, Sendable {
    public var used: Int
    public var limit: Int
    public var tier: String

    public var remaining: Int { max(limit - used, 0) }
}

/// Модель ElevenLabs. Flash вдвое дешевле по знакам и быстрее отвечает, Multilingual звучит живее,
/// v3 самая новая: живее всех читает русский и реже путает ударения, но не видит соседних фраз.
public enum NeuralVoiceModel: String, CaseIterable, Codable, Sendable {
    case v3 = "eleven_v3"
    case multilingual = "eleven_multilingual_v2"
    case flash = "eleven_flash_v2_5"

    public var title: String {
        switch self {
        case .v3: "Новая v3: живее, точнее ударения"
        case .multilingual: "Многоязычная v2: ровное звучание"
        case .flash: "Быстрая: вдвое дешевле"
        }
    }

    /// Соседние фразы для интонации (`previous_text` / `next_text`): v3 их не принимает.
    var takesNeighbours: Bool { self != .v3 }
    /// Язык текста явно (`language_code`): Multilingual v2 его не принимает, узнаёт сам.
    var takesLanguage: Bool { self != .multilingual }
}

/// Как звучит голос ElevenLabs. Ровность: выше спокойнее и ровнее, без странных акцентов,
/// ниже живее, но голос чаще «гуляет». Выразительность: 0 как у диктора, выше ярче и театральнее.
public struct NeuralVoiceTuning: Codable, Hashable, Sendable {
    public var stability: Double
    public var style: Double

    public static let standard = NeuralVoiceTuning(stability: 0.65, style: 0)

    public init(stability: Double, style: Double) {
        self.stability = min(max(stability, 0), 1)
        self.style = min(max(style, 0), 1)
    }

    /// `voice_settings` для запроса. v3 понимает только три ступени ровности
    /// (0 «творческая», 0.5 «естественная», 1 «надёжная») и без остальных полей.
    func voiceSettings(for model: NeuralVoiceModel) -> [String: Any] {
        if model == .v3 {
            let step = stability < 0.25 ? 0.0 : stability < 0.75 ? 0.5 : 1.0
            return ["stability": step]
        }
        return [
            "stability": Self.rounded(stability),
            "similarity_boost": 0.75,
            "style": Self.rounded(style),
            "use_speaker_boost": true,
        ]
    }

    /// Для имени файла в кеше: то же, что уходит в запрос.
    func cachePart(for model: NeuralVoiceModel) -> String {
        voiceSettings(for: model).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

public enum NeuralVoiceError: Error, Equatable, LocalizedError {
    case noKey
    case noVoice
    case badKey
    case missingPermission
    case quotaExceeded
    /// 402: голос из библиотеки на бесплатном тарифе, или тариф не оплачен.
    case paidPlanRequired
    case busy
    case offline
    case keychain(Int32)
    case server(Int, String)

    public var errorDescription: String? {
        switch self {
        case .noKey: "ключ не введён."
        case .noVoice: "голос не выбран."
        case .badKey: "ключ не подходит. Проверьте, что он скопирован целиком."
        case .missingPermission: "у ключа нет нужного права. В ElevenLabs откройте ключ и включите «Text to Speech» и «Voices: Read»."
        case .quotaExceeded: "знаки тарифа на этот месяц кончились."
        case .paidPlanRequired: "этот голос недоступен на вашем тарифе ElevenLabs или закончились кредиты. На бесплатном тарифе работают только стандартные голоса ElevenLabs, не голоса из библиотеки."
        case .busy: "сервис сейчас перегружен, попробуйте чуть позже."
        case .offline: "нет интернета."
        case .keychain(let status): "не удалось сохранить ключ в Связке ключей (код \(status))."
        case .server(let code, let message): message.isEmpty ? "ошибка сервиса (\(code))." : "ошибка сервиса (\(code)): \(message)"
        }
    }

    static func wrap(_ error: any Error) -> NeuralVoiceError {
        if let error = error as? NeuralVoiceError { return error }
        if error is URLError { return .offline }
        return .server(0, error.localizedDescription)
    }
}

/// Одна часть для озвучки нейроголосом. Соседние фразы ElevenLabs берёт для интонации,
/// в кеш они не входят: та же фраза тем же голосом звучит из кеша в любом окружении.
public struct NeuralSpeechRequest: Hashable, Sendable {
    public var text: String
    public var voiceId: String
    public var model: NeuralVoiceModel
    public var tuning: NeuralVoiceTuning
    public var language: String?
    public var previous: String?
    public var next: String?

    public init(
        text: String,
        voiceId: String,
        model: NeuralVoiceModel,
        tuning: NeuralVoiceTuning = .standard,
        language: String? = nil,
        previous: String? = nil,
        next: String? = nil
    ) {
        self.text = text
        self.voiceId = voiceId
        self.model = model
        self.tuning = tuning
        self.language = language
        self.previous = previous
        self.next = next
    }

    /// Имя файла в кеше: от голоса, модели, настроек звучания и текста.
    public var cacheKey: String {
        let digest = SHA256.hash(data: Data("\(model.rawValue)|\(voiceId)|\(tuning.cachePart(for: model))|\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// ElevenLabs по ключу пользователя: проверка ключа, список голосов, звук фразы (mp3).
public struct ElevenLabsClient: Sendable {
    public static let base = URL(string: "https://api.elevenlabs.io")!
    public static let keysPage = URL(string: "https://elevenlabs.io/app/settings/api-keys")!

    public var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Знаки тарифа. `nil`, если ключу не дали права читать аккаунт: сам ключ при этом рабочий.
    public func account() async throws -> NeuralVoiceAccount? {
        do {
            let data = try await send(request(path: "/v1/user/subscription"))
            return try Self.parseAccount(data)
        } catch NeuralVoiceError.missingPermission {
            return nil
        }
    }

    public func voices() async throws -> [NeuralVoiceInfo] {
        try Self.parseVoices(await send(request(path: "/v1/voices")))
    }

    public func speech(_ speech: NeuralSpeechRequest) async throws -> Data {
        try await send(speechRequest(speech))
    }

    // MARK: Запросы

    func request(path: String) -> URLRequest {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 30
        return request
    }

    func speechRequest(_ speech: NeuralSpeechRequest) -> URLRequest {
        var request = request(path: "/v1/text-to-speech/\(speech.voiceId)")
        request.url = request.url?.appending(queryItems: [URLQueryItem(name: "output_format", value: "mp3_44100_128")])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "text": speech.text,
            "model_id": speech.model.rawValue,
            "voice_settings": speech.tuning.voiceSettings(for: speech.model),
        ]
        if speech.model.takesNeighbours {
            if let previous = speech.previous { body["previous_text"] = previous }
            if let next = speech.next { body["next_text"] = next }
        }
        if speech.model.takesLanguage, let language = speech.language?.prefix(2), language.count == 2 {
            body["language_code"] = String(language).lowercased()
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NeuralVoiceError.wrap(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.parseError(status: status, data: data) }
        return data
    }

    // MARK: Разбор ответов

    static func parseAccount(_ data: Data) throws -> NeuralVoiceAccount {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return NeuralVoiceAccount(
            used: object["character_count"] as? Int ?? 0,
            limit: object["character_limit"] as? Int ?? 0,
            tier: object["tier"] as? String ?? ""
        )
    }

    static func parseVoices(_ data: Data) throws -> [NeuralVoiceInfo] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let list = object["voices"] as? [[String: Any]] ?? []
        let voices = list.compactMap { item -> NeuralVoiceInfo? in
            guard let id = item["voice_id"] as? String, let name = item["name"] as? String else { return nil }
            let labels = item["labels"] as? [String: String] ?? [:]
            let use = (labels["use_case"] ?? labels["use case"] ?? "").lowercased()
            let isNarration = ["narration", "narrative", "audiobook", "narrative_story", "informative_educational"].contains { use.contains($0) }
            let details = [
                labels["gender"].map(gender),
                labels["accent"],
                labels["age"].map(age),
                isNarration ? "для книг" : nil,
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let category = (item["category"] as? String ?? "premade").lowercased()
            return NeuralVoiceInfo(id: id, name: name, details: details, isNarration: isNarration, isPremade: category == "premade")
        }
        // Голоса для книг сверху, дальше как в аккаунте.
        return voices.filter(\.isNarration) + voices.filter { !$0.isNarration }
    }

    static func parseError(status: Int, data: Data) -> NeuralVoiceError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let detail = object?["detail"]
        let fields = detail as? [String: Any]
        let code = ((fields?["status"] ?? fields?["code"]) as? String ?? "").lowercased()
        let message = fields?["message"] as? String ?? detail as? String ?? ""
        switch code {
        case "invalid_api_key", "api_key_invalid": return .badKey
        case "missing_permissions", "missing_permission": return .missingPermission
        case "quota_exceeded", "insufficient_credits": return .quotaExceeded
        case "payment_required", "paid_plan_required", "subscription_required", "free_users_not_allowed": return .paidPlanRequired
        case "too_many_concurrent_requests", "system_busy", "rate_limit_exceeded": return .busy
        case "voice_not_found": return .noVoice
        default: break
        }
        switch status {
        case 401: return .badKey
        case 402: return .paidPlanRequired
        case 429: return .busy
        default: return .server(status, message)
        }
    }

    private static func gender(_ value: String) -> String {
        switch value.lowercased() {
        case "male": "мужской"
        case "female": "женский"
        default: value
        }
    }

    private static func age(_ value: String) -> String {
        switch value.lowercased() {
        case "young": "молодой"
        case "middle aged", "middle_aged": "средних лет"
        case "old": "пожилой"
        default: value
        }
    }
}

/// Озвученные фразы на диске (Caches/LumenReader/voice): второй раз та же фраза знаков не тратит.
public enum NeuralVoiceCache {
    /// Сколько держать: старые файлы удаляются, когда кеш перерастает предел.
    public static let limit = 400 * 1024 * 1024

    public static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "LumenReader/voice", directoryHint: .isDirectory)
    }

    /// Звук фразы: из кеша, а нет — у ElevenLabs (с одной повторной попыткой, если сервис занят).
    public static func audio(for speech: NeuralSpeechRequest, key: String) async throws -> Data {
        let file = directory.appending(path: speech.cacheKey + ".mp3")
        if let data = try? Data(contentsOf: file), !data.isEmpty {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return data
        }
        let client = ElevenLabsClient(apiKey: key)
        let data: Data
        do {
            data = try await client.speech(speech)
        } catch NeuralVoiceError.busy {
            try await Task.sleep(for: .seconds(1.5))
            data = try await client.speech(speech)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// Убирает самые давние файлы, пока кеш не станет меньше предела.
    public static func trim(to bytes: Int = limit) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        var entries = files.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > bytes else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > bytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// Сколько места занято, байт.
    public static func size() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Ключ ElevenLabs в Связке ключей: только на этом устройстве, в iCloud и в резервные копии Lumen не попадает.
public enum NeuralVoiceKey {
    static let service = "io.github.bradd06.lumen.voice"
    static let account = "elevenlabs"

    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func load() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    public static func save(_ key: String) throws {
        delete()
        var item = base
        item[kSecValueData as String] = Data(key.utf8)
        #if os(iOS)
        // Доступен и при заблокированном экране (книга играет в фоне), но не уходит на другие устройства.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        item[kSecAttrLabel as String] = "Lumen: ключ ElevenLabs"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NeuralVoiceError.keychain(status)
        }
    }

    public static func delete() {
        SecItemDelete(base as CFDictionary)
    }

    /// Конец ключа, чтобы показать, какой сохранён: «…a1b2».
    public static func masked(_ key: String) -> String {
        "…" + key.suffix(4)
    }
}
