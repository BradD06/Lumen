import Foundation

/// Ссылка `lumen://` на страницу, книгу, выписку или место в книге. Такую ссылку можно
/// скопировать и вставить куда угодно (Заметки, Напоминания, Telegram): нажатие открывает Lumen там.
///
/// - `lumen://page/<id>` страница;
/// - `lumen://source/<id>` книга там, где остановились;
/// - `lumen://source/<id>/highlight/<id>` книга на выделении, из которого сделана выписка;
/// - `lumen://source/<id>/place?s=3&p=0.42&o=1200` книга на месте: глава или страница PDF,
///   насколько она прокручена, первый символ вверху экрана, у PDF ещё и точка страницы (`x`, `y`).
public enum LumenLink: Hashable, Sendable {
    case page(UUID)
    case source(UUID)
    case highlight(sourceId: UUID, highlightId: UUID)
    case place(sourceId: UUID, locator: SourceLocator)

    public static let scheme = "lumen"

    /// Книга, на которую ведёт ссылка. У ссылки на страницу её нет.
    public var sourceId: UUID? {
        switch self {
        case .page: nil
        case .source(let id), .highlight(let id, _), .place(let id, _): id
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .page(let id):
            components.host = "page"
            components.path = "/\(id.uuidString)"
        case .source(let id):
            components.host = "source"
            components.path = "/\(id.uuidString)"
        case .highlight(let sourceId, let highlightId):
            components.host = "source"
            components.path = "/\(sourceId.uuidString)/highlight/\(highlightId.uuidString)"
        case .place(let sourceId, let locator):
            components.host = "source"
            components.path = "/\(sourceId.uuidString)/place"
            components.queryItems = Self.queryItems(for: locator)
        }
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let first = parts.first, let id = UUID(uuidString: first) else { return nil }

        switch (host, parts.count) {
        case ("page", 1):
            self = .page(id)
        case ("source", 1):
            self = .source(id)
        case ("source", 3) where parts[1] == "highlight":
            guard let highlightId = UUID(uuidString: parts[2]) else { return nil }
            self = .highlight(sourceId: id, highlightId: highlightId)
        case ("source", 2) where parts[1] == "place":
            let items = components.queryItems ?? []
            func value(_ name: String) -> Double? {
                items.first { $0.name == name }?.value.flatMap(Double.init)
            }
            // Без страницы или главы место непонятно: тогда книга просто откроется там, где остановились.
            guard let section = value("s"), section.isFinite else {
                self = .source(id)
                return
            }
            var point: LocatorPoint?
            if let x = value("x"), let y = value("y"), x.isFinite, y.isFinite {
                point = LocatorPoint(x: x, y: y)
            }
            let offset = value("o").flatMap { $0.isFinite ? Int(min(max($0, 0), 100_000_000)) : nil }
            let locator = SourceLocator(
                section: Int(min(max(section, 0), 1_000_000)),
                progression: value("p").flatMap { $0.isFinite ? $0 : nil } ?? 0,
                textOffset: offset,
                point: point
            )
            self = .place(sourceId: id, locator: locator)
        default:
            return nil
        }
    }

    /// В ссылку попадает только само место. Текст выделения и прямоугольники в ней не нужны:
    /// ссылка на выделение ведёт на само выделение по его id.
    private static func queryItems(for locator: SourceLocator) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "s", value: String(locator.section))]
        if locator.progression > 0 {
            items.append(URLQueryItem(name: "p", value: format(locator.progression)))
        }
        if let offset = locator.textOffset {
            items.append(URLQueryItem(name: "o", value: String(offset)))
        }
        if let point = locator.point {
            items.append(URLQueryItem(name: "x", value: format(point.x)))
            items.append(URLQueryItem(name: "y", value: format(point.y)))
        }
        return items
    }

    /// Не больше четырёх знаков после запятой, чтобы ссылка оставалась короткой.
    private static func format(_ value: Double) -> String {
        let rounded = (value * 10_000).rounded() / 10_000
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(rounded)
    }
}

extension ExcerptReference {
    /// Куда ведёт выписка: на выделение, а у ссылки на место на само место.
    public var link: LumenLink {
        if let highlightId { return .highlight(sourceId: sourceId, highlightId: highlightId) }
        if let locator { return .place(sourceId: sourceId, locator: locator) }
        return .source(sourceId)
    }
}
