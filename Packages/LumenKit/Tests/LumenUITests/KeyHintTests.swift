import CoreGraphics
@testable import LumenUI
import Testing

struct KeyHintLabelTests {
    @Test func labelsStartOnTheHomeRowAndNeverPrefixEachOther() {
        #expect(KeyHintCenter.labels(count: 3) == ["a", "s", "d"])
        let many = KeyHintCenter.labels(count: 40)
        #expect(many.count == 40)
        #expect(Set(many).count == 40)
        #expect(many.allSatisfy { $0.count == 2 })
        #expect(KeyHintCenter.labels(count: 0).isEmpty)
    }

    @Test func russianLayoutTypesTheSameKeys() {
        #expect(KeyHintCenter.latin("ф") == "a")
        #expect(KeyHintCenter.latin("Ы") == "s")
        #expect(KeyHintCenter.latin("j") == "j")
        #expect(KeyHintCenter.latin("1") == nil)
    }

    @Test func readingOrderGoesByRowsThenLeftToRight() {
        let top = CGRect(x: 300, y: 10, width: 20, height: 20)
        let sameRow = CGRect(x: 20, y: 14, width: 20, height: 20)
        let below = CGRect(x: 0, y: 90, width: 20, height: 20)
        #expect(KeyHintCenter.readingOrder(sameRow, top))
        #expect(KeyHintCenter.readingOrder(top, below))
    }
}

@MainActor
struct KeyHintCenterTests {
    @Test func typingALabelPressesItAndShiftOpensItsMenu() {
        let center = KeyHintCenter()
        var pressed: [String] = []
        center.register(UUID(), frame: CGRect(x: 0, y: 0, width: 50, height: 20), title: "Первое", layer: 0, clip: .null,
                        action: { pressed.append("first") }, secondary: { pressed.append("menu") })
        center.register(UUID(), frame: CGRect(x: 100, y: 0, width: 50, height: 20), title: "Второе", layer: 0, clip: .null,
                        action: { pressed.append("second") }, secondary: nil)
        center.activate()
        #expect(center.isActive)
        #expect(center.labeled.map(\.title) == ["Первое", "Второе"])

        center.type("ы")
        #expect(pressed == ["second"])
        #expect(!center.isActive)

        center.activate()
        center.type("A", shifted: true)
        #expect(pressed == ["second", "menu"])
    }

    @Test func onlyTheTopLayerAndVisiblePlacesGetLetters() {
        let center = KeyHintCenter()
        center.bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        center.register(UUID(), frame: CGRect(x: 10, y: 10, width: 40, height: 20), title: "Под витриной", layer: 0, clip: .null, action: {}, secondary: nil)
        center.register(UUID(), frame: CGRect(x: 10, y: 50, width: 40, height: 20), title: "Витрина", layer: 1, clip: .null, action: {}, secondary: nil)
        center.register(UUID(), frame: CGRect(x: 10, y: 900, width: 40, height: 20), title: "За краем", layer: 1, clip: .null, action: {}, secondary: nil)
        center.register(UUID(), frame: CGRect(x: 10, y: 120, width: 40, height: 20), title: "Прокручено", layer: 1,
                        clip: CGRect(x: 0, y: 0, width: 400, height: 100), action: {}, secondary: nil)
        center.activate()
        #expect(center.labeled.map(\.title) == ["Витрина"])
        center.deactivate()
        #expect(!center.isActive)
    }
}
