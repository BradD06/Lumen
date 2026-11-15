import Foundation

/// Комментарий к блоку: заметка на полях, вопрос к себе, «проверить». Лежит в самом блоке
/// (`BlockContent.comments`), поэтому переезжает, копируется и удаляется вместе с ним.
public struct BlockComment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var editedAt: Date?
    /// Решённый комментарий прячется, но не удаляется.
    public var isResolved: Bool

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date(), editedAt: Date? = nil, isResolved: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.isResolved = isResolved
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, editedAt, isResolved
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        isResolved = try container.decodeIfPresent(Bool.self, forKey: .isResolved) ?? false
    }
}

extension BlockContent {
    /// Нерешённые комментарии блока.
    public var openComments: [BlockComment] {
        (comments ?? []).filter { !$0.isResolved }
    }
}
