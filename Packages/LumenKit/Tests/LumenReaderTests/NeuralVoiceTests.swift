import Foundation
import Testing
@testable import LumenReader

struct NeuralVoiceTests {
    @Test func voicesAreParsedWithBookVoicesFirst() throws {
        let json = """
        {"voices": [
          {"voice_id": "a1", "name": "Adam", "labels": {"gender": "male", "accent": "american", "use_case": "social media"}},
          {"voice_id": "b2", "name": "Bella", "labels": {"gender": "female", "age": "young", "use_case": "narration"}},
          {"name": "Без id"}
        ]}
        """
        let voices = try ElevenLabsClient.parseVoices(Data(json.utf8))
        #expect(voices.map(\.id) == ["b2", "a1"])
        #expect(voices[0].isNarration)
        #expect(voices[0].details == "женский · молодой · для книг")
        #expect(voices[1].details == "мужской · american")
    }

    @Test func libraryVoicesAreMarkedOnTheFreePlan() throws {
        let json = """
        {"voices": [
          {"voice_id": "lib", "name": "Из библиотеки", "category": "professional", "labels": {"use_case": "narration"}},
          {"voice_id": "std", "name": "Стандартный", "category": "premade", "labels": {}}
        ]}
        """
        let voices = try ElevenLabsClient.parseVoices(Data(json.utf8))
        #expect(voices.map(\.id) == ["lib", "std"])
        #expect(!voices[0].isPremade && voices[1].isPremade)

        let free = NeuralVoiceInfo.marking(voices, tier: "free")
        #expect(free.map(\.id) == ["std", "lib"])
        #expect(free[1].needsPaidPlan)
        #expect(free[1].shownDetails == "для книг · нужен платный тариф")
        #expect(!free[0].needsPaidPlan)

        // На платном тарифе и когда тариф неизвестен ничего не помечается.
        #expect(NeuralVoiceInfo.marking(voices, tier: "creator").allSatisfy { !$0.needsPaidPlan })
        #expect(NeuralVoiceInfo.marking(voices, tier: nil).map(\.id) == ["lib", "std"])
    }

    @Test func accountShowsRemainingCharacters() throws {
        let json = #"{"tier": "free", "character_count": 1200, "character_limit": 10000}"#
        let account = try ElevenLabsClient.parseAccount(Data(json.utf8))
        #expect(account.remaining == 8800)
        #expect(account.tier == "free")
    }

    @Test func errorsBecomeClearReasons() {
        func error(_ status: Int, _ body: String) -> NeuralVoiceError {
            ElevenLabsClient.parseError(status: status, data: Data(body.utf8))
        }
        #expect(error(401, #"{"detail": {"status": "invalid_api_key", "message": "Invalid API key"}}"#) == .badKey)
        #expect(error(401, #"{"detail": {"status": "missing_permissions", "message": "..."}}"#) == .missingPermission)
        #expect(error(401, #"{"detail": {"status": "quota_exceeded", "message": "..."}}"#) == .quotaExceeded)
        #expect(error(429, #"{"detail": {"status": "too_many_concurrent_requests"}}"#) == .busy)
        #expect(error(429, "") == .busy)
        #expect(error(402, #"{"detail": {"status": "payment_required", "message": "Free users cannot use library voices via the API."}}"#) == .paidPlanRequired)
        #expect(error(402, "") == .paidPlanRequired)
        #expect(error(500, #"{"detail": "Внутренняя ошибка"}"#) == .server(500, "Внутренняя ошибка"))
    }

    @Test func speechRequestCarriesKeyTextAndNeighbours() throws {
        let client = ElevenLabsClient(apiKey: "sk_test")
        let speech = NeuralSpeechRequest(text: "Вторая фраза.", voiceId: "voice1", model: .flash, language: "ru", previous: "Первая.", next: "Третья.")
        let request = client.speechRequest(speech)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "sk_test")
        #expect(request.url?.path() == "/v1/text-to-speech/voice1")
        #expect(request.url?.query()?.contains("output_format=mp3_44100_128") == true)
        let body = try #require(json(request))
        #expect(body["text"] as? String == "Вторая фраза.")
        #expect(body["model_id"] as? String == "eleven_flash_v2_5")
        #expect(body["previous_text"] as? String == "Первая.")
        #expect(body["next_text"] as? String == "Третья.")
        #expect(body["language_code"] as? String == "ru")
        let settings = try #require(body["voice_settings"] as? [String: Any])
        #expect(settings["stability"] as? Double == NeuralVoiceTuning.standard.stability)
        #expect(settings["style"] as? Double == 0)

        // Multilingual сам узнаёт язык: код языка ему не отправляем.
        var multilingual = speech
        multilingual.model = .multilingual
        let other = try #require(json(client.speechRequest(multilingual)))
        #expect(other["language_code"] == nil)
        #expect(other["previous_text"] as? String == "Первая.")
    }

    @Test func v3GetsLanguageNoNeighboursAndAStabilityStep() throws {
        let client = ElevenLabsClient(apiKey: "sk_test")
        let speech = NeuralSpeechRequest(
            text: "Фраза.", voiceId: "v", model: .v3, tuning: NeuralVoiceTuning(stability: 0.65, style: 0.8),
            language: "ru-RU", previous: "До.", next: "После."
        )
        let body = try #require(json(client.speechRequest(speech)))
        #expect(body["model_id"] as? String == "eleven_v3")
        #expect(body["previous_text"] == nil)
        #expect(body["next_text"] == nil)
        #expect(body["language_code"] as? String == "ru")
        let settings = try #require(body["voice_settings"] as? [String: Any])
        #expect(settings["stability"] as? Double == 0.5)
        #expect(settings.count == 1)
    }

    @Test func tuningStaysInRangeAndChangesTheCache() {
        #expect(NeuralVoiceTuning(stability: 1.4, style: -1) == NeuralVoiceTuning(stability: 1, style: 0))
        let calm = NeuralSpeechRequest(text: "Фраза.", voiceId: "v", model: .multilingual, tuning: NeuralVoiceTuning(stability: 0.9, style: 0))
        var lively = calm
        lively.tuning = NeuralVoiceTuning(stability: 0.3, style: 0.4)
        #expect(calm.cacheKey != lively.cacheKey)
    }

    private func json(_ request: URLRequest) -> [String: Any]? {
        request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    @Test func cacheKeyDependsOnVoiceModelTuningAndTextOnly() {
        let base = NeuralSpeechRequest(text: "Фраза.", voiceId: "v", model: .multilingual, previous: "До.")
        var neighbours = base
        neighbours.previous = "Другое."
        neighbours.next = "После."
        var voice = base
        voice.voiceId = "w"
        var model = base
        model.model = .flash
        #expect(base.cacheKey == neighbours.cacheKey)
        #expect(base.cacheKey != voice.cacheKey)
        #expect(base.cacheKey != model.cacheKey)
        #expect(base.cacheKey.count == 64)
    }

    @Test func neuralSpeedStaysWithinTwiceFaster() {
        #expect(NeuralVoicePlayer.playbackRate(3) == 2)
        #expect(NeuralVoicePlayer.playbackRate(0.25) == 0.5)
        #expect(NeuralVoicePlayer.playbackRate(1.25) == 1.25)
    }

    /// Знаки ElevenLabs списывает, как только начал озвучивать: одна фраза просится один раз,
    /// и отмена ждущего (пауза, переход) не обрывает загрузку.
    @Test func samePhraseIsFetchedOnceAndCancellingTheWaiterKeepsTheFetch() async throws {
        actor Counter {
            var calls = 0
            func hit() { calls += 1 }
        }
        let counter = Counter()
        let fetches = NeuralVoiceFetches()
        let make: @Sendable () async throws -> Data = {
            await counter.hit()
            try await Task.sleep(for: .milliseconds(200))
            return Data("mp3".utf8)
        }
        let first = Task { try await fetches.data(for: "k", make: make) }
        try await Task.sleep(for: .milliseconds(20))
        first.cancel()
        let second = try await fetches.data(for: "k", make: make)
        #expect(second == Data("mp3".utf8))
        #expect(try await first.value == Data("mp3".utf8))
        #expect(await counter.calls == 1)
    }

    @Test func maskedKeyShowsOnlyTheEnd() {
        #expect(NeuralVoiceKey.masked("sk_abcdef1234") == "…1234")
    }
}
