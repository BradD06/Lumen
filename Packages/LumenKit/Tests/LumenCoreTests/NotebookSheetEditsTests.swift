import CoreGraphics
import Foundation
import Testing
@testable import LumenCore

struct NotebookSheetEditsTests {
    @Test func mappingMovesOneSheetAndShiftsTheOthers() {
        // Лист 0 на место 2: листы 1 и 2 поднимаются.
        #expect(NotebookSheets.sheetMapping(movingFrom: 0, to: 2, count: 4) == [2, 0, 1, 3])
        // Лист 3 на место 1: листы 1 и 2 опускаются.
        #expect(NotebookSheets.sheetMapping(movingFrom: 3, to: 1, count: 4) == [0, 2, 3, 1])
        #expect(NotebookSheets.sheetMapping(movingFrom: 1, to: 1, count: 3) == [0, 1, 2])
        #expect(NotebookSheets.sheetMapping(movingFrom: 5, to: 0, count: 3) == [0, 1, 2])
    }

    @Test func perSheetListsMoveWithTheirSheets() {
        let papers: [PaperPattern?] = [.cornell, nil, .week]
        #expect(NotebookSheets.movingSheet(papers, from: 0, to: 2, sheetCount: 3) == [nil, .week, .cornell])
        #expect(NotebookSheets.movingSheet([PaperPattern?]([.staff]), from: 0, to: 3, sheetCount: 4) == [nil, nil, nil, .staff])
        #expect(NotebookSheets.movingSheet([PaperPattern?]([.staff]), from: 3, to: 0, sheetCount: 4) == [nil, .staff])
        #expect(NotebookSheets.movingSheet([String?]?.none, from: 0, to: 1, sheetCount: 2) == nil)
        #expect(NotebookSheets.insertingSheets(["а"], after: 0, into: ["x", "y"], sheetCount: 2) == ["x", "а", "y"])
        #expect(NotebookSheets.removingSheet(0, from: ["x", nil]) == nil)
    }

    private func notebook() -> BlockContent {
        let second = NotebookLayout.sheetRect(1)
        return BlockContent(
            sheetCount: 3,
            items: [
                NotebookItem(kind: .text, frame: CGRect(x: 40, y: second.minY + 60, width: 200, height: 40), text: "Формула Эйлера"),
                NotebookItem(kind: .image, frame: CGRect(x: 40, y: 80, width: 100, height: 100), attachment: "a.png"),
            ],
            sheetTexts: ["Лекция по истории\nПётр Первый и реформы", nil, "Ёлка и история"]
        )
    }

    @Test func sheetTextJoinsHandwritingAndTextBoxes() {
        let content = notebook()
        #expect(NotebookSheets.text(of: content, sheet: 0) == "Лекция по истории\nПётр Первый и реформы")
        #expect(NotebookSheets.text(of: content, sheet: 1) == "Формула Эйлера")
        #expect(NotebookSheets.text(of: content, sheet: 2) == "Ёлка и история")
        #expect(NotebookSheets.text(of: content, sheet: 7).isEmpty)
    }

    @Test func findingWordsListsSheetsWithSnippets() {
        let content = notebook()
        let history = NotebookSheets.matches("история", in: content)
        #expect(history.map(\.sheet) == [2])
        let lecture = NotebookSheets.matches("ИСТОРИИ реформы", in: content)
        #expect(lecture.map(\.sheet) == [0])
        // Перевод строки в куске текста становится пробелом.
        #expect(lecture.first?.snippet.contains("\n") == false)
        #expect(NotebookSheets.matches("эйлер", in: content).map(\.sheet) == [1])
        #expect(NotebookSheets.matches("истори", in: content).map(\.sheet) == [0, 2])
        #expect(NotebookSheets.matches("   ", in: content).isEmpty)
        #expect(NotebookSheets.matches("квант", in: content).isEmpty)
    }

    @Test func longTextIsCutAroundTheWord() {
        let long = String(repeating: "слово ", count: 40) + "нужное " + String(repeating: "хвост ", count: 40)
        let content = BlockContent(sheetCount: 1, sheetTexts: [long])
        let snippet = NotebookSheets.matches("нужное", in: content, snippetRadius: 10).first?.snippet ?? ""
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.contains("нужное"))
        #expect(snippet.count < 40)
    }

    @Test func handwritingAndTextBoxesAreSearchable() throws {
        let content = notebook()
        #expect(content.searchText.contains("Пётр Первый"))
        #expect(content.searchText.contains("Формула Эйлера"))
        let decoded = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.sheetTexts == content.sheetTexts)
    }
}
