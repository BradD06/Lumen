import Foundation
import Testing
@testable import LumenCore

struct InlineMarkupTests {
    private func run(_ text: String, _ marks: Set<TextMark> = [], link: String? = nil) -> TextRun {
        TextRun(text, marks: marks, link: link)
    }

    @Test func parsesEveryMark() {
        let runs = InlineMarkup.runs(from: "a **b** *c* ++d++ ~~e~~ `f` [g](https://x.io)")
        #expect(runs == [
            run("a "), run("b", [.bold]), run(" "), run("c", [.italic]), run(" "),
            run("d", [.underline]), run(" "), run("e", [.strikethrough]), run(" "),
            run("f", [.code]), run(" "), run("g", link: "https://x.io"),
        ])
    }

    @Test func plainTextStaysAsTyped() {
        for text in ["2*3", "C++", "a ~ b", "2 * 3 * 4", "[[Страница", "snake_case", "цена: 5$ (примерно)"] {
            let runs = InlineMarkup.runs(from: text)
            #expect(runs == [run(text)], "\(text)")
            #expect(InlineMarkup.source(runs) == text)
        }
    }

    @Test func unfinishedMarkersAreLiteral() {
        #expect(InlineMarkup.runs(from: "**жирн") == [run("**жирн")])
        #expect(InlineMarkup.runs(from: "****") == [run("****")])
        #expect(InlineMarkup.runs(from: "** нет**") == [run("** нет**")])
    }

    @Test func boldItalicNests() {
        #expect(InlineMarkup.runs(from: "***x***") == [run("x", [.bold, .italic])])
        #expect(InlineMarkup.runs(from: "**a *b* c**") == [run("a ", [.bold]), run("b", [.bold, .italic]), run(" c", [.bold])])
        #expect(InlineMarkup.runs(from: "[**ссылка**](lumen://page/1)") == [run("ссылка", [.bold], link: "lumen://page/1")])
    }

    @Test func escapesKeepMarkersLiteral() {
        #expect(InlineMarkup.runs(from: #"\*не курсив\*"#) == [run("*не курсив*")])
    }

    @Test(arguments: [
        [TextRun("просто текст")],
        [TextRun("a "), TextRun("b", marks: [.bold]), TextRun(" c")],
        [TextRun("a", marks: [.bold]), TextRun("b", marks: [.bold, .italic])],
        [TextRun("b", marks: [.bold, .italic]), TextRun("a", marks: [.bold])],
        [TextRun("x", marks: [.underline, .strikethrough]), TextRun(" y", marks: [.code])],
        [TextRun("ссылка", link: "https://example.com"), TextRun(" и "), TextRun("код", marks: [.code])],
        [TextRun("2*3*4 ", marks: []), TextRun("жирный", marks: [.bold])],
        [TextRun("C++ ", marks: []), TextRun("и", marks: [.italic])],
    ])
    func roundTrips(_ runs: [TextRun]) {
        let source = InlineMarkup.source(runs)
        #expect(InlineMarkup.runs(from: source) == InlineMarkup.normalized(runs), "\(source)")
    }

    @Test func edgeSpacesMoveOutOfMarks() {
        let source = InlineMarkup.source([run("a "), run("b ", [.bold]), run("c")])
        #expect(InlineMarkup.runs(from: source) == [run("a "), run("b", [.bold]), run(" c")])
    }

    @Test func togglesMarkOnSelection() {
        let runs = [run("один два три")]
        let bold = InlineMarkup.toggling(.bold, in: runs, range: 5..<9)
        #expect(bold == [run("один "), run("два", [.bold]), run(" три")])
        #expect(InlineMarkup.hasMark(.bold, in: bold, range: 5..<8))
        let back = InlineMarkup.toggling(.bold, in: bold, range: 5..<8)
        #expect(back == runs)
    }

    @Test func togglingMixedSelectionAddsMarkEverywhere() {
        let runs = [run("ab"), run("cd", [.italic])]
        #expect(InlineMarkup.toggling(.italic, in: runs, range: 0..<4) == [run("abcd", [.italic])])
    }

    @Test func linksAndClearing() {
        let runs = InlineMarkup.settingLink("https://x.io", in: [run("смотри тут")], range: 7..<10)
        #expect(runs == [run("смотри "), run("тут", link: "https://x.io")])
        #expect(InlineMarkup.link(in: runs, range: 7..<10) == "https://x.io")
        #expect(InlineMarkup.settingLink(nil, in: runs, range: 0..<10) == [run("смотри тут")])
        let styled = [run("a", [.bold]), run("b", [.italic], link: "u")]
        #expect(InlineMarkup.clearingFormatting(in: styled, range: 0..<2) == [run("ab")])
    }

    @Test func mapsSelectionBetweenSourceAndText() {
        let parsed = InlineMarkup.parse("a **bc** d")
        #expect(parsed.plainText == "a bc d")
        // «bc» в разметке стоит с 4 по 6 символ.
        #expect(parsed.plainOffset(forSource: 4) == 2)
        #expect(parsed.plainOffset(forSource: 6) == 4)
        #expect(parsed.sourceRange(forPlain: 2..<4) == 4..<6)
        #expect(parsed.sourceRange(forPlain: 6..<6) == 10..<10)
    }
}
