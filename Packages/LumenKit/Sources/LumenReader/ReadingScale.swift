import Foundation

/// Сколько прочитано в книге из нескольких HTML-файлов. Файлы в EPUB бывают любого размера:
/// обложка в одну строку, глава на сорок страниц. Поэтому доля считается по объёму текста
/// в каждом файле, а не по номеру файла.
public struct ReadingScale: Hashable, Sendable {
    /// Вес каждой главы: сколько в ней текста (картинка считается за кусок текста).
    public let weights: [Int]
    private let starts: [Int]
    private let total: Int

    public init(weights: [Int]) {
        let weights = weights.map { max($0, 1) }
        var starts: [Int] = []
        var sum = 0
        for weight in weights {
            starts.append(sum)
            sum += weight
        }
        self.weights = weights
        self.starts = starts
        self.total = sum
    }

    /// Все главы весят одинаково: пока вес файлов не посчитан.
    public static func even(_ count: Int) -> ReadingScale {
        ReadingScale(weights: Array(repeating: 1, count: max(count, 1)))
    }

    /// Доля книги, от 0 до 1, для места `progression` (0...1) внутри главы `section`.
    public func progress(section: Int, progression: Double) -> Double {
        guard total > 0, !weights.isEmpty else { return 0 }
        let section = min(max(section, 0), weights.count - 1)
        let within = Double(weights[section]) * min(max(progression, 0), 1)
        return min((Double(starts[section]) + within) / Double(total), 1)
    }

    /// Вес главы для текста её HTML: видимые буквы плюс картинки. Теги, стили и скрипты не считаются.
    public static func weight(html: String) -> Int {
        var text = html
        if let body = text.range(of: "<body", options: .caseInsensitive) {
            text = String(text[body.lowerBound...])
        }
        let images = text.components(separatedBy: "<img").count - 1
            + text.components(separatedBy: "<image").count - 1
            + text.components(separatedBy: "<svg").count - 1
        for pattern in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<[^>]*>"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "&#?[A-Za-z0-9]+;", with: "x", options: .regularExpression)
        let letters = text.unicodeScalars.reduce(0) { $0 + (CharacterSet.whitespacesAndNewlines.contains($1) ? 0 : 1) }
        return max(letters + images * imageWeight, 1)
    }

    /// Картинка весит как треть страницы текста: страница с одной картинкой тоже двигает прогресс.
    static let imageWeight = 600

    /// Веса глав готового документа. Файлы читаются с диска, поэтому звать не на главном потоке.
    public static func weights(of prepared: PreparedDocument) -> [Int] {
        prepared.document.sections.indices.map { index in
            guard let url = prepared.url(for: index),
                  let data = try? Data(contentsOf: url) else { return 1 }
            return weight(html: String(decoding: data, as: UTF8.self))
        }
    }
}

extension TocEntry {
    /// Главы для полосы внизу читалки: верхний уровень оглавления. Если там один пункт
    /// (часто это название книги, внутри которого всё остальное), берётся уровень ниже.
    public static func chapters(in toc: [TocEntry]) -> [TocEntry] {
        guard let top = toc.map(\.level).min() else { return [] }
        let first = toc.filter { $0.level == top }
        if first.count == 1 {
            let next = toc.filter { $0.level == top + 1 }
            if next.count > 1 { return next }
        }
        return first
    }
}
