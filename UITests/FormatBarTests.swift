import XCTest

/// Панель оформления над выделенным текстом: кнопки нажимаются мышью.
final class FormatBarTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func row(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "row-\(text)").firstMatch
    }

    private func field(_ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", value)).firstMatch
    }

    /// Панель висит над блоком выше: клик должен попасть в кнопку, а не в тот блок.
    func testBoldButtonFormatsSelection() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(row("").waitForExistence(timeout: 10), "Не открылась новая заметка")
        app.typeText("Test")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("First")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("Hello world")
        XCTAssertTrue(row("Hello world").waitForExistence(timeout: 5), "Нет блока «Hello world»")
        // Курсор после Return ещё пару кадров ставится в конец блока: ждём, пока он успокоится.
        Thread.sleep(forTimeInterval: 0.6)
        for _ in 0..<5 {
            app.typeKey(.leftArrow, modifierFlags: .shift)
        }

        let bold = app.buttons["Жирный"].firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 5), "Над выделением нет панели оформления")
        bold.click()

        XCTAssertTrue(field("Hello **world**").waitForExistence(timeout: 5), "Кнопка «Жирный» не сработала")
        XCTAssertTrue(app.buttons["Жирный"].firstMatch.exists, "Панель пропала после нажатия")
    }
}
