import Foundation
import LumenCore

/// Где стоят заметки у книги: рядом или под ней, слева или справа, и сколько места у них.
/// Помнится для каждой книги, а новая книга берёт то, что выбрали последним.
enum ReaderLayoutStore {
    static let lastKey = "reader.layout"
    /// Ширина заметок из прежних версий: с неё начинают, пока раскладку ни разу не меняли.
    static let legacyFractionKey = "reader.notesFraction"

    static func key(for sourceId: UUID) -> String {
        "reader.layout.\(sourceId.uuidString)"
    }

    static func load(_ sourceId: UUID, defaults: UserDefaults = .standard) -> PaneArrangement {
        if let saved = decode(defaults.data(forKey: key(for: sourceId))) { return saved }
        if let last = decode(defaults.data(forKey: lastKey)) { return last }
        var arrangement = PaneArrangement()
        if let old = defaults.object(forKey: legacyFractionKey) as? Double {
            arrangement.setFraction(old, for: .sideBySide)
        }
        return arrangement
    }

    static func save(_ arrangement: PaneArrangement, for sourceId: UUID, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(arrangement) else { return }
        defaults.set(data, forKey: key(for: sourceId))
        defaults.set(data, forKey: lastKey)
    }

    private static func decode(_ data: Data?) -> PaneArrangement? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PaneArrangement.self, from: data)
    }
}
