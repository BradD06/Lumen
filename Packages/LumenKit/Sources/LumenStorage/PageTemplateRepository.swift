import Foundation
import GRDB
import LumenCore

extension AppDatabase {
    /// Свои шаблоны по названию.
    public func pageTemplates() async throws -> [PageTemplate] {
        try await reader.read { db in
            try PageTemplate.order(Column("title").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
        }
    }

    /// Новый шаблон из блоков страницы.
    @discardableResult
    public func savePageTemplate(title: String, icon: String?, blocks: BlockClipboard) async throws -> PageTemplate {
        try await writer.write { db in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let template = PageTemplate(title: trimmed.isEmpty ? "Без названия" : trimmed, icon: icon, blocks: blocks)
            try template.insert(db)
            return template
        }
    }

    public func deletePageTemplate(_ id: UUID) async throws {
        try await writer.write { db in
            _ = try PageTemplate.deleteOne(db, key: id)
        }
    }
}
