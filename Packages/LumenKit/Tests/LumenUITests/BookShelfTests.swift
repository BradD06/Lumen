import Foundation
import LumenCore
@testable import LumenUI
import Testing

struct BookShelfTests {
    private func book(id: UUID = UUID(), title: String = "Мастер и Маргарита", progress: Double = 0, opened: Bool = false) -> Source {
        var source = Source(title: title, format: .epub, file: "b.epub", originalName: "b.epub")
        source.id = id
        source.progress = progress
        source.lastOpenedAt = opened ? Date() : nil
        return source
    }

    @Test func spineLooksTheSameEveryTime() {
        let id = UUID()
        let first = BookSpineStyle(source: book(id: id))
        let second = BookSpineStyle(source: book(id: id))
        #expect(first == second)
        #expect((128...168).contains(first.height))
        #expect((0..<5).contains(first.colorIndex))
        #expect(first.width >= 30)
    }

    @Test func ribbonHangsDownToTheReadPlace() {
        #expect(BookSpineStyle.ribbon(progress: 0.5, opened: false, height: 150) == nil, "неоткрытая книга без ленты")
        #expect(BookSpineStyle.ribbon(progress: 0, opened: true, height: 150) == 14, "начатая показывает кончик")
        #expect(BookSpineStyle.ribbon(progress: 0.5, opened: true, height: 150) == 75)
        #expect(BookSpineStyle.ribbon(progress: 1.4, opened: true, height: 150) == 150)
    }

    @Test func summarySaysHowMuchIsRead() {
        #expect(BookSpineStyle.summary(book(progress: 0.42, opened: true)) == "Мастер и Маргарита, прочитано 42%")
        #expect(BookSpineStyle.summary(book()) == "Мастер и Маргарита, ещё не открывали")
    }
}

struct BookStatsTextTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 11, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func lastReadSaysTodayYesterdayOrTheDate() {
        let now = date(8, 12, 0)
        #expect(BookStatsText.lastRead(nil, now: now, calendar: calendar) == "ещё не открывали")
        #expect(BookStatsText.lastRead(date(8, 9, 5), now: now, calendar: calendar) == "сегодня, 09:05")
        #expect(BookStatsText.lastRead(date(7, 22, 10), now: now, calendar: calendar) == "вчера, 22:10")
        #expect(BookStatsText.lastRead(date(5, 18, 0), now: now, calendar: calendar) == "5 ноября")
        #expect(BookStatsText.lastRead(date(5, 18, 0, year: 2025), now: now, calendar: calendar).hasPrefix("5 ноября 2025"))
    }

    @Test func excerptCountsAgreeWithTheNumber() {
        #expect(BookStatsText.excerpts(1) == "1 выписка")
        #expect(BookStatsText.excerpts(3) == "3 выписки")
        #expect(BookStatsText.excerpts(5) == "5 выписок")
        #expect(BookStatsText.excerpts(12) == "12 выписок")
        #expect(BookStatsText.excerpts(21) == "21 выписка")
    }

    @Test func pulledBookTurnsToACoverOfBookProportions() {
        let style = BookSpineStyle(source: Source(title: "Книга", format: .epub, file: "a.epub", originalName: "a.epub"))
        #expect(style.coverWidth == (style.height * 0.68).rounded())
        #expect(style.coverWidth > style.width)
    }
}

struct BookShowcaseLayoutTests {
    @Test func wideWindowPutsCoverAndStatsSideBySide() {
        let layout = BookShowcaseLayout(size: CGSize(width: 1400, height: 900))
        #expect(layout.isSideBySide)
        #expect(layout.coverHeight == 520, "обложка крупная, но не выше 520")
        #expect(layout.coverWidth == (520 * 0.68).rounded())
    }

    @Test func narrowWindowStacksThemAndShrinksTheCover() {
        let layout = BookShowcaseLayout(size: CGSize(width: 420, height: 800))
        #expect(!layout.isSideBySide)
        #expect(layout.coverHeight <= 300)
    }
}
