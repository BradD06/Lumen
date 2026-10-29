import Foundation
import ZIPFoundation

/// Презентация PowerPoint (PPTX) в HTML: каждый слайд карточкой с заголовком, текстом, таблицами
/// и картинками. Расположение элементов на слайде не повторяется, это делает системный просмотр.
enum PPTXConverter {
    static func convert(file: URL, into folder: URL) throws -> ReadableDocument {
        try FileManager.default.unzipItem(at: file, to: folder)
        guard let presentation = XMLTree.parse(contentsOf: folder.appendingPathComponent("ppt/presentation.xml")) else {
            throw ReaderError.unreadable
        }
        let presentationRels = OfficeRelationships(folder: folder, part: "ppt/presentation.xml")
        // У sldId два атрибута id: числовой `id` и связь `r:id`, нужна связь.
        let slidePaths = presentation.descendants("sldId").compactMap { slide in
            slide.attributes.first { $0.key.hasSuffix(":id") }.flatMap { presentationRels.target($0.value) }
        }
        guard !slidePaths.isEmpty else { throw ReaderError.unreadable }

        var html = ""
        for (index, path) in slidePaths.enumerated() {
            guard let slide = XMLTree.parse(contentsOf: folder.appendingPathComponent(path)) else { continue }
            let renderer = SlideRenderer(relationships: OfficeRelationships(folder: folder, part: path))
            let number = index + 1
            html += "<section class=\"slide\" data-lumen-label=\"Слайд \(number)\">"
            html += "<div class=\"slide-number\">\(number)</div>"
            html += renderer.render(tree: slide.descendants("spTree").first)
            html += "</section>"
        }
        try HTML.page(title: "", body: html).write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        let core = OfficeCoreProperties(folder: folder)
        return ReadableDocument(
            title: core.title,
            author: core.author,
            sections: [ReadableSection(title: core.title ?? "Слайды", path: "index.html")]
        )
    }

    private struct SlideRenderer {
        let relationships: OfficeRelationships

        func render(tree: XElement?) -> String {
            guard let tree else { return "" }
            // Заголовок слайда первым, даже если в файле он стоит позже текста.
            let shapes = tree.elements
            let titles = shapes.filter(isTitle)
            return (titles + shapes.filter { !isTitle($0) }).map { render($0) }.joined()
        }

        private func isTitle(_ shape: XElement) -> Bool {
            guard shape.localName == "sp" else { return false }
            let type = shape.descendants("ph").first?.attribute("type")
            return type == "title" || type == "ctrTitle"
        }

        private func render(_ shape: XElement) -> String {
            switch shape.localName {
            case "sp":
                guard let body = shape.child("txBody") else { return "" }
                let paragraphs = body.children("p").map { paragraph($0) }.filter { !$0.isEmpty }
                guard !paragraphs.isEmpty else { return "" }
                if isTitle(shape) {
                    return "<h2>\(paragraphs.joined(separator: "<br>"))</h2>"
                }
                if paragraphs.count == 1 { return "<p>\(paragraphs[0])</p>" }
                return "<ul>" + paragraphs.map { "<li>\($0)</li>" }.joined() + "</ul>"
            case "pic":
                guard let id = shape.descendants("blip").first?.attribute("embed"),
                      let path = relationships.target(id) else { return "" }
                return "<p class=\"image\"><img src=\"\(HTML.escape(path))\" alt=\"\"></p>"
            case "graphicFrame":
                guard let table = shape.descendants("tbl").first else { return "" }
                let rows = table.children("tr").map { row in
                    "<tr>" + row.children("tc").map { cell in
                        "<td>" + cell.descendants("p").map { paragraph($0) }.joined(separator: "<br>") + "</td>"
                    }.joined() + "</tr>"
                }
                return "<table>\(rows.joined())</table>"
            case "grpSp":
                return render(tree: shape)
            default:
                return ""
            }
        }

        private func paragraph(_ p: XElement) -> String {
            p.elements.map { child in
                switch child.localName {
                case "r", "fld":
                    var text = HTML.escape(child.child("t")?.text ?? "")
                    let properties = child.child("rPr")
                    if properties?.attribute("b") == "1" { text = "<strong>\(text)</strong>" }
                    if properties?.attribute("i") == "1" { text = "<em>\(text)</em>" }
                    return text
                case "br":
                    return "<br>"
                default:
                    return ""
                }
            }.joined()
        }
    }
}
