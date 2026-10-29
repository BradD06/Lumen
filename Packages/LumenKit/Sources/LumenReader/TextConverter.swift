import Foundation
import LumenCore
import ZIPFoundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Простые форматы: текст, Markdown, HTML, RTF (и на Mac ещё DOC и ODT через системный разбор).
enum TextConverter {
    static func convert(file: URL, format: SourceFormat, into folder: URL) throws -> ReadableDocument {
        let index = folder.appendingPathComponent("index.html")
        let title = file.deletingPathExtension().lastPathComponent
        switch format {
        case .txt:
            try HTML.page(title: title, body: plainText(try readText(file))).write(to: index, atomically: true, encoding: .utf8)
        case .markdown:
            try HTML.page(title: title, body: markdown(try readText(file))).write(to: index, atomically: true, encoding: .utf8)
        case .html:
            try FileManager.default.copyItem(at: file, to: index)
        case .rtf, .doc, .odt:
            try attributedHTML(file: file, format: format).write(to: index)
        default:
            throw ReaderError.unsupportedFormat
        }
        return ReadableDocument(sections: [ReadableSection(title: title, path: "index.html")])
    }

    /// Текст в UTF-8, а если не вышло, в кодировке Windows-1251: так часто сохранены русские книги.
    static func readText(_ file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1251) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    /// Абзацы разделены пустыми строками. Если пустых строк нет, абзацем считается каждая строка.
    static func plainText(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let hasBlankLines = normalized.contains("\n\n")
        let paragraphs = hasBlankLines
            ? normalized.components(separatedBy: "\n\n").map { $0.replacingOccurrences(of: "\n", with: " ") }
            : normalized.components(separatedBy: "\n")
        return paragraphs
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .map { "<p>\(HTML.escape($0))</p>" }
            .joined(separator: "\n")
    }

    /// Небольшая часть Markdown: заголовки, списки, цитаты, код, жирный, курсив и `код` в строке.
    static func markdown(_ text: String) -> String {
        var html = ""
        var paragraph: [String] = []
        var list: String?
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html += "<p>\(inlineMarkdown(paragraph.joined(separator: " ")))</p>\n"
            paragraph = []
        }
        func closeList() {
            if let tag = list { html += "</\(tag)>\n" }
            list = nil
        }

        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flushParagraph()
                closeList()
                html += inCode ? "</code></pre>\n" : "<pre><code>"
                inCode.toggle()
                continue
            }
            if inCode {
                html += HTML.escape(rawLine) + "\n"
                continue
            }
            if line.isEmpty {
                flushParagraph()
                closeList()
                continue
            }
            if let level = headingLevel(line) {
                flushParagraph()
                closeList()
                let content = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                html += "<h\(level)>\(inlineMarkdown(content))</h\(level)>\n"
            } else if let item = listItem(line) {
                flushParagraph()
                if list != item.tag {
                    closeList()
                    html += "<\(item.tag)>\n"
                    list = item.tag
                }
                html += "<li>\(inlineMarkdown(item.text))</li>\n"
            } else if line.hasPrefix(">") {
                flushParagraph()
                closeList()
                html += "<blockquote>\(inlineMarkdown(String(line.dropFirst()).trimmed))</blockquote>\n"
            } else if line == "---" || line == "***" {
                flushParagraph()
                closeList()
                html += "<hr>\n"
            } else {
                closeList()
                paragraph.append(line)
            }
        }
        flushParagraph()
        closeList()
        if inCode { html += "</code></pre>\n" }
        return html
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func listItem(_ line: String) -> (tag: String, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return ("ul", String(line.dropFirst(marker.count)))
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return ("ol", String(line.dropFirst(digits.count + 2)))
        }
        return nil
    }

    static func inlineMarkdown(_ text: String) -> String {
        var html = HTML.escape(text)
        let rules: [(String, String)] = [
            ("`([^`]+)`", "<code>$1</code>"),
            ("\\*\\*([^*]+)\\*\\*", "<strong>$1</strong>"),
            ("__([^_]+)__", "<strong>$1</strong>"),
            ("\\*([^*]+)\\*", "<em>$1</em>"),
            ("\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", "<a href=\"$2\">$1</a>"),
        ]
        for (pattern, template) in rules {
            html = html.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return html
    }

    /// RTF (и на Mac DOC и ODT) через системный разбор текста с оформлением, на выходе HTML.
    private static func attributedHTML(file: URL, format: SourceFormat) throws -> Data {
        let type: NSAttributedString.DocumentType
        switch format {
        case .rtf: type = .rtf
        #if os(macOS)
        case .doc: type = .docFormat
        case .odt: type = .openDocument
        #endif
        default: throw ReaderError.unsupportedFormat
        }
        let string = try NSAttributedString(url: file, options: [.documentType: type], documentAttributes: nil)
        return try string.data(
            from: NSRange(location: 0, length: string.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
    }
}

/// Комикс в CBZ: архив картинок, которые идут по порядку имён одной длинной лентой.
enum CBZConverter {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic"]

    static func convert(file: URL, into folder: URL) throws -> ReadableDocument {
        try FileManager.default.unzipItem(at: file, to: folder)
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            throw ReaderError.unreadable
        }
        let rootPath = folder.resolvingSymlinksInPath().path
        var images: [String] = []
        for case let url as URL in enumerator where imageExtensions.contains(url.pathExtension.lowercased()) {
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(rootPath), !path.contains("/__MACOSX/") else { continue }
            images.append(String(path.dropFirst(rootPath.count + 1)))
        }
        images.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !images.isEmpty else { throw ReaderError.unreadable }

        let body = images.enumerated().map { index, path in
            "<p class=\"page\" data-lumen-label=\"Стр. \(index + 1)\"><img src=\"\(HTML.escape(path))\" alt=\"\"></p>"
        }.joined(separator: "\n")
        try HTML.page(title: "", body: body).write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let title = file.deletingPathExtension().lastPathComponent
        return ReadableDocument(sections: [ReadableSection(title: title, path: "index.html")], coverPath: images.first)
    }
}
