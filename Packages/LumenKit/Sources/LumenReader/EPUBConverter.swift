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

        let entries = tableOfContents(package: package, manifest: manifest.mapValues { (href: $0.href, properties: $0.properties) }, root: folder)
        var titles: [String: String] = [:]
        for entry in entries where titles[entry.path] == nil {
            titles[entry.path] = entry.title
        }

        var sections: [ReadableSection] = []
        for itemref in package.descendants("itemref") where itemref.attribute("linear") != "no" {
            guard let id = itemref.attribute("idref"), let item = manifest[id] else { continue }
            guard item.mediaType.contains("html") || item.href.hasSuffix("html") || item.href.hasSuffix(".htm") else { continue }
            let number = sections.count + 1
            sections.append(ReadableSection(title: titles[item.href] ?? "Глава \(number)", path: item.href))
        }
        guard !sections.isEmpty else { throw ReaderError.unreadable }

        // Пункты оглавления, которые ведут в главы книги. Ссылки на файлы вне порядка чтения пропускаются.
        var sectionIndex: [String: Int] = [:]
        for (index, section) in sections.enumerated() where sectionIndex[section.path] == nil {
            sectionIndex[section.path] = index
        }
        let toc = entries.compactMap { entry -> TocEntry? in
            guard let section = sectionIndex[entry.path] else { return nil }
            return TocEntry(title: entry.title, section: section, anchor: entry.anchor, level: entry.level)
        }
        return ReadableDocument(
            title: title?.isEmpty == false ? title : nil,
            author: author?.isEmpty == false ? author : nil,
            sections: sections,
            coverPath: coverPath,
            toc: toc
        )
    }

    struct NavEntry {
        var title: String
        var path: String
        var anchor: String?
        var level: Int
    }

    /// Оглавление EPUB 3 (nav) или EPUB 2 (NCX) с вложенностью, по порядку.
    private static func tableOfContents(
        package: XElement,
        manifest: [String: (href: String, properties: String)],
        root: URL
    ) -> [NavEntry] {
        var entries: [NavEntry] = []
        func add(_ href: String, base: String, title: String, level: Int) {
            let parts = href.components(separatedBy: "#")
            let path = parts[0].isEmpty ? base : join((base as NSString).deletingLastPathComponent, parts[0])
            let title = title.collapsedWhitespace
            guard !title.isEmpty else { return }
            let anchor = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            entries.append(NavEntry(title: title, path: path, anchor: anchor, level: level))
        }

        if let nav = manifest.values.first(where: { $0.properties.contains("nav") }),
           let tree = XMLTree.parse(contentsOf: root.appendingPathComponent(nav.href)) {
            let tocNav = tree.descendants("nav").first { $0.attribute("type") == "toc" } ?? tree.descendants("nav").first
            func walk(_ list: XElement, level: Int) {
                for item in list.children("li") {
                    if let link = item.child("a"), let href = link.attribute("href") {
                        add(href, base: nav.href, title: link.text, level: level)
                    }
                    if let nested = item.child("ol") ?? item.child("ul") {
                        walk(nested, level: level + 1)
                    }
                }
            }
            if let list = tocNav?.child("ol") ?? tocNav?.child("ul") {
                walk(list, level: 0)
            }
        }
        if entries.isEmpty,
           let tocId = package.descendants("spine").first?.attribute("toc"),
           let ncx = manifest[tocId],
           let tree = XMLTree.parse(contentsOf: root.appendingPathComponent(ncx.href)) {
            func walk(_ parent: XElement, level: Int) {
                for point in parent.children("navPoint") {
                    if let src = point.child("content")?.attribute("src") {
                        add(src, base: ncx.href, title: point.child("navLabel")?.text ?? "", level: level)
                    }
                    walk(point, level: level + 1)
                }
            }
            if let map = tree.descendants("navMap").first {
                walk(map, level: 0)
            }
        }
        return entries
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

    /// Пробелы и переносы строк внутри схлопнуты в один пробел.
    var collapsedWhitespace: String { split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
