import LumenCore
import SwiftUI
import UniformTypeIdentifiers

/// Значок и название папки.
struct FolderLabel: View {
    let folder: Folder

    var body: some View {
        Label {
            Text(folder.displayName)
                .lineLimit(1)
        } icon: {
            FolderGlyph(color: folder.color, icon: folder.icon)
        }
    }
}

/// Что переносится при перетаскивании страницы (например, между колонками доски).
struct PageDragItem: Codable, Transferable {
    let pageId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .lumenPage)
    }
}

extension UTType {
    static let lumenPage = UTType(exportedAs: "app.lumen.page")
}

/// Иконка и название страницы.
struct PageLabel: View {
    let page: Page

    var body: some View {
        Label {
            Text(page.displayTitle)
                .lineLimit(1)
        } icon: {
            if let icon = page.icon, !icon.isEmpty {
                Text(icon)
            } else {
                Image(systemName: "doc.text")
            }
        }
    }
}
