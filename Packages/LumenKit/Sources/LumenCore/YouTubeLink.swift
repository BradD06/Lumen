import Foundation

/// Ссылка на ролик YouTube в любом виде, в каком её копируют: `youtube.com/watch?v=`, `youtu.be/`,
/// `shorts/`, `embed/`, `live/`, мобильная и `music.` версии, с началом `t=1m30s` или без.
/// Видео в заметке хранится в блоке «Видео» как `content.bookmark` с адресом `watchURL`, без файла.
public struct YouTubeLink: Hashable, Sendable {
    /// Одиннадцать символов: `dQw4w9WgXcQ`.
    public var videoId: String
    /// С какой секунды начинать, если в ссылке было `t=` или `start=`.
    public var start: Int?
    /// Вертикальный ролик (Shorts): показывается кадром 9:16.
    public var isShort: Bool

    public init(videoId: String, start: Int? = nil, isShort: Bool = false) {
        self.videoId = videoId
        self.start = start
        self.isShort = isShort
    }

    /// `nil`, если это не ссылка на ролик YouTube (или на плейлист без ролика).
    public init?(string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = components.host?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "music."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        let items = components.queryItems ?? []
        func query(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let path = components.path.split(separator: "/").map(String.init)

        var id: String?
        var isShort = false
        switch host {
        case "youtu.be":
            id = path.first
        case "youtube.com", "youtube-nocookie.com":
            if path.first == "watch" || path.isEmpty {
                id = query("v")
            } else if path.count >= 2, ["shorts", "embed", "live", "v", "e"].contains(path[0]) {
                id = path[1]
                isShort = path[0] == "shorts"
            }
        default:
            return nil
        }
        guard let id, Self.isVideoId(id) else { return nil }
        self.videoId = id
        self.isShort = isShort
        // У youtu.be начало бывает и в `#t=`.
        let fragmentStart = components.fragment.flatMap { fragment in
            fragment.hasPrefix("t=") ? String(fragment.dropFirst(2)) : nil
        }
        self.start = (query("t") ?? query("start") ?? fragmentStart).flatMap(Self.seconds)
    }

    /// Обычная ссылка на ролик, её и хранит блок. Shorts остаются Shorts, чтобы кадр был вертикальный.
    public var watchURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        if isShort {
            components.path = "/shorts/\(videoId)"
        } else {
            components.path = "/watch"
            components.queryItems = [URLQueryItem(name: "v", value: videoId)]
        }
        if let start, start > 0 {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: "\(start)s")]
        }
        return components.url!
    }

    /// Проигрыватель для встраивания. Домен без cookie: ролик в заметке не попадает в историю
    /// просмотров и рекомендации. `origin` нужен YouTube, чтобы проигрыватель знал, где он стоит.
    public func embedURL(origin: String, autoplay: Bool = true) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube-nocookie.com"
        components.path = "/embed/\(videoId)"
        var items = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1"),
            URLQueryItem(name: "origin", value: origin),
        ]
        if autoplay { items.append(URLQueryItem(name: "autoplay", value: "1")) }
        if let start, start > 0 { items.append(URLQueryItem(name: "start", value: "\(start)")) }
        components.queryItems = items
        return components.url!
    }

    /// Картинки-превью от самой большой к той, что есть у любого ролика.
    public var thumbnailURLs: [URL] {
        ["maxresdefault", "sddefault", "hqdefault"].map { URL(string: "https://i.ytimg.com/vi/\(videoId)/\($0).jpg")! }
    }

    /// Адрес для запроса названия и автора (oEmbed отвечает без ключа и без страницы согласия на cookie).
    public var oEmbedURL: URL {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: watchURL.absoluteString),
        ]
        return components.url!
    }

    /// Высота кадра на ширину.
    public var aspect: Double { isShort ? 16.0 / 9.0 : 9.0 / 16.0 }

    /// «1:30» для подписи «с 1:30».
    public var startText: String? {
        guard let start, start > 0 else { return nil }
        let hours = start / 3600
        let minutes = start / 60 % 60
        let seconds = start % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    static func isVideoId(_ text: String) -> Bool {
        text.count == 11 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// `90`, `90s`, `1m30s`, `1h2m3s` → секунды.
    static func seconds(_ text: String) -> Int? {
        if let plain = Int(text) { return plain >= 0 ? plain : nil }
        var total = 0
        var number = ""
        var sawUnit = false
        for character in text.lowercased() {
            if character.isASCII, character.isNumber {
                number.append(character)
                continue
            }
            guard let value = Int(number) else { return nil }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: return nil
            }
            number = ""
            sawUnit = true
        }
        guard sawUnit, number.isEmpty else { return nil }
        return total
    }
}
