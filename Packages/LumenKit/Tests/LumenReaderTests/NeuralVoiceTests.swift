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
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body["text"] == "Вторая фраза.")
        #expect(body["model_id"] == "eleven_flash_v2_5")
        #expect(body["previous_text"] == "Первая.")
        #expect(body["next_text"] == "Третья.")
        #expect(body["language_code"] == "ru")

        // Multilingual сам узнаёт язык: код языка ему не отправляем.
        var multilingual = speech
        multilingual.model = .multilingual
        let other = try #require(client.speechRequest(multilingual).httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(other["language_code"] == nil)
    }

    @Test func cacheKeyDependsOnVoiceModelAndTextOnly() {
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

    @Test func maskedKeyShowsOnlyTheEnd() {
        #expect(NeuralVoiceKey.masked("sk_abcdef1234") == "…1234")
    }
}
