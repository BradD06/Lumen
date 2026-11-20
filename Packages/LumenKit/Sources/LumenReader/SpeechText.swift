import Foundation
import NaturalLanguage

/// Кусок главы, как его собирает скрипт читалки: абзац, заголовок или код.
/// `start` считается так же, как место чтения (`SourceLocator.textOffset`): в символах UTF-16
/// от начала текста главы, поэтому часть потом можно подсветить и запомнить как место.
/// Пропущенное внутри куска (сноски, номера страниц) заменено пробелами той же длины.
public struct SpeechBlock: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case heading
        case code
    }

    public var kind: Kind
    public var text: String
    public var start: Int

    public init(kind: Kind = .text, text: String, start: Int) {
        self.kind = kind
        self.text = text
        self.start = start
    }
}

/// Часть текста, которую голос говорит целиком и которая подсвечена, пока звучит: предложение.
public struct SpeechPart: Hashable, Sendable {
    /// Что сказать: без переносов, лишних пробелов и номеров сносок.
    public var spoken: String
    /// Где часть в главе и сколько символов главы подсветить.
    public var start: Int
    public var length: Int
    public var isHeading: Bool

    public var end: Int { start + length }

    public init(spoken: String, start: Int, length: Int, isHeading: Bool = false) {
        self.spoken = spoken
        self.start = start
        self.length = length
        self.isHeading = isHeading
    }
}

/// Текст главы для чтения вслух: куски → части (предложения) со своими местами в главе.
/// Очень длинное предложение режется по запятым. `groupLength` склеивает соседние предложения
/// абзаца в одну часть, пока она короче этого числа знаков (0 — каждое предложение отдельно).
/// Код не читается (на слух бессмысленно), вместо него короткое «пример кода пропущен».
/// Голые номера страниц и строки из одних знаков пропускаются.
public enum SpeechText {
    public static let codeNotice = "Пример кода пропущен."
    /// Длиннее предложение режется по запятым: подсветка не стоит на месте полминуты.
    public static let maxPartLength = 320

    public static func parts(from blocks: [SpeechBlock], groupLength: Int = 0) -> [SpeechPart] {
        var result: [SpeechPart] = []
        for block in blocks {
            switch block.kind {
            case .code:
                let length = block.text.utf16.count
                guard length > 0, hasWords(block.text) else { continue }
                // Несколько блоков кода подряд говорим один раз.
                if let last = result.last, last.spoken == codeNotice, block.start - last.end < 4 {
                    result[result.count - 1].length = block.start + length - last.start
                    continue
                }
                result.append(SpeechPart(spoken: codeNotice, start: block.start, length: length))
            case .heading:
                guard !isNoise(block.text),
                      let range = trimmed(block.text, in: block.text.startIndex..<block.text.endIndex) else { continue }
                result.append(part(block, range, isHeading: true))
            case .text:
                guard !isNoise(block.text) else { continue }
                let pieces = sentences(in: block.text).flatMap { cut(block.text, $0) }
                for range in group(block.text, pieces, upTo: groupLength) {
                    guard let range = trimmed(block.text, in: range) else { continue }
                    let made = part(block, range, isHeading: false)
                    if hasWords(made.spoken) { result.append(made) }
                }
            }
        }
        return result
    }

    /// Часть, на которой стоит место `offset`: первая, что кончается после него.
    public static func index(of offset: Int, in parts: [SpeechPart]) -> Int? {
        guard !parts.isEmpty else { return nil }
        var low = 0
        var high = parts.count
        while low < high {
            let middle = (low + high) / 2
            if parts[middle].end <= offset { low = middle + 1 } else { high = middle }
        }
        return low < parts.count ? low : nil
    }

    /// Язык главы, чтобы выбрать голос: «ru», «en»…
    public static func language(of parts: [SpeechPart]) -> String? {
        var sample = ""
        for part in parts where !part.isHeading && part.spoken != codeNotice {
            sample += part.spoken + " "
            if sample.count > 2_000 { break }
        }
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Примерно сколько секунд займут части при обычной скорости: ~15 символов в секунду.
    public static func estimatedSeconds(of parts: some Collection<SpeechPart>, rate: Double = 1) -> Double {
        let characters = parts.reduce(0) { $0 + $1.spoken.count }
        return Double(characters) / (15 * max(rate, 0.1))
    }

    // MARK: Разбор

    static func sentences(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        return ranges.isEmpty ? [text.startIndex..<text.endIndex] : ranges
    }

    /// Предложение длиннее предела режется по знакам препинания, а если их нет, по пробелу.
    static func cut(_ text: String, _ range: Range<String.Index>) -> [Range<String.Index>] {
        var pieces: [Range<String.Index>] = []
        var start = range.lowerBound
        while text.distance(from: start, to: range.upperBound) > maxPartLength {
            let limit = text.index(start, offsetBy: maxPartLength)
            let window = text[start..<limit]
            let cut = window.lastIndex { ",;:—–".contains($0) }.map { text.index(after: $0) }
                ?? window.lastIndex(where: \.isWhitespace)
                ?? limit
            guard cut > start else { break }
            pieces.append(start..<cut)
            start = cut
        }
        pieces.append(start..<range.upperBound)
        return pieces
    }

    /// Склеивает соседние куски, пока часть короче `length` знаков.
    static func group(_ text: String, _ pieces: [Range<String.Index>], upTo length: Int) -> [Range<String.Index>] {
        guard length > 0, var current = pieces.first else { return pieces }
        var result: [Range<String.Index>] = []
        for piece in pieces.dropFirst() {
            if text.distance(from: current.lowerBound, to: piece.upperBound) <= length {
                current = current.lowerBound..<piece.upperBound
            } else {
                result.append(current)
                current = piece
            }
        }
        result.append(current)
        return result
    }

    /// Диапазон без пробелов по краям; `nil`, если в нём одни пробелы.
    static func trimmed(_ text: String, in range: Range<String.Index>) -> Range<String.Index>? {
        guard let first = text[range].firstIndex(where: { !$0.isWhitespace }),
              let last = text[range].lastIndex(where: { !$0.isWhitespace }) else { return nil }
        return first..<text.index(after: last)
    }

    private static func part(_ block: SpeechBlock, _ range: Range<String.Index>, isHeading: Bool) -> SpeechPart {
        let text = block.text
        let start = block.start + text.utf16.distance(from: text.startIndex, to: range.lowerBound)
        let length = text.utf16.distance(from: range.lowerBound, to: range.upperBound)
        return SpeechPart(spoken: clean(String(text[range])), start: start, length: length, isHeading: isHeading)
    }

    /// Мягкие переносы, сноски вида [12] и лишние пробелы голосу не нужны.
    static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\u{00AD}", with: "")
        value = value.replacingOccurrences(of: #"\[\d{1,3}\]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Номер страницы, «* * *» и прочее, что вслух не читают.
    static func isNoise(_ text: String) -> Bool {
        let value = clean(text)
        if value.isEmpty { return true }
        if value.range(of: #"^[\d\s.\-–—]+$"#, options: .regularExpression) != nil { return true }
        return !hasWords(value)
    }

    static func hasWords(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
