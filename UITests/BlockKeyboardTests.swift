import XCTest

/// Клавиши в редакторе так, как их нажимает пользователь.
final class BlockKeyboardTests: XCTestCase {
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

    /// Тексты всех блоков: в сообщении об ошибке видно, что получилось на самом деле.
    private var rows: String {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'row-'"))
            .allElementsBoundByIndex
            .map { $0.identifier.debugDescription }
            .joined(separator: ", ")
    }

    func testBackspaceDeletesEmptyBlock() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(row("").waitForExistence(timeout: 10), "Не открылась новая заметка")
        app.typeText("Test")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(row("").waitForExistence(timeout: 5))
        row("").click()
        app.typeText("First")
        XCTAssertTrue(row("First").waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])

        let empty = row("")
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "Return создал пустой блок")
        empty.click()
        app.typeKey(.delete, modifierFlags: [])

        XCTAssertTrue(empty.waitForNonExistence(timeout: 5), "Backspace удалил пустой блок")
        app.typeText("X")
        XCTAssertTrue(row("FirstX").waitForExistence(timeout: 5), "Курсор встал в конец блока выше. Блоки: \(rows)")
    }

    func testReturnInCodeBlockAddsLineThenLeaves() {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(row("").waitForExistence(timeout: 10), "Не открылась новая заметка")
        app.typeText("Test")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(row("").waitForExistence(timeout: 5))
        row("").click()
        app.typeText("```")
        app.typeText("a")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("b")
        XCTAssertTrue(row("a\nb").waitForExistence(timeout: 5), "Return перенёс строку внутри блока кода. Блоки: \(rows)")

        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        app.typeText("after")
        XCTAssertTrue(row("after").waitForExistence(timeout: 5), "Второй Return создал новый блок. Блоки: \(rows)")
        XCTAssertTrue(row("a\nb").exists, "Пустая строка в конце кода убрана. Блоки: \(rows)")
    }
}
