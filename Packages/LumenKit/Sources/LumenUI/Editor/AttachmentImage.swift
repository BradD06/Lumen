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

    /// Уже прочитанные картинки. Когда вид пересоздаётся (прокрутка, смена панели), картинка
    /// показывается сразу, без мигания пустого места и индикатора загрузки.
    private static let cache: NSCache<NSURL, PlatformImage> = {
        let cache = NSCache<NSURL, PlatformImage>()
        cache.totalCostLimit = 200 * 1024 * 1024
        return cache
    }()

    init(name: String, attachments: AttachmentStore, contentMode: ContentMode = .fit) {
        self.name = name
        self.attachments = attachments
        self.contentMode = contentMode
        _image = State(initialValue: Self.cache.object(forKey: attachments.url(for: name) as NSURL))
    }

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
            if let cached = Self.cache.object(forKey: url as NSURL) {
                image = cached
                isMissing = false
                return
            }
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            image = data.flatMap(PlatformImage.init(data:))
            isMissing = image == nil
            if let image, let data {
                Self.cache.setObject(image, forKey: url as NSURL, cost: data.count)
            }
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
