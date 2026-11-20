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

    /// Пока вкладка одна, кружков у острова нет: они появляются со второй вкладкой и прячутся снова.
    func testNewTabOpensAndCloses() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "Окно не открылось")
        XCTAssertFalse(element("tab-1").exists, "Кружок вкладки виден при одной вкладке")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(element("tab-2").waitForExistence(timeout: 5), "⌘T не открыл вкладку")
        XCTAssertTrue(element("tab-1").exists, "Нет первой вкладки")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("tab-2").waitForNonExistence(timeout: 5), "⌘W не закрыл вкладку")
        XCTAssertTrue(app.windows.firstMatch.exists, "Закрылось окно вместо вкладки")
    }

    /// Щелчок по кружку вкладки у острова открывает эту вкладку.
    func testTabCircleSwitchesTab() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(element("row-").waitForExistence(timeout: 10), "Не открылась новая заметка")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(element("tab-2").waitForExistence(timeout: 5), "⌘T не открыл вкладку")
        XCTAssertTrue(element("row-").waitForNonExistence(timeout: 5), "Новая вкладка не пустая")
        element("tab-1").click()
        XCTAssertTrue(element("row-").waitForExistence(timeout: 5), "Кружок не вернул вкладку с заметкой")
    }
}
