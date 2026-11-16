import Foundation
import GRDB
import LumenCore

extension AppDatabase {
    /// Вещь удалили навсегда: её старая кнопка с доски связей тоже уходит.
    static func removeOrphanBoardPins(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM boardPin
            WHERE (kind = 'page' AND id NOT IN (SELECT id FROM page))
                OR (kind = 'source' AND id NOT IN (SELECT id FROM source))
                OR (kind = 'folder' AND id NOT IN (SELECT id FROM folder))
            """)
    }
}
