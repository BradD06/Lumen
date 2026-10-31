import XCTest

/// Стрелки «Назад / Вперёд» и вкладки: работают с клавиатуры, как в браузере.
final class NavigationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testBackAndForwardReturnToTheNote() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(element("row-").waitForExistence(timeout: 10), "Не открылась новая заметка")

        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(element("row-").waitForNonExistence(timeout: 5), "«Назад» не ушёл с заметки")

        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(element("row-").waitForExistence(timeout: 5), "«Вперёд» не вернул заметку")
    }

    func testNewTabOpensAndCloses() {
        XCTAssertTrue(element("tab-1").waitForExistence(timeout: 10), "Нет полоски вкладок")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(element("tab-2").waitForExistence(timeout: 5), "⌘T не открыл вкладку")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("tab-2").waitForNonExistence(timeout: 5), "⌘W не закрыл вкладку")
        XCTAssertTrue(element("tab-1").exists, "Закрылось окно вместо вкладки")
    }
}
