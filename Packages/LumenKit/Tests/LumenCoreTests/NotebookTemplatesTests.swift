import Foundation
import Testing
@testable import LumenCore

struct NotebookTemplatesTests {
    @Test func sheetUsesItsOwnTemplateOrTheNotebooks() {
        var content = BlockContent(sheetCount: 3, paper: .grid)
        #expect(NotebookSheets.paper(of: content, sheet: 0) == .grid)
        content.sheetPapers = NotebookSheets.settingPaper(.cornell, sheet: 1, in: content)
        #expect(content.sheetPapers == [nil, .cornell])
        #expect(NotebookSheets.paper(of: content, sheet: 1) == .cornell)
        #expect(NotebookSheets.paper(of: content, sheet: 2) == .grid)
        // Тетрадь без шаблона: в линейку.
        #expect(NotebookSheets.paper(of: BlockContent(sheetCount: 1), sheet: 0) == .lined)
    }

    @Test func templateEqualToTheNotebooksIsNotStored() {
        var content = BlockContent(sheetCount: 2, paper: .dotted)
        content.sheetPapers = NotebookSheets.settingPaper(.staff, sheet: 0, in: content)
        #expect(content.sheetPapers == [.staff])
        content.sheetPapers = NotebookSheets.settingPaper(.dotted, sheet: 0, in: content)
        #expect(content.sheetPapers == nil)
        // Листа нет: ничего не меняется.
        #expect(NotebookSheets.settingPaper(.week, sheet: 5, in: content) == nil)
    }

    @Test func sheetTemplatesMoveWithTheirSheets() {
        let list: [PaperPattern?] = [nil, .cornell, .week]
        // Новый лист после первого: шаблоны ниже уезжают на один.
        #expect(NotebookSheets.insertingPapers([.staff], after: 0, into: list, sheetCount: 3) == [nil, .staff, .cornell, .week])
        // В конец, в короткий список.
        #expect(NotebookSheets.insertingPapers([.grid], after: nil, into: [.cornell], sheetCount: 3) == [.cornell, nil, nil, .grid])
        #expect(NotebookSheets.insertingPapers([nil], after: nil, into: nil, sheetCount: 2) == nil)
        #expect(NotebookSheets.removingPaper(1, from: list) == [nil, .week])
        #expect(NotebookSheets.removingPaper(2, from: list) == [nil, .cornell])
        #expect(NotebookSheets.removingPaper(1, from: [nil, .week]) == nil)
    }

    @Test func sheetTemplatesRoundTripAndUnknownOnesAreIgnored() throws {
        let content = BlockContent(sheetCount: 3, paper: .lined, sheetPapers: [nil, .smallGrid, .cornell])
        let decoded = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.sheetPapers == [nil, .smallGrid, .cornell])

        let json = Data(#"{"runs":[],"sheetCount":2,"sheetPapers":["hexagons","week"]}"#.utf8)
        let newer = try JSONDecoder().decode(BlockContent.self, from: json)
        #expect(newer.sheetPapers == [nil, .week])
        #expect(NotebookSheets.paper(of: newer, sheet: 0) == .lined)
    }

    @Test func everyTemplateHasANameAndAnIcon() {
        #expect(PaperPattern.allCases.count == 8)
        #expect(Set(PaperPattern.allCases.map(\.title)).count == PaperPattern.allCases.count)
        for pattern in PaperPattern.allCases {
            #expect(!pattern.symbolName.isEmpty)
        }
        // 5 мм на листе A4.
        #expect(NotebookLayout.smallGridSpacing == 18)
    }
}
