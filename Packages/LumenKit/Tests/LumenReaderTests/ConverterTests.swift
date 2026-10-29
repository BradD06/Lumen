import Foundation
import Testing
import ZIPFoundation
import LumenCore
@testable import LumenReader

struct ConverterTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumenReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Архив с файлами, как EPUB или DOCX.
    private func zip(_ name: String, _ files: [String: String]) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let archive = try Archive(url: url, accessMode: .create)
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    private func prepare(_ file: URL, _ format: SourceFormat) throws -> PreparedDocument {
        let prepared = try DocumentConverter.prepareSync(file: file, format: format, cacheKey: UUID().uuidString)
        return prepared
    }

    private func html(_ prepared: PreparedDocument, section: Int = 0) throws -> String {
        try String(contentsOf: try #require(prepared.url(for: section)), encoding: .utf8)
    }

    @Test func epubKeepsSpineOrderTitlesAndCover() throws {
        let file = try zip("book.epub", [
            "mimetype": "application/epub+zip",
            "META-INF/container.xml": """
                <?xml version="1.0"?>
                <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
                  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
                </container>
                """,
            "OEBPS/content.opf": """
                <?xml version="1.0"?>
                <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
                  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <dc:title>Евгений Онегин</dc:title><dc:creator>Александр Пушкин</dc:creator>
                  </metadata>
                  <manifest>
                    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    <item id="c2" href="text/chapter%202.xhtml" media-type="application/xhtml+xml"/>
                    <item id="c1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
                    <item id="cover" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
                  </manifest>
                  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
                </package>
                """,
            "OEBPS/nav.xhtml": """
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
                <nav epub:type="toc"><ol>
                  <li><a href="text/chapter1.xhtml">Глава первая</a></li>
                  <li><a href="text/chapter%202.xhtml#start">Глава вторая</a></li>
                </ol></nav></body></html>
                """,
            "OEBPS/text/chapter1.xhtml": "<html><body><p>Мой дядя самых честных правил</p></body></html>",
            "OEBPS/text/chapter 2.xhtml": "<html><body><p>Деревня, где скучал Евгений</p></body></html>",
            "OEBPS/images/cover.jpg": "jpg",
        ])
        let prepared = try prepare(file, .epub)
        #expect(prepared.document.title == "Евгений Онегин")
        #expect(prepared.document.author == "Александр Пушкин")
        #expect(prepared.document.sections.map(\.title) == ["Глава первая", "Глава вторая"])
        #expect(prepared.document.sections.map(\.path) == ["OEBPS/text/chapter1.xhtml", "OEBPS/text/chapter 2.xhtml"])
        #expect(prepared.document.coverPath == "OEBPS/images/cover.jpg")
        #expect(try html(prepared, section: 1).contains("Деревня"))
    }

    @Test func fb2SplitsSectionsAndDecodesImages() throws {
        let image = Data("png".utf8).base64EncodedString()
        let file = folder.appendingPathComponent("book.fb2")
        try """
            <?xml version="1.0" encoding="utf-8"?>
            <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
              <description><title-info>
                <author><first-name>Лев</first-name><last-name>Толстой</last-name></author>
                <book-title>Война и мир</book-title>
                <coverpage><image l:href="#cover.png"/></coverpage>
              </title-info></description>
              <body>
                <section><title><p>Часть первая</p></title><p>Ну, князь, <emphasis>Генуя</emphasis> и Лукка</p></section>
                <section><title><p>Часть вторая</p></title><p>В октябре</p></section>
              </body>
              <body name="notes"><section><p>Примечание</p></section></body>
              <binary id="cover.png" content-type="image/png">\(image)</binary>
            </FictionBook>
            """.write(to: file, atomically: true, encoding: .utf8)

        let prepared = try prepare(file, .fb2)
        #expect(prepared.document.title == "Война и мир")
        #expect(prepared.document.author == "Лев Толстой")
        #expect(prepared.document.sections.map(\.title) == ["Часть первая", "Часть вторая", "Примечания"])
        #expect(try html(prepared).contains("<em>Генуя</em>"))
        let cover = try #require(prepared.coverURL)
        #expect(try Data(contentsOf: cover) == Data("png".utf8))
    }

    @Test func docxKeepsHeadingsListsAndFormatting() throws {
        let w = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
        let file = try zip("doc.docx", [
            "word/document.xml": """
                <w:document \(w)><w:body>
                  <w:p><w:pPr><w:pStyle w:val="1"/></w:pPr><w:r><w:t>Введение</w:t></w:r></w:p>
                  <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Жирный</w:t></w:r><w:r><w:t xml:space="preserve"> и обычный</w:t></w:r></w:p>
                  <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/></w:numPr></w:pPr><w:r><w:t>Пункт</w:t></w:r></w:p>
                  <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Ячейка</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
                </w:body></w:document>
                """,
            "word/styles.xml": """
                <w:styles \(w)><w:style w:type="paragraph" w:styleId="1"><w:name w:val="heading 1"/></w:style></w:styles>
                """,
            "docProps/core.xml": """
                <cp:coreProperties xmlns:cp="x" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Курсовая</dc:title></cp:coreProperties>
                """,
        ])
        let prepared = try prepare(file, .docx)
        let text = try html(prepared)
        #expect(prepared.document.title == "Курсовая")
        #expect(text.contains("<h1>Введение</h1>"))
        #expect(text.contains("<strong>Жирный</strong> и обычный"))
        #expect(text.contains("<ul><li>Пункт</li></ul>"))
        #expect(text.contains("<td>"))
    }

    @Test func pptxPutsTitleFirstOnEachSlide() throws {
        let p = "xmlns:p=\"p\" xmlns:a=\"a\" xmlns:r=\"r\""
        let file = try zip("deck.pptx", [
            "ppt/presentation.xml": "<p:presentation \(p)><p:sldIdLst><p:sldId id=\"256\" r:id=\"rId2\"/></p:sldIdLst></p:presentation>",
            "ppt/_rels/presentation.xml.rels": "<Relationships><Relationship Id=\"rId2\" Target=\"slides/slide1.xml\"/></Relationships>",
            "ppt/slides/slide1.xml": """
                <p:sld \(p)><p:cSld><p:spTree>
                  <p:sp><p:txBody><a:p><a:r><a:t>Первый пункт</a:t></a:r></a:p><a:p><a:r><a:t>Второй</a:t></a:r></a:p></p:txBody></p:sp>
                  <p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>План доклада</a:t></a:r></a:p></p:txBody></p:sp>
                </p:spTree></p:cSld></p:sld>
                """,
        ])
        let text = try html(try prepare(file, .pptx))
        #expect(text.contains("data-lumen-label=\"Слайд 1\""))
        let title = try #require(text.range(of: "<h2>План доклада</h2>"))
        let list = try #require(text.range(of: "<ul><li>Первый пункт</li><li>Второй</li></ul>"))
        #expect(title.lowerBound < list.lowerBound)
    }

    @Test func plainTextAndMarkdown() throws {
        #expect(TextConverter.plainText("Первый\nабзац\n\nВторой <абзац>") == "<p>Первый абзац</p>\n<p>Второй &lt;абзац&gt;</p>")
        let html = TextConverter.markdown("# Заголовок\n\n- один\n- **два**\n\nТекст с `кодом`")
        #expect(html.contains("<h1>Заголовок</h1>"))
        #expect(html.contains("<ul>\n<li>один</li>\n<li><strong>два</strong></li>\n</ul>"))
        #expect(html.contains("<p>Текст с <code>кодом</code></p>"))
    }

    @Test func windows1251TextIsDecoded() throws {
        let file = folder.appendingPathComponent("book.txt")
        try #require("Привет, мир".data(using: .windowsCP1251)).write(to: file)
        #expect(try TextConverter.readText(file) == "Привет, мир")
    }

    @Test func secondOpenUsesCache() throws {
        let file = folder.appendingPathComponent("notes.md")
        try "# Один".write(to: file, atomically: true, encoding: .utf8)
        let key = UUID().uuidString
        let first = try DocumentConverter.prepareSync(file: file, format: .markdown, cacheKey: key)
        try FileManager.default.removeItem(at: file)
        let second = try DocumentConverter.prepareSync(file: file, format: .markdown, cacheKey: key)
        #expect(first == second)
        DocumentConverter.removeCache(for: key)
    }

    @Test func unsupportedFormatsGoToSystemPreview() {
        #expect(!DocumentConverter.canConvert(.pdf))
        #expect(!DocumentConverter.canConvert(.other))
        #expect(throws: ReaderError.unsupportedFormat) {
            try DocumentConverter.prepareSync(file: URL(fileURLWithPath: "/tmp/x.xlsx"), format: .other, cacheKey: "x")
        }
    }

    @Test func formatsFromExtensions() {
        #expect(SourceFormat(fileExtension: "EPUB") == .epub)
        #expect(SourceFormat(fileExtension: "docx") == .docx)
        #expect(SourceFormat(fileExtension: "pptx") == .pptx)
        #expect(SourceFormat(fileExtension: "xlsx") == .other)
        #expect(SourceFormat(fileExtension: "jpeg") == .image)
    }

    @Test func excerptLinkRoundTrips() throws {
        let reference = ExcerptReference(sourceId: UUID(), highlightId: UUID(), label: "стр. 3")
        let parsed = try #require(ExcerptReference(url: reference.url))
        #expect(parsed.sourceId == reference.sourceId)
        #expect(parsed.highlightId == reference.highlightId)
    }
}
