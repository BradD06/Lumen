import Foundation
import Testing
@testable import LumenCore

struct WebPreviewTests {
    let base = URL(string: "https://example.com/articles/1")!

    @Test func openGraphWinsOverTitle() {
        let html = """
            <html><head>
            <title>  Заголовок
              вкладки </title>
            <meta property="og:title" content="Статья &laquo;Про книги&raquo;">
            <meta name="description" content='Обычное описание'>
            <meta property="og:description" content="Описание &amp; подробности">
            <meta property="og:site_name" content="Пример">
            <meta property="og:image" content="/img/cover.png">
            <link rel="icon" href="/favicon-32.png">
            <link rel="apple-touch-icon" href="https://cdn.example.com/touch.png">
            </head><body><meta property="og:title" content="Не то"></body></html>
            """
        let preview = WebPreview.parse(html: html, baseURL: base)
        #expect(preview.title == "Статья «Про книги»")
        #expect(preview.summary == "Описание & подробности")
        #expect(preview.siteName == "Пример")
        #expect(preview.imageURL?.absoluteString == "https://example.com/img/cover.png")
        #expect(preview.iconURL?.absoluteString == "https://cdn.example.com/touch.png")
    }

    @Test func plainPageFallsBackToTitleAndFavicon() {
        let preview = WebPreview.parse(html: "<HTML><HEAD><TITLE>Просто\n  страница</TITLE></HEAD></HTML>", baseURL: base)
        #expect(preview.title == "Просто страница")
        #expect(preview.summary == nil)
        #expect(preview.imageURL == nil)
        #expect(preview.iconURL?.absoluteString == "https://example.com/favicon.ico")
    }

    @Test func entitiesAndAttributes() {
        #expect(WebPreview.decodeEntities("&#1055;&#x440;&#1080; &amp;lt;") == "При &lt;")
        let attributes = WebPreview.attributes(of: #"<meta PROPERTY="og:title" content='a "b"' data-x=1>"#)
        #expect(attributes["property"] == "og:title")
        #expect(attributes["content"] == #"a "b""#)
        #expect(attributes["data-x"] == "1")
    }

    @Test func addressesAreNormalized() {
        #expect(WebBookmark.normalizedURL("ru.wikipedia.org/wiki/Книга")?.scheme == "https")
        #expect(WebBookmark.normalizedURL("  http://example.com  ")?.absoluteString == "http://example.com")
        #expect(WebBookmark.normalizedURL("просто текст") == nil)
        #expect(WebBookmark.normalizedURL("ftp://example.com") == nil)
        #expect(WebBookmark.normalizedURL("localhost") == nil)
        #expect(WebBookmark(url: "https://www.example.com/a").host == "example.com")
    }
}

struct FileAttachmentTests {
    @Test func symbolsAndSize() {
        #expect(FileAttachment(name: "Лекция.PDF").symbolName == "doc.richtext")
        #expect(FileAttachment(name: "запись.m4a").symbolName == "waveform")
        #expect(FileAttachment(name: "без расширения").symbolName == "doc")
        // Книги и документы с тем же значком, что в библиотеке.
        #expect(FileAttachment(name: "Роман.epub").symbolName == SourceFormat.epub.symbolName)
        #expect(FileAttachment(name: "План.xlsx").symbolName == "tablecells")
        #expect(FileAttachment.opensInReader("pdf"))
        #expect(FileAttachment.opensInReader("EPUB"))
        #expect(!FileAttachment.opensInReader("zip"))
        #expect(!FileAttachment.opensInReader("png"), "Картинке свой блок")
        #expect(FileAttachment.isImage("HEIC"))
        #expect(FileAttachment(name: "a", size: 2_400_000).sizeText != nil)
    }

    @Test func contentKeepsFileAndBookmark() throws {
        var content = BlockContent()
        content.attachment = "abc.pdf"
        content.file = FileAttachment(name: "Конспект.pdf", size: 1024)
        content.bookmark = WebBookmark(url: "https://example.com", title: "Пример", summary: "Описание")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(BlockContent.self, from: data)
        #expect(decoded == content)
        #expect(decoded.searchText.contains("Конспект.pdf"))
        #expect(decoded.searchText.contains("Пример"))
        #expect(decoded.searchText.contains("https://example.com"))
    }

    @Test func markdownExportNamesFilesAndLinks() {
        let page = Page(title: "Т", sortKey: "a")
        let file = Block(pageId: page.id, type: .pdf, content: BlockContent(file: FileAttachment(name: "Лекция.pdf")), sortKey: "b")
        let link = Block(pageId: page.id, type: .bookmark, content: BlockContent(bookmark: WebBookmark(url: "https://example.com/x", title: "Сайт")), sortKey: "c")
        let markdown = PageExport(page: page, blocks: [file, link]).markdown()
        #expect(markdown.contains("📎 Лекция.pdf"))
        #expect(markdown.contains("🔗 [Сайт](https://example.com/x)"))
    }
}
