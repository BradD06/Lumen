import Foundation
import Testing
@testable import LumenCore

struct LumenLinkTests {
    let source = UUID()

    @Test func roundTrips() {
        let links: [LumenLink] = [
            .page(UUID()),
            .source(source),
            .highlight(sourceId: source, highlightId: UUID()),
            .place(sourceId: source, locator: SourceLocator(section: 3, progression: 0.4237, textOffset: 1200)),
            .place(sourceId: source, locator: SourceLocator(section: 0, point: LocatorPoint(x: 12.5, y: 640))),
        ]
        for link in links {
            #expect(LumenLink(url: link.url) == link, "\(link.url)")
        }
    }

    @Test func placeLinkKeepsThePlace() throws {
        let url = LumenLink.place(sourceId: source, locator: SourceLocator(section: 7, progression: 0.5, textOffset: 99)).url
        #expect(url.absoluteString == "lumen://source/\(source.uuidString)/place?s=7&p=0.5&o=99")

        let reference = try #require(ExcerptReference(url: url))
        #expect(reference.isPlace)
        #expect(reference.locator?.section == 7)
        #expect(reference.locator?.textOffset == 99)
    }

    @Test func excerptPointsToHighlightOrPlace() {
        let highlight = UUID()
        #expect(ExcerptReference(sourceId: source, highlightId: highlight, label: "").link == .highlight(sourceId: source, highlightId: highlight))
        let locator = SourceLocator(section: 2)
        #expect(ExcerptReference(sourceId: source, locator: locator, label: "").link == .place(sourceId: source, locator: locator))
    }

    @Test func caseOfSchemeAndIdDoesNotMatter() throws {
        let url = try #require(URL(string: "LUMEN://Source/\(source.uuidString.lowercased())"))
        #expect(LumenLink(url: url) == .source(source))
    }

    /// Место без страницы или с мусором вместо чисел: книга откроется там, где остановились.
    @Test func brokenPlaceOpensTheBook() throws {
        for query in ["", "?s=abc", "?p=0.3"] {
            let url = try #require(URL(string: "lumen://source/\(source.uuidString)/place\(query)"))
            #expect(LumenLink(url: url) == .source(source))
        }
        let huge = try #require(URL(string: "lumen://source/\(source.uuidString)/place?s=1e300&p=7&o=-5"))
        guard case .place(_, let locator) = LumenLink(url: huge) else {
            Issue.record("Должна быть ссылка на место")
            return
        }
        #expect(locator.progression == 1)
        #expect(locator.textOffset == 0)
    }

    @Test(arguments: [
        "https://example.com/source/x",
        "lumen://source/not-a-uuid",
        "lumen://unknown/1F1F1F1F-1F1F-1F1F-1F1F-1F1F1F1F1F1F",
        "lumen://source/1F1F1F1F-1F1F-1F1F-1F1F-1F1F1F1F1F1F/highlight",
        "lumen://page",
    ])
    func rejectsForeignLinks(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(LumenLink(url: url) == nil)
    }
}
