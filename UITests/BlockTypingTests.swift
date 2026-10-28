import XCTest

/// Набор текста блоками: Return создаёт новый блок и сразу переводит в него курсор.
final class BlockTypingTests: XCTestCase {
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

    /// Печатаем подряд без кликов мышью: каждая строка должна попасть в свой блок.
    func testReturnMovesCursorToNewBlock() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(row("").waitForExistence(timeout: 10), "Не открылась новая заметка")
        app.typeText("Test")
        app.typeKey(.return, modifierFlags: [])
        let lines = ["One", "Two", "Three", "Four"]
        for (index, line) in lines.enumerated() {
            if index > 0 {
                app.typeKey(.return, modifierFlags: [])
            }
            app.typeText(line)
        }
        for line in lines {
            XCTAssertTrue(row(line).waitForExistence(timeout: 5), "Нет отдельного блока «\(line)»")
        }
    }
}
