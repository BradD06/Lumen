import Foundation

/// Файл в блоке «Файл», «PDF», «Видео» или «Аудио». Сам файл лежит во вложениях
/// (`BlockContent.attachment`), здесь то, что показывается людям.
public struct FileAttachment: Hashable, Codable, Sendable {
    /// Имя файла, каким его добавили: «Лекция 3.pdf».
    public var name: String
    /// Размер в байтах.
    public var size: Int64?

    public init(name: String, size: Int64? = nil) {
        self.name = name
        self.size = size
    }

    /// «2,4 МБ».
    public var sizeText: String? {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    /// Значок по расширению.
    public var symbolName: String {
        Self.symbolName(forExtension: (name as NSString).pathExtension)
    }

    public static func symbolName(forExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "doc", "docx", "rtf", "pages", "txt", "md", "odt": "doc.text"
        case "xls", "xlsx", "csv", "numbers", "ods": "tablecells"
        case "ppt", "pptx", "key", "odp": "rectangle.on.rectangle"
        case "zip", "rar", "7z", "gz", "tar": "archivebox"
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff", "caf": "waveform"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": "film"
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff": "photo"
        case "epub", "fb2", "mobi", "djvu": "book.closed"
        default: "doc"
        }
    }
}

/// Закладка на сайт: адрес и превью, как в Notion (название, описание, картинка, значок).
/// Картинка и значок скачиваются во вложения, чтобы закладка выглядела так же без сети.
public struct WebBookmark: Hashable, Codable, Sendable {
    public var url: String
    public var title: String?
    public var summary: String?
    public var siteName: String?
    /// Картинка превью во вложениях.
    public var image: String?
    /// Значок сайта во вложениях.
    public var icon: String?

    public init(url: String, title: String? = nil, summary: String? = nil, siteName: String? = nil, image: String? = nil, icon: String? = nil) {
        self.url = url
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.image = image
        self.icon = icon
    }

    /// Сайт без `https://` и `www.`: «ru.wikipedia.org».
    public var host: String {
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Адрес, как его ввели: без схемы дописывается `https://`. `nil`, если это не адрес.
    public static func normalizedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host(), host.contains(".") else { return nil }
        return url
    }
}

/// Превью страницы сайта из её HTML: `og:` и обычные мета-теги.
public struct WebPreview: Equatable, Sendable {
    public var title: String?
    public var summary: String?
    public var siteName: String?
    public var imageURL: URL?
    public var iconURL: URL?

    public init(title: String? = nil, summary: String? = nil, siteName: String? = nil, imageURL: URL? = nil, iconURL: URL? = nil) {
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.imageURL = imageURL
        self.iconURL = iconURL
    }

    public static func parse(html: String, baseURL: URL) -> WebPreview {
        // Мета-теги стоят в <head>: дальше читать незачем.
        let head: Substring
        if let end = html.range(of: "</head>", options: .caseInsensitive) {
            head = html[..<end.lowerBound]
        } else {
            head = html.prefix(200_000)
        }
        let text = String(head)

        var meta: [String: String] = [:]
        for tag in matches(#"<meta\b[^>]*>"#, in: text) {
            let attributes = attributes(of: tag)
            guard let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased(),
                  let content = attributes["content"], meta[key] == nil else { continue }
            meta[key] = decodeEntities(content).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var preview = WebPreview()
        let titleTag = firstGroup(#"<title\b[^>]*>([\s\S]*?)</title>"#, in: text).map(decodeEntities)
        preview.title = nonEmpty(meta["og:title"] ?? meta["twitter:title"] ?? titleTag.map(collapseSpaces))
        preview.summary = nonEmpty(meta["og:description"] ?? meta["twitter:description"] ?? meta["description"])
        preview.siteName = nonEmpty(meta["og:site_name"] ?? meta["application-name"])
        if let image = meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"] ?? meta["twitter:image:src"] {
            preview.imageURL = URL(string: image, relativeTo: baseURL)?.absoluteURL
        }

        var icons: [(rank: Int, href: String)] = []
        for tag in matches(#"<link\b[^>]*>"#, in: text) {
            let attributes = attributes(of: tag)
            guard let rel = attributes["rel"]?.lowercased(), rel.contains("icon"), let href = attributes["href"] else { continue }
            // Большой значок лучше крошечного favicon.
            let rank = rel.contains("apple-touch-icon") ? 0 : (rel.contains("mask") ? 3 : 1)
            icons.append((rank, decodeEntities(href)))
        }
        if let best = icons.min(by: { $0.rank < $1.rank }) {
            preview.iconURL = URL(string: best.href, relativeTo: baseURL)?.absoluteURL
        } else if let scheme = baseURL.scheme, let host = baseURL.host() {
            preview.iconURL = URL(string: "\(scheme)://\(host)/favicon.ico")
        }
        return preview
    }

    // MARK: Разбор

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Атрибуты тега: имена строчными буквами, значения в кавычках или без.
    static func attributes(of tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#) else { return [:] }
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let value = (2...4).lazy.compactMap { Range(match.range(at: $0), in: tag) }.first.map { String(tag[$0]) } ?? ""
            result[tag[nameRange].lowercased()] = value
        }
        return result
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&laquo;": "«", "&raquo;": "»", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) {
            let text = NSMutableString(string: result)
            // С конца, чтобы места ещё не заменённых кодов не съезжали.
            for match in regex.matches(in: result, range: NSRange(location: 0, length: text.length)).reversed() {
                let code = text.substring(with: match.range(at: 1))
                let value = code.hasPrefix("x") || code.hasPrefix("X") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
                if let value, let scalar = Unicode.Scalar(value) {
                    text.replaceCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
            result = text as String
        }
        // &amp; последним, чтобы «&amp;lt;» не стало «<».
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
