import LumenCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Кладёт ссылку `lumen://` в буфер обмена и как ссылку, и как текст: Заметки и почта вставят
/// её ссылкой, мессенджеры текстом. Нажатие на неё в любом приложении откроет Lumen на этом месте.
@MainActor
func copyLink(_ link: LumenLink) {
    let url = link.url
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([url as NSURL])
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
    #else
    UIPasteboard.general.items = [[
        UTType.url.identifier: url,
        UTType.utf8PlainText.identifier: url.absoluteString,
    ]]
    #endif
}
