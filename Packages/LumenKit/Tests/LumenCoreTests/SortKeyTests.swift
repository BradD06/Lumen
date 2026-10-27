import Testing
@testable import LumenCore

struct SortKeyTests {
    @Test func firstKeyIsInTheMiddle() {
        #expect(SortKey.between(nil, nil) == "V")
    }

    @Test func appendAndPrependKeepOrder() {
        var appended: [String] = []
        for _ in 0..<200 {
            appended.append(SortKey.between(appended.last, nil))
        }
        #expect(appended == appended.sorted())

        var prepended: [String] = []
        for _ in 0..<200 {
            prepended.insert(SortKey.between(nil, prepended.first), at: 0)
        }
        #expect(prepended == prepended.sorted())
    }

    @Test func randomInsertionsStayOrderedAndUnique() {
        var generator = SplitMix64(seed: 42)
        var keys: [String] = []
        for _ in 0..<1_000 {
            let index = Int.random(in: 0...keys.count, using: &generator)
            let lower = index > 0 ? keys[index - 1] : nil
            let upper = index < keys.count ? keys[index] : nil
            let key = SortKey.between(lower, upper)
            if let lower { #expect(lower < key) }
            if let upper { #expect(key < upper) }
            #expect(!key.hasSuffix("0"))
            keys.insert(key, at: index)
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
    }

    @Test func brokenOrderDoesNotCrash() {
        let key = SortKey.between("b", "a")
        #expect(key > "b")
    }

    @Test func sequenceIsAscending() {
        let keys = SortKey.sequence(count: 5, after: "A", before: "B")
        #expect(keys.count == 5)
        #expect(keys == keys.sorted())
        #expect(keys.allSatisfy { $0 > "A" && $0 < "B" })
    }
}

/// Детерминированный генератор, чтобы тест всегда проверял одну и ту же последовательность.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
