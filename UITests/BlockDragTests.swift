import XCTest

/// Перетаскивание блоков за ручку так, как это делает пользователь мышью.
final class BlockDragTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    /// Новая заметка с блоками по одному на строку. Текст латиницей: так ввод не зависит от раскладки.
    private func createNote(_ lines: [String]) {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(row("").waitForExistence(timeout: 10), "Не открылась новая заметка")
        app.typeText("Test")
        app.typeKey(.return, modifierFlags: [])
        for (index, line) in lines.enumerated() {
            if index > 0 {
                app.typeKey(.return, modifierFlags: [])
            }
            // Новый пустой блок появляется и получает фокус асинхронно: ждём его и щёлкаем в него,
            // чтобы текст не ушёл в предыдущий блок на медленной машине.
            let empty = row("")
            XCTAssertTrue(empty.waitForExistence(timeout: 5), "Не появился новый блок")
            empty.click()
            app.typeText(line)
            XCTAssertTrue(row(line).waitForExistence(timeout: 5), "Нет блока «\(line)»")
        }
    }

    private func row(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "row-\(text)").firstMatch
    }

    private func handle(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "handle-\(text)").firstMatch
    }

    /// Тянет блок `source` за ручку в точку `offset` (доли ширины и высоты) строки `target`.
    private func drag(_ source: String, to target: String, at offset: CGVector) {
        row(source).hover()
        Thread.sleep(forTimeInterval: 0.3)
        let from = handle(source).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = row(target).coordinate(withNormalizedOffset: offset)
        from.click(forDuration: 0.6, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.6)
    }

    func testDragToRightEdgeMakesColumns() {
        createNote(["Left", "Right"])
        XCTAssertGreaterThan(row("Right").frame.minY, row("Left").frame.maxY - 1, "Сначала блоки идут друг под другом")

        drag("Right", to: "Left", at: CGVector(dx: 0.92, dy: 0.5))

        let predicate = NSPredicate { _, _ in
            abs(self.row("Right").frame.minY - self.row("Left").frame.minY) < 8
        }
        let sideBySide = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [sideBySide], timeout: 5)
        XCTAssertGreaterThan(row("Right").frame.minX, row("Left").frame.maxX - 1, "Правый блок стоит справа")
    }

    func testColumnDividerResizesColumns() {
        createNote(["Left", "Right"])
        drag("Right", to: "Left", at: CGVector(dx: 0.92, dy: 0.5))
        let divider = app.descendants(matching: .any).matching(identifier: "column-divider").firstMatch
        XCTAssertTrue(divider.waitForExistence(timeout: 5), "Между колонками есть разделитель")

        let before = row("Left").frame.width
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 120, dy: 0)))

        let predicate = NSPredicate { _, _ in self.row("Left").frame.width > before + 60 }
        let wider = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [wider], timeout: 5)
    }

    func testDragAboveReordersBlocks() {
        createNote(["First", "Second", "Third"])

        drag("Third", to: "First", at: CGVector(dx: 0.3, dy: 0.1))

        let predicate = NSPredicate { _, _ in
            self.row("Third").frame.maxY <= self.row("First").frame.minY + 1
        }
        let moved = expectation(for: predicate, evaluatedWith: nil)
        wait(for: [moved], timeout: 5)
    }
}
