import Testing
@testable import LumenReader
@testable import LumenUI

struct ReaderLookTests {
    @Test func highlightsCountUsesRussianPlural() {
        #expect(ReaderView.highlightsCount(1) == "1 выделение")
        #expect(ReaderView.highlightsCount(3) == "3 выделения")
        #expect(ReaderView.highlightsCount(7) == "7 выделений")
        #expect(ReaderView.highlightsCount(11) == "11 выделений")
        #expect(ReaderView.highlightsCount(12) == "12 выделений")
        #expect(ReaderView.highlightsCount(21) == "21 выделение")
        #expect(ReaderView.highlightsCount(24) == "24 выделения")
    }

    @Test func dawnPageIsWarmPaper() {
        let dawn = ReaderAppearance(palette: .dawn)
        #expect(dawn.backgroundHex == 0xFBE6DA)
        #expect(dawn.css.contains("#FBE6DA"))
    }

    @Test func roundedTypefaceUsesSystemRoundedFont() {
        let rounded = ReaderAppearance(typeface: .rounded)
        #expect(rounded.css.contains("ui-rounded"))
        #expect(!ReaderAppearance().css.contains("ui-rounded"))
    }
}
