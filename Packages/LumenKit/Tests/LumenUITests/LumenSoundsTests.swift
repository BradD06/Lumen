import Testing
@testable import LumenUI

struct LumenSoundsTests {
    @Test(arguments: LumenSound.allCases)
    func everySoundRendersItsFullLength(_ sound: LumenSound) throws {
        let buffer = try #require(LumenSounds.render(sound))
        let expected = Int((sound.duration * LumenSounds.sampleRate).rounded())
        #expect(Int(buffer.frameLength) == expected)
        #expect((0.03...0.3).contains(sound.duration), "Звуки интерфейса короткие")

        let samples = try #require(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).map { abs(samples[$0]) }.max() ?? 0
        #expect(peak > 0.01, "Звук не тишина")
        #expect(peak <= 1, "Без перегруза")
    }
}
