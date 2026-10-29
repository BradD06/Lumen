import Foundation
import ZIPFoundation

/// EPUB уже состоит из HTML: архив распаковывается, а из OPF берутся порядок глав,
/// названия из оглавления, автор и обложка.
enum EPUBConverter {
    static func convert(file: URL, into folder: URL) throws -> ReadableDocument {
        try FileManager.default.unzipItem(at: file, to: folder)

        guard let container = XMLTree.parse(contentsOf: folder.appendingPathComponent("META-INF/container.xml")),
              let opfPath = container.descendants("rootfile").first?.attribute("full-path"),
              let package = XMLTree.parse(contentsOf: folder.appendingPathComponent(opfPath)) else {
            throw ReaderError.unreadable
        }
        let opfDir = (opfPath as NSString).deletingLastPathComponent

        struct Item {
            var href: String
            var mediaType: String
            var properties: String
        }
        var manifest: [String: Item] = [:]
        for item in package.descendants("item") {
            guard let id = item.attribute("id"), let href = item.attribute("href") else { continue }
            manifest[id] = Item(
                href: join(opfDir, href),
                mediaType: item.attribute("media-type") ?? "",
                properties: item.attribute("properties") ?? ""
            )
        }

        let metadata = package.child("metadata")
        let title = metadata?.descendants("title").first?.text.trimmed
        let author = metadata?.descendants("creator").map(\.text.trimmed).filter { !$0.isEmpty }.joined(separator: ", ")

        // Обложка: EPUB 3 помечает её свойством, EPUB 2 мета-тегом с id картинки.
        var coverPath = manifest.values.first { $0.properties.contains("cover-image") }?.href
        if coverPath == nil,
           let coverId = metadata?.descendants("meta").first(where: { $0.attribute("name") == "cover" })?.attribute("content") {
            coverPath = manifest[coverId]?.href
        }

        let titles = tableOfContents(package: package, manifest: manifest.mapValues { (href: $0.href, properties: $0.properties) }, root: folder)

        var sections: [ReadableSection] = []
        for itemref in package.descendants("itemref") where itemref.attribute("linear") != "no" {
            guard let id = itemref.attribute("idref"), let item = manifest[id] else { continue }
            guard item.mediaType.contains("html") || item.href.hasSuffix("html") || item.href.hasSuffix(".htm") else { continue }
            let number = sections.count + 1
            sections.append(ReadableSection(title: titles[item.href] ?? "Глава \(number)", path: item.href))
        }
        guard !sections.isEmpty else { throw ReaderError.unreadable }
        return ReadableDocument(
            title: title?.isEmpty == false ? title : nil,
            author: author?.isEmpty == false ? author : nil,
            sections: sections,
            coverPath: coverPath
        )
    }

    /// Названия глав по пути файла: из оглавления EPUB 3 (nav) или EPUB 2 (NCX).
    private static func tableOfContents(
        package: XElement,
        manifest: [String: (href: String, properties: String)],
        root: URL
    ) -> [String: String] {
        var titles: [String: String] = [:]
        func add(_ href: String, base: String, title: String) {
            let path = join((base as NSString).deletingLastPathComponent, href.components(separatedBy: "#")[0])
            let title = title.trimmed
            if !title.isEmpty, titles[path] == nil { titles[path] = title }
        }

        if let nav = manifest.values.first(where: { $0.properties.contains("nav") }),
           let tree = XMLTree.parse(contentsOf: root.appendingPathComponent(nav.href)) {
            let tocNav = tree.descendants("nav").first { $0.attribute("type") == "toc" } ?? tree.descendants("nav").first
            for link in tocNav?.descendants("a") ?? [] {
                if let href = link.attribute("href") { add(href, base: nav.href, title: link.text) }
            }
        }
        if titles.isEmpty,
           let tocId = package.descendants("spine").first?.attribute("toc"),
           let ncx = manifest[tocId],
           let tree = XMLTree.parse(contentsOf: root.appendingPathComponent(ncx.href)) {
            for point in tree.descendants("navPoint") {
                guard let src = point.child("content")?.attribute("src") else { continue }
                add(src, base: ncx.href, title: point.child("navLabel")?.text ?? "")
            }
        }
        return titles
    }

    /// Путь внутри архива: папка OPF плюс относительная ссылка, без `..` и процентов.
    static func join(_ base: String, _ href: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var parts = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            switch part {
            case ".", "": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
