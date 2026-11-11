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
        #expect(first.width >= 30)
    }

    @Test func ribbonHangsDownToTheReadPlace() {
        #expect(BookSpineStyle.ribbon(progress: 0.5, opened: false, height: 150) == nil, "неоткрытая книга без ленты")
        #expect(BookSpineStyle.ribbon(progress: 0, opened: true, height: 150) == 14, "начатая показывает кончик")
        #expect(BookSpineStyle.ribbon(progress: 0.5, opened: true, height: 150) == 75)
        #expect(BookSpineStyle.ribbon(progress: 1.4, opened: true, height: 150) == 150)
    }

    @Test func spineShowsTheChosenStripOfTheCover() {
        #expect(BookSpineStyle.stripOffset(center: nil, coverWidth: 100, spineWidth: 30) == 0, "по умолчанию середина")
        #expect(BookSpineStyle.stripOffset(center: 0.5, coverWidth: 100, spineWidth: 30) == 0)
        #expect(BookSpineStyle.stripOffset(center: 0.3, coverWidth: 100, spineWidth: 30) == 20)
        // У края полоска упирается в край обложки, пустоты на корешке нет.
        #expect(BookSpineStyle.stripOffset(center: 0, coverWidth: 100, spineWidth: 30) == 35)
        #expect(BookSpineStyle.stripOffset(center: 1, coverWidth: 100, spineWidth: 30) == -35)
        #expect(SpineStripPicker.fraction(150, width: 300) == 0.5)
        #expect(SpineStripPicker.fraction(-20, width: 300) == 0)
        #expect(SpineStripPicker.fraction(400, width: 300) == 1)
    }

    @Test func ownCoverPhotoIsShownInsteadOfTheBookCover() {
        var source = book()
        #expect(source.shownCover == nil)
        source.cover = "book.jpg"
        #expect(source.shownCover == "book.jpg")
        source.customCover = "mine.jpg"
        #expect(source.shownCover == "mine.jpg")
        #expect(source.attachmentNames == ["b.epub", "book.jpg", "mine.jpg"])
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

struct ShelfLayoutTests {
    @Test func dropPlaceFollowsThePointer() {
        // Две книги по 30 точек: середины на 25 и 58.
        let widths: [CGFloat] = [30, 30]
        #expect(ShelfLayout.insertionIndex(x: 5, widths: widths) == 0)
        #expect(ShelfLayout.insertionIndex(x: 30, widths: widths) == 1)
        #expect(ShelfLayout.insertionIndex(x: 70, widths: widths) == 2)
        #expect(ShelfLayout.insertionIndex(x: 10, widths: []) == 0)
    }
}

struct ShelfReorderTests {
    private let a = UUID(), b = UUID(), c = UUID()

    @Test func wideBookDoesNotJumpBackAndForthOverANarrowOne() {
        // a широкая (60), b и c узкие (20). a держат над b: она встаёт на место b,
        // и та же точка уже над ней самой, поэтому порядок дальше не меняется.
        let widths: [UUID: CGFloat] = [a: 60, b: 20, c: 20]
        let first = ShelfLayout.reorder([a, b, c], moving: a, x: 80, widths: widths)
        #expect(first == [b, a, c])
        #expect(ShelfLayout.reorder(first, moving: a, x: 80, widths: widths) == first)
    }

    @Test func narrowBookWaitsUntilItReallyPassesAWideOne() {
        // b узкая (20) держат над началом широкой c (60): рано, порядок тот же.
        let widths: [UUID: CGFloat] = [a: 20, b: 20, c: 60]
        let order = [a, b, c]
        #expect(ShelfLayout.reorder(order, moving: b, x: 60, widths: widths) == order)
        // Над правым краем c: b встаёт после неё.
        #expect(ShelfLayout.reorder(order, moving: b, x: 100, widths: widths) == [a, c, b])
    }

    @Test func bookFromAnotherShelfLandsWhereItIsHeld() {
        let widths: [UUID: CGFloat] = [a: 30, b: 30, c: 30]
        #expect(ShelfLayout.reorder([a, b], moving: c, x: 30, widths: widths) == [a, c, b])
        #expect(ShelfLayout.reorder([], moving: c, x: 5, widths: widths) == [c])
    }
}
