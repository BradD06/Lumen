/// Дробные индексы для порядка страниц и блоков.
///
/// Ключ это строка в base62, ключи сравниваются как строки (и в Swift, и в SQLite).
/// Между любыми двумя ключами всегда найдётся третий, поэтому вставка в середину
/// не требует перенумерации соседей и не конфликтует при синхронизации.
public enum SortKey {
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let base = digits.count
    private static let values: [Character: Int] = Dictionary(
        uniqueKeysWithValues: digits.enumerated().map { ($1, $0) }
    )

    /// Ключ строго между `lower` и `upper`. `nil` означает «без границы» (начало или конец списка).
    public static func between(_ lower: String?, _ upper: String?) -> String {
        if let lower, let upper, lower >= upper {
            // Повреждённый порядок: не падаем, а ставим элемент после нижней границы.
            return between(lower, nil)
        }
        let a = decode(lower ?? "")
        let b = upper.map(decode)
        return encode(midpoint(a, b))
    }

    /// `count` ключей подряд после `lower` и до `upper`.
    public static func sequence(count: Int, after lower: String? = nil, before upper: String? = nil) -> [String] {
        var keys: [String] = []
        var previous = lower
        for _ in 0..<max(count, 0) {
            let key = between(previous, upper)
            keys.append(key)
            previous = key
        }
        return keys
    }

    private static func midpoint(_ a: [Int], _ b: [Int]?) -> [Int] {
        if let b {
            // Общий префикс переносим как есть.
            var n = 0
            while n < b.count, (n < a.count ? a[n] : 0) == b[n] {
                n += 1
            }
            if n > 0 {
                return Array(b[..<n]) + midpoint(Array(a.dropFirst(n)), Array(b.dropFirst(n)))
            }
        }
        let digitA = a.first ?? 0
        let digitB = b?.first ?? base
        if digitB - digitA > 1 {
            return [(digitA + digitB) / 2]
        }
        // Соседние цифры.
        if let b, b.count > 1 {
            return [b[0]]
        }
        return [digitA] + midpoint(Array(a.dropFirst()), nil)
    }

    private static func decode(_ key: String) -> [Int] {
        key.map { values[$0] ?? 0 }
    }

    private static func encode(_ value: [Int]) -> String {
        String(value.map { digits[$0] })
    }
}
