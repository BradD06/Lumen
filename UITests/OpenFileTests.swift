import XCTest

/// Файл, открытый в Lumen снаружи (как «Открыть с помощью» в Finder), ложится в библиотеку
/// и сразу открывается в читалке в том же окне.
final class OpenFileTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR title CONTAINS %@ OR value CONTAINS %@", text, text, text))
            .firstMatch
    }

    func testOpenedFileShowsInReader() throws {
        let name = "LumenOpenTest"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).txt")
        try Data("\(name)\nHello from Finder".utf8).write(to: url)
        XCTAssertEqual(app.windows.count, 1)

        app.open(url)

        XCTAssertTrue(element(containing: name).waitForExistence(timeout: 20), "Книга не открылась")
        XCTAssertEqual(app.windows.count, 1, "Файл должен открыться в том же окне, а не в новом")
    }

    /// Ссылка на книгу, которой нет, показывает понятную ошибку.
    func testLinkToMissingBookShowsMessage() {
        app.open(URL(string: "lumen://source/1F1F1F1F-1F1F-1F1F-1F1F-1F1F1F1F1F1F")!)

        XCTAssertTrue(element(containing: "Не получилось открыть").waitForExistence(timeout: 10), "Нет сообщения об ошибке")
    }
}
