import Foundation
import Testing
@testable import LumenCore

struct PageVersionPolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func newVersionEveryTenMinutes() {
        #expect(PageVersionPolicy.isDue(last: nil, now: now))
        #expect(!PageVersionPolicy.isDue(last: now.addingTimeInterval(-9 * 60), now: now))
        #expect(PageVersionPolicy.isDue(last: now.addingTimeInterval(-10 * 60), now: now))
    }

    @Test func olderVersionsAreThinnedOut() {
        let hour: TimeInterval = 3_600
        let dates = [
            now.addingTimeInterval(-10 * 60),            // 0: свежая, остаётся
            now.addingTimeInterval(-20 * 60),            // 1: свежая, остаётся
            now.addingTimeInterval(-30 * hour),          // 2: вторые сутки, уходит: в этом часу есть версия позже
            now.addingTimeInterval(-30 * hour + 600),    // 3: тот же час, что 2, но позже: остаётся она
            now.addingTimeInterval(-10 * 24 * hour),     // 4: старше недели, свой день
            now.addingTimeInterval(-10 * 24 * hour - 60),// 5: тот же день, уходит
            now.addingTimeInterval(-100 * 24 * hour),    // 6: старше 90 дней, уходит
        ]
        let removed = PageVersionPolicy.toDelete(dates, now: now)
        #expect(!removed.contains(0))
        #expect(!removed.contains(1))
        #expect(!removed.contains(4))
        #expect(removed.contains(6))
        // Из двух версий одного часа (дня) остаётся более поздняя.
        #expect(removed.contains(2))
        #expect(!removed.contains(3))
        #expect(removed.contains(5))
    }

    @Test func countIsCapped() {
        let dates = (0..<150).map { now.addingTimeInterval(-Double($0) * 60) }
        let removed = PageVersionPolicy.toDelete(dates, now: now)
        #expect(dates.count - removed.count == PageVersionPolicy.maxCount)
        #expect(!removed.contains(0), "Самая свежая остаётся")
    }

    @Test func comparisonIgnoresEditTimes() {
        let pageId = UUID()
        let block = Block(pageId: pageId, content: BlockContent(text: "а"), sortKey: "a", createdAt: now)
        var later = block
        later.updatedAt = now.addingTimeInterval(500)
        #expect(PageVersionPolicy.normalized([block]) == PageVersionPolicy.normalized([later]))
        later.text = "б"
        #expect(PageVersionPolicy.normalized([block]) != PageVersionPolicy.normalized([later]))
    }
}
