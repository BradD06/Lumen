import Foundation
import Testing
@testable import LumenCore

struct PaneArrangementTests {
    @Test func wideWindowsSideBySideTallWindowsStacked() {
        let arrangement = PaneArrangement()
        #expect(arrangement.axis(isTall: false) == .sideBySide)
        #expect(arrangement.axis(isTall: true) == .stacked)
        #expect(PaneArrangement.isTall(width: 834, height: 1194))
        #expect(!PaneArrangement.isTall(width: 1194, height: 834))
    }

    @Test func choiceIsRememberedPerWindowShape() {
        var arrangement = PaneArrangement()
        arrangement.setAxis(.stacked, isTall: false)
        #expect(arrangement.axis(isTall: false) == .stacked)
        // Вертикальный iPad свою раскладку не теряет.
        #expect(arrangement.axis(isTall: true) == .stacked)
        arrangement.setAxis(.sideBySide, isTall: true)
        #expect(arrangement.axis(isTall: true) == .sideBySide)
        #expect(arrangement.axis(isTall: false) == .stacked)
    }

    @Test func fractionsStayInRange() {
        var arrangement = PaneArrangement()
        arrangement.setFraction(0.99, for: .stacked)
        #expect(arrangement.stackedFraction == PaneArrangement.stackedRange.upperBound)
        arrangement.setFraction(0.01, for: .sideBySide)
        #expect(arrangement.sideFraction == PaneArrangement.sideRange.lowerBound)
        arrangement.setFraction(.nan, for: .sideBySide)
        #expect(PaneArrangement.sideRange.contains(arrangement.sideFraction))
    }

    @Test func draggingTheHandleTowardsTheNoteShrinksIt() {
        // Заметка снизу: ручку тянут вниз, заметка становится ниже.
        let lower = PaneArrangement.dragged(from: 0.5, delta: 100, length: 1000, axis: .stacked, isSwapped: false)
        #expect(abs(lower - 0.4) < 0.0001)
        // Заметка сверху (поменяли местами): тянут вниз, заметка растёт.
        let upper = PaneArrangement.dragged(from: 0.5, delta: 100, length: 1000, axis: .stacked, isSwapped: true)
        #expect(abs(upper - 0.6) < 0.0001)
        let clamped = PaneArrangement.dragged(from: 0.5, delta: -900, length: 1000, axis: .sideBySide, isSwapped: false)
        #expect(clamped == PaneArrangement.sideRange.upperBound)
    }

    @Test func oldOrPartialSavesDecodeWithDefaults() throws {
        let empty = try JSONDecoder().decode(PaneArrangement.self, from: Data("{}".utf8))
        #expect(empty == PaneArrangement())
        let partial = try JSONDecoder().decode(
            PaneArrangement.self,
            from: Data(#"{"wideAxis":"stacked","isSwapped":true,"unknown":1}"#.utf8)
        )
        #expect(partial.wideAxis == .stacked)
        #expect(partial.isSwapped)
        #expect(partial.tallAxis == .stacked)

        var arrangement = PaneArrangement()
        arrangement.swap()
        arrangement.setFraction(0.3, for: .stacked)
        let data = try JSONEncoder().encode(arrangement)
        #expect(try JSONDecoder().decode(PaneArrangement.self, from: data) == arrangement)
    }
}
