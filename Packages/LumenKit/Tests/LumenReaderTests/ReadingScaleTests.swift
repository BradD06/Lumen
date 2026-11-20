import Foundation
import Testing
@testable import LumenReader

@Suite struct ReadingScaleTests {
    @Test func progressFollowsTextNotFileNumber() {
        // Обложка, титул и две главы разной длины, как в EPUB.
        let scale = ReadingScale(weights: [10, 90, 300, 600])
        #expect(scale.progress(section: 0, progression: 0) == 0)
        // Начало первой главы: прочитаны только обложка и титул, а не половина книги.
        #expect(abs(scale.progress(section: 2, progression: 0) - 0.1) < 0.0001)
        #expect(abs(scale.progress(section: 2, progression: 0.5) - 0.25) < 0.0001)
        #expect(abs(scale.progress(section: 3, progression: 1) - 1) < 0.0001)
    }

    @Test func evenScaleMatchesOldCount() {
        let scale = ReadingScale.even(4)
        #expect(abs(scale.progress(section: 1, progression: 0.5) - 0.375) < 0.0001)
    }

    @Test func progressClampsOutOfRange() {
        let scale = ReadingScale(weights: [1, 1])
        #expect(scale.progress(section: 5, progression: 2) == 1)
        #expect(scale.progress(section: -1, progression: -1) == 0)
        #expect(ReadingScale(weights: []).progress(section: 0, progression: 0.5) == 0)
    }

    @Test func weightCountsVisibleLettersAndPictures() {
        let html = """
        <html><head><title>Не считается</title><style>p { color: red }</style></head>
        <body><h1>Глава&nbsp;1</h1><p>Привет, <b>мир</b>!</p>
        <script>var x = "не считается";</script><img src="a.jpg"/></body></html>
        """
        // «Глава» + &nbsp; + «1» + «Привет,» + «мир» + «!» = 5 + 1 + 1 + 7 + 3 + 1 букв, плюс картинка.
        #expect(ReadingScale.weight(html: html) == 18 + ReadingScale.imageWeight)
        #expect(ReadingScale.weight(html: "<body></body>") == 1)
    }

    @Test func weightsReadSectionFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "<body>abc</body>".write(to: root.appendingPathComponent("a.html"), atomically: true, encoding: .utf8)
        try "<body>abcdef</body>".write(to: root.appendingPathComponent("b.html"), atomically: true, encoding: .utf8)
        let prepared = PreparedDocument(root: root, document: ReadableDocument(sections: [
            ReadableSection(title: "A", path: "a.html"),
            ReadableSection(title: "B", path: "b.html"),
            ReadableSection(title: "Нет файла", path: "missing.html"),
        ]))
        #expect(ReadingScale.weights(of: prepared) == [3, 6, 1])
    }

    @Test func chaptersAreTopLevelOfContents() {
        let toc = [
            TocEntry(title: "Пролог", section: 2),
            TocEntry(title: "Глава 1", section: 3),
            TocEntry(title: "Часть I", section: 4, anchor: "a", level: 1),
            TocEntry(title: "Глава 2", section: 6),
        ]
        #expect(TocEntry.chapters(in: toc).map(\.title) == ["Пролог", "Глава 1", "Глава 2"])
    }

    @Test func singleTopEntryUsesLevelBelow() {
        // Всё оглавление вложено в название книги: главами считаются пункты под ним.
        let toc = [
            TocEntry(title: "Книга", section: 0),
            TocEntry(title: "Глава 1", section: 1, level: 1),
            TocEntry(title: "1.1", section: 1, anchor: "x", level: 2),
            TocEntry(title: "Глава 2", section: 2, level: 1),
        ]
        #expect(TocEntry.chapters(in: toc).map(\.title) == ["Глава 1", "Глава 2"])
        #expect(TocEntry.chapters(in: []).isEmpty)
    }

    @Test func arrowsStepThroughSubsections() {
        // Как в «Хрониках»: глава и её разделы, каждый в своём файле.
        let toc = [
            TocEntry(title: "Глава 2", section: 15),
            TocEntry(title: "Галакронд", section: 24, level: 1),
            TocEntry(title: "Глава 3", section: 34),
            TocEntry(title: "Империя Зул", section: 35, level: 1),
            TocEntry(title: "Цикл богомолов", section: 36, level: 1),
        ]
        #expect(TocEntry.neighbour(of: 2, forward: true, in: toc) == 3)
        #expect(TocEntry.neighbour(of: 3, forward: true, in: toc) == 4)
        #expect(TocEntry.neighbour(of: 4, forward: true, in: toc) == nil)
        #expect(TocEntry.neighbour(of: 3, forward: false, in: toc) == 2)
        #expect(TocEntry.neighbour(of: 0, forward: false, in: toc) == nil)
        // Ещё на обложке: вперёд к первому пункту, назад некуда.
        #expect(TocEntry.neighbour(of: nil, forward: true, in: toc) == 0)
        #expect(TocEntry.neighbour(of: nil, forward: false, in: toc) == nil)
    }

    @Test func arrowsSkipEntriesAtTheSamePlace() {
        // «Часть I» и «Глава 1» начинаются в одном месте: назад из раздела 1.1 к главе,
        // а из главы сразу к прологу, иначе стрелка открывала бы то же место.
        let toc = [
            TocEntry(title: "Пролог", section: 1),
            TocEntry(title: "Часть I", section: 2),
            TocEntry(title: "Глава 1", section: 2, level: 1),
            TocEntry(title: "1.1", section: 2, anchor: "x", level: 2),
        ]
        #expect(TocEntry.neighbour(of: 3, forward: false, in: toc) == 2)
        #expect(TocEntry.neighbour(of: 2, forward: false, in: toc) == 0)
        #expect(TocEntry.neighbour(of: 0, forward: true, in: toc) == 1)
        #expect(TocEntry.neighbour(of: 2, forward: true, in: toc) == 3)
    }
}
