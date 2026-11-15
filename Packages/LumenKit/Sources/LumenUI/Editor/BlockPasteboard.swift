import Foundation
import LumenCore
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Блоки в буфере обмена. Внутри Lumen вставляются целиком (тип, цвет, вложенность, картинки),
/// в другие программы попадает их текст в Markdown.
@MainActor
enum BlockPasteboard {
    static let type = "app.lumen.blocks"
    /// Синхронные блоки, которые вырезали (а не скопировали): при вставке они переезжают
    /// оригиналом, а не становятся копией удалённого блока.
    static var cutSyncedIds: Set<UUID> = []

    static func write(_ clipboard: BlockClipboard, text: String) {
        guard let data = try? JSONEncoder().encode(clipboard) else { return }
        cutSyncedIds = []
        #if canImport(UIKit)
        UIPasteboard.general.setItems([[type: data, UTType.utf8PlainText.identifier: text]])
        #else
        let pasteboard = NSPasteboard.general
        let blocksType = NSPasteboard.PasteboardType(type)
        pasteboard.clearContents()
        pasteboard.declareTypes([blocksType, .string], owner: nil)
        pasteboard.setData(data, forType: blocksType)
        pasteboard.setString(text, forType: .string)
        #endif
    }

    /// Есть ли в буфере блоки Lumen. Содержимое при этом не читается.
    static var hasBlocks: Bool {
        #if canImport(UIKit)
        UIPasteboard.general.contains(pasteboardTypes: [type])
        #else
        NSPasteboard.general.availableType(from: [NSPasteboard.PasteboardType(type)]) != nil
        #endif
    }

    static func read() -> BlockClipboard? {
        #if canImport(UIKit)
        let data = UIPasteboard.general.data(forPasteboardType: type)
        #else
        let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(type))
        #endif
        return data.flatMap { try? JSONDecoder().decode(BlockClipboard.self, from: $0) }
    }
}
