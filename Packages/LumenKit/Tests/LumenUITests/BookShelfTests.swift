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
