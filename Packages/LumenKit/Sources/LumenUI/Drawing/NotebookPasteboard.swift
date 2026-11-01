import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Картинка из буфера обмена: скриншот, скопированная картинка или файл картинки из Finder.
enum NotebookPasteboard {
    struct Image {
        var data: Data
        var fileExtension: String
    }

    /// Есть ли в буфере картинка. Быстрая проверка, без чтения данных.
    @MainActor
    static var hasImage: Bool {
        #if canImport(UIKit)
        UIPasteboard.general.hasImages
        #else
        let board = NSPasteboard.general
        if board.availableType(from: [.png, .tiff]) != nil { return true }
        return imageFileURL(on: board) != nil
        #endif
    }

    @MainActor
    static func image() -> Image? {
        #if canImport(UIKit)
        let board = UIPasteboard.general
        if let data = board.data(forPasteboardType: UTType.png.identifier) {
            return Image(data: data, fileExtension: "png")
        }
        if let data = board.data(forPasteboardType: UTType.jpeg.identifier) {
            return Image(data: data, fileExtension: "jpg")
        }
        if let data = board.image?.pngData() {
            return Image(data: data, fileExtension: "png")
        }
        return nil
        #else
        let board = NSPasteboard.general
        // Файл картинки, скопированный в Finder: берём сам файл, а не его значок.
        if let url = imageFileURL(on: board), let data = try? Data(contentsOf: url) {
            return Image(data: data, fileExtension: url.pathExtension.lowercased())
        }
        if let data = board.data(forType: .png) {
            return Image(data: data, fileExtension: "png")
        }
        // Скриншоты и картинки из многих программ лежат в буфере как TIFF: храним их в PNG, он меньше.
        if let tiff = board.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return Image(data: png, fileExtension: "png")
        }
        return nil
        #endif
    }

    #if os(macOS)
    private static func imageFileURL(on board: NSPasteboard) -> URL? {
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { url in
            UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        }
    }
    #endif
}
