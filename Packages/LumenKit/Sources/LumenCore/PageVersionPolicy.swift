import Foundation

/// Когда запоминать версию страницы и какие старые версии убирать.
/// Свежие версии хранятся все, старые прореживаются: за неделю одна в час, дальше одна в день.
public enum PageVersionPolicy {
    /// Новая версия не чаще, чем раз в десять минут правки.
    public static let interval: TimeInterval = 10 * 60
    /// Сколько версий у одной страницы самое большее.
    public static let maxCount = 100
    /// Версии старше этого убираются.
    public static let maxAge: TimeInterval = 90 * 86_400

    /// Пора ли запомнить новую версию, если прошлая была `last`.
    public static func isDue(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Какие версии убрать. `dates` в любом порядке, ответ: их места в этом массиве.
    public static func toDelete(_ dates: [Date], now: Date) -> Set<Int> {
        let order = dates.indices.sorted { dates[$0] > dates[$1] }
        var keep: [Int] = []
        var buckets = Set<String>()
        for index in order {
            let age = now.timeIntervalSince(dates[index])
            if age > maxAge { continue }
            if age <= 86_400 {
                keep.append(index)
                continue
            }
            // Старше суток: одна версия на час, старше недели одна на день (самая поздняя).
            let size: TimeInterval = age <= 7 * 86_400 ? 3_600 : 86_400
            let bucket = "\(Int(size)):\(Int(floor(dates[index].timeIntervalSince1970 / size)))"
            if buckets.insert(bucket).inserted {
                keep.append(index)
            }
        }
        let kept = Set(keep.prefix(maxCount))
        return Set(dates.indices).subtracting(kept)
    }

    /// Блоки, какими их сравнивают с прошлой версией: без времени правки.
    public static func normalized(_ blocks: [Block]) -> [Block] {
        blocks
            .map { block in
                var block = block
                block.createdAt = Date(timeIntervalSince1970: 0)
                block.updatedAt = Date(timeIntervalSince1970: 0)
                return block
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
