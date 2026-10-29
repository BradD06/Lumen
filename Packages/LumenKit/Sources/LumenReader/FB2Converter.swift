import Foundation

/// FictionBook 2: одна XML-книга, картинки внутри неё в base64. Каждый раздел верхнего уровня
/// становится главой, примечания идут последней главой.
enum FB2Converter {
    static func convert(file: URL, into folder: URL) throws -> ReadableDocument {
        guard let book = XMLTree.parse(contentsOf: file), book.localName == "FictionBook" else {
            throw ReaderError.unreadable
        }

        // Картинки из base64 в файлы рядом с главами.
        let images = folder.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        var imagePaths: [String: String] = [:]
        for binary in book.children("binary") {
            guard let id = binary.attribute("id"),
                  let data = Data(base64Encoded: binary.text, options: .ignoreUnknownCharacters) else { continue }
            let name = "\(imagePaths.count)-\(safeFileName(id))"
            try data.write(to: images.appendingPathComponent(name))
            imagePaths[id] = "images/\(name)"
        }

        let info = book.child("description")?.child("title-info")
        let title = info?.child("book-title")?.text.trimmed
        let author = info?.children("author").map { author in
            ["first-name", "middle-name", "last-name"]
                .compactMap { author.child($0)?.text.trimmed }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
        let coverId = info?.child("coverpage")?.child("image").flatMap(imageId)

        let renderer = Renderer(imagePaths: imagePaths)
        var sections: [ReadableSection] = []
        func write(_ body: String, title: String) throws {
            let path = "section-\(sections.count + 1).html"
            try HTML.page(title: title, body: body).write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
            sections.append(ReadableSection(title: title, path: path))
        }

        for body in book.children("body") {
            let isNotes = body.attribute("name") == "notes" || body.attribute("name") == "comments"
            if isNotes {
                try write(renderer.render(children: body), title: "Примечания")
                continue
            }
            let topSections = body.children("section")
            if topSections.isEmpty {
                try write(renderer.render(children: body), title: title ?? "Текст")
                continue
            }
            // Заголовок и эпиграф книги перед первым разделом попадают в первую главу.
            var preface = ""
            for element in body.elements where element.localName != "section" {
                preface += renderer.render(element)
            }
            for (index, section) in topSections.enumerated() {
                let sectionTitle = section.child("title")?.text.trimmed.replacingOccurrences(of: "\n", with: " ")
                let html = (index == 0 ? preface : "") + renderer.render(children: section)
                try write(html, title: sectionTitle?.isEmpty == false ? sectionTitle! : "Глава \(sections.count + 1)")
            }
        }
        guard !sections.isEmpty else { throw ReaderError.unreadable }
        return ReadableDocument(
            title: title?.isEmpty == false ? title : nil,
            author: author?.isEmpty == false ? author : nil,
            sections: sections,
            coverPath: coverId.flatMap { imagePaths[$0] }
        )
    }

    static func imageId(_ image: XElement) -> String? {
        image.attribute("href").map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
    }

    static func safeFileName(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    private struct Renderer {
        let imagePaths: [String: String]

        func render(children element: XElement) -> String {
            element.nodes.map { node in
                switch node {
                case .text(let text): HTML.escape(text)
                case .element(let child): render(child)
                }
            }.joined()
        }

        func render(_ element: XElement) -> String {
            let inner = { render(children: element) }
            switch element.localName {
            case "section": return "<section>\(inner())</section>"
            case "title": return "<h2>\(element.children("p").map { HTML.escape($0.text) }.joined(separator: "<br>"))</h2>"
            case "subtitle": return "<h3>\(inner())</h3>"
            case "p": return "<p>\(inner())</p>"
            case "v": return "<p class=\"verse\">\(inner())</p>"
            case "text-author": return "<p class=\"text-author\">\(inner())</p>"
            case "emphasis": return "<em>\(inner())</em>"
            case "strong": return "<strong>\(inner())</strong>"
            case "strikethrough": return "<s>\(inner())</s>"
            case "sub": return "<sub>\(inner())</sub>"
            case "sup": return "<sup>\(inner())</sup>"
            case "code": return "<code>\(inner())</code>"
            case "empty-line": return "<br>"
            case "epigraph", "cite": return "<blockquote>\(inner())</blockquote>"
            case "poem", "stanza": return "<div class=\"poem\">\(inner())</div>"
            case "annotation": return "<div class=\"annotation\">\(inner())</div>"
            case "table": return "<table>\(inner())</table>"
            case "tr": return "<tr>\(inner())</tr>"
            case "td": return "<td>\(inner())</td>"
            case "th": return "<th>\(inner())</th>"
            case "a": return "<span class=\"note-ref\">\(inner())</span>"
            case "image":
                guard let id = FB2Converter.imageId(element), let path = imagePaths[id] else { return "" }
                return "<p class=\"image\"><img src=\"\(HTML.escape(path))\" alt=\"\"></p>"
            case "binary", "description": return ""
            default: return inner()
            }
        }
    }
}
