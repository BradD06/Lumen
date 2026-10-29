import Foundation
import ZIPFoundation

/// Документ Word (DOCX) в HTML: абзацы, заголовки, списки, жирный и курсив, таблицы и картинки.
/// Вёрстка страниц не сохраняется, зато текст можно выделять и делать из него выписки.
/// Точный вид оригинала показывает системный просмотр.
enum DOCXConverter {
    static func convert(file: URL, into folder: URL) throws -> ReadableDocument {
        try FileManager.default.unzipItem(at: file, to: folder)
        guard let document = XMLTree.parse(contentsOf: folder.appendingPathComponent("word/document.xml")),
              let body = document.child("body") else {
            throw ReaderError.unreadable
        }
        let relationships = OfficeRelationships(folder: folder, part: "word/document.xml")
        let styles = headingLevels(XMLTree.parse(contentsOf: folder.appendingPathComponent("word/styles.xml")))
        let renderer = Renderer(relationships: relationships, headingLevels: styles)
        let html = renderer.render(blocks: body.elements)
        try HTML.page(title: "", body: html).write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        let core = OfficeCoreProperties(folder: folder)
        return ReadableDocument(
            title: core.title,
            author: core.author,
            sections: [ReadableSection(title: core.title ?? "Документ", path: "index.html")]
        )
    }

    /// Уровни заголовков по id стилей: в русском Word стиль может называться «1», а не «Heading1».
    static func headingLevels(_ styles: XElement?) -> [String: Int] {
        var levels: [String: Int] = [:]
        for style in styles?.children("style") ?? [] {
            guard let id = style.attribute("styleId") else { continue }
            let name = (style.child("name")?.attribute("val") ?? id).lowercased()
            if name == "title" {
                levels[id] = 1
            } else if name == "subtitle" {
                levels[id] = 2
            } else if let level = headingLevel(name) {
                levels[id] = level
            } else if let outline = style.child("pPr")?.child("outlineLvl")?.attribute("val").flatMap(Int.init) {
                levels[id] = min(outline + 1, 6)
            }
        }
        return levels
    }

    /// `heading 2` → 2, `заголовок 3` → 3.
    static func headingLevel(_ name: String) -> Int? {
        for prefix in ["heading", "заголовок"] where name.hasPrefix(prefix) {
            let digits = name.dropFirst(prefix.count).filter(\.isNumber)
            if let level = Int(String(digits)), (1...6).contains(level) { return level }
        }
        return nil
    }

    private struct Renderer {
        let relationships: OfficeRelationships
        let headingLevels: [String: Int]

        func render(blocks: [XElement]) -> String {
            var html = ""
            var listOpen = false
            for element in blocks {
                let isListItem = element.localName == "p" && element.child("pPr")?.child("numPr") != nil
                if isListItem != listOpen {
                    html += isListItem ? "<ul>" : "</ul>"
                    listOpen = isListItem
                }
                switch element.localName {
                case "p": html += paragraph(element, asListItem: isListItem)
                case "tbl": html += table(element)
                case "sdt": html += render(blocks: element.child("sdtContent")?.elements ?? [])
                default: break
                }
            }
            if listOpen { html += "</ul>" }
            return html
        }

        private func paragraph(_ p: XElement, asListItem: Bool) -> String {
            let content = inline(p)
            if asListItem { return "<li>\(content)</li>" }
            let style = p.child("pPr")?.child("pStyle")?.attribute("val")
            if let style, let level = headingLevels[style] ?? DOCXConverter.headingLevel(style.lowercased()) {
                return "<h\(level)>\(content)</h\(level)>"
            }
            let alignment = p.child("pPr")?.child("jc")?.attribute("val")
            let center = alignment == "center" ? " class=\"center\"" : ""
            return content.isEmpty ? "<p class=\"empty\"><br></p>" : "<p\(center)>\(content)</p>"
        }

        private func table(_ tbl: XElement) -> String {
            let rows = tbl.children("tr").map { row in
                "<tr>" + row.children("tc").map { "<td>\(render(blocks: $0.elements))</td>" }.joined() + "</tr>"
            }
            return "<table>\(rows.joined())</table>"
        }

        /// Текст абзаца. Гиперссылки, исправления и поля Word здесь просто обёртки вокруг фрагментов.
        private func inline(_ element: XElement) -> String {
            element.elements.map { child in
                switch child.localName {
                case "r": run(child)
                case "hyperlink", "ins", "smartTag", "fldSimple", "customXml": inline(child)
                case "sdt": child.child("sdtContent").map { inline($0) } ?? ""
                default: ""
                }
            }.joined()
        }

        private func run(_ r: XElement) -> String {
            var text = ""
            for child in r.elements {
                switch child.localName {
                case "t": text += HTML.escape(child.text)
                case "tab": text += "&emsp;"
                case "br", "cr": text += "<br>"
                case "drawing", "pict":
                    for blip in child.descendants("blip") + child.descendants("imagedata") {
                        let id = blip.attribute("embed") ?? blip.attribute("id")
                        if let path = id.flatMap({ relationships.target($0) }) {
                            text += "<img src=\"\(HTML.escape(path))\" alt=\"\">"
                        }
                    }
                default: break
                }
            }
            guard !text.isEmpty, let properties = r.child("rPr") else { return text }
            func isOn(_ name: String) -> Bool {
                guard let element = properties.child(name) else { return false }
                let value = element.attribute("val")
                return value == nil || (value != "0" && value != "false" && value != "none")
            }
            if isOn("b") { text = "<strong>\(text)</strong>" }
            if isOn("i") { text = "<em>\(text)</em>" }
            if isOn("u") { text = "<u>\(text)</u>" }
            if isOn("strike") { text = "<s>\(text)</s>" }
            switch properties.child("vertAlign")?.attribute("val") {
            case "superscript": text = "<sup>\(text)</sup>"
            case "subscript": text = "<sub>\(text)</sub>"
            default: break
            }
            return text
        }
    }
}

/// Связи частей документа Office: по id из `r:embed` находится файл картинки.
struct OfficeRelationships {
    private var targets: [String: String] = [:]

    /// `part` это путь части внутри архива, например `word/document.xml`.
    init(folder: URL, part: String) {
        let directory = (part as NSString).deletingLastPathComponent
        let name = (part as NSString).lastPathComponent
        let relsPath = directory.isEmpty ? "_rels/\(name).rels" : "\(directory)/_rels/\(name).rels"
        guard let rels = XMLTree.parse(contentsOf: folder.appendingPathComponent(relsPath)) else { return }
        for relationship in rels.children("Relationship") {
            guard let id = relationship.attribute("Id"), let target = relationship.attribute("Target"),
                  relationship.attribute("TargetMode") != "External" else { continue }
            targets[id] = target.hasPrefix("/")
                ? EPUBConverter.join("", String(target.dropFirst()))
                : EPUBConverter.join(directory, target)
        }
    }

    /// Путь файла относительно папки документа.
    func target(_ id: String) -> String? { targets[id] }
}

/// Название и автор из `docProps/core.xml`, общие для Word и PowerPoint.
struct OfficeCoreProperties {
    var title: String?
    var author: String?

    init(folder: URL) {
        let core = XMLTree.parse(contentsOf: folder.appendingPathComponent("docProps/core.xml"))
        let title = core?.child("title")?.text.trimmed
        let author = core?.child("creator")?.text.trimmed
        self.title = title?.isEmpty == false ? title : nil
        self.author = author?.isEmpty == false ? author : nil
    }
}
