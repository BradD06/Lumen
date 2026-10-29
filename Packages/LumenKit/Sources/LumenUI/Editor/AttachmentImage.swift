import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Картинка из вложений. Файл читается в фоне, чтобы не тормозить прокрутку.
struct AttachmentImage: View {
    let name: String
    let attachments: AttachmentStore
    var contentMode: ContentMode = .fit

    @State private var image: PlatformImage?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isMissing {
                Label("Картинка не найдена", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: name) {
            let url = attachments.url(for: name)
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            image = data.flatMap(PlatformImage.init(data:))
            isMissing = image == nil
        }
    }
}

/// Обложка страницы над названием: на всю ширину окна, без скруглений.
struct PageCoverView: View {
    let cover: PageCover
    let attachments: AttachmentStore
    /// Насколько зашло солнце на горной обложке, см. `LayeredWallpaper.sunset`.
    var sunset: Double = 0
    /// Высота полосы: в редакторе обложка большая, на плитке библиотеки маленькая.
    var height: CGFloat = 240

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            switch cover {
            case .wallpaper(let wallpaper):
                LayeredWallpaper(
                    palette: wallpaper.palette,
                    layers: wallpaper.layers,
                    hasSun: wallpaper.hasSun,
                    isFaceted: wallpaper.isFaceted,
                    seed: wallpaper.seed,
                    sunset: sunset
                )
            case .gradient(let index):
                LinearGradient(
                    colors: theme.vividCard(index).colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .image(let name):
                Color.clear.overlay {
                    AttachmentImage(name: name, attachments: attachments, contentMode: .fill)
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
