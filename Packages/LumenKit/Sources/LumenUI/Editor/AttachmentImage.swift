import ImageIO
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

/// Картинка из вложений. Файл читается и раскодируется в фоне, чтобы не тормозить прокрутку.
struct AttachmentImage: View {
    let name: String
    let attachments: AttachmentStore
    var contentMode: ContentMode = .fit
    /// Длинная сторона в пикселях, до которой картинка уменьшается. Фото с телефона в полном
    /// размере занимает в памяти десятки мегабайт, а на экране столько точек не нужно.
    /// `nil`: как есть (картинка, открытая в читалке, где её увеличивают).
    let maxPixelSize: Int?

    @State private var image: PlatformImage?
    @State private var isMissing = false

    /// Хватает на всю ширину большого экрана Retina.
    nonisolated static let defaultMaxPixelSize = 3000

    /// Уже прочитанные картинки. Когда вид пересоздаётся (прокрутка, смена панели), картинка
    /// показывается сразу, без мигания пустого места и индикатора загрузки.
    private static let cache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.totalCostLimit = 200 * 1024 * 1024
        return cache
    }()

    init(
        name: String,
        attachments: AttachmentStore,
        contentMode: ContentMode = .fit,
        maxPixelSize: Int? = AttachmentImage.defaultMaxPixelSize
    ) {
        self.name = name
        self.attachments = attachments
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
        _image = State(initialValue: Self.cache.object(forKey: Self.cacheKey(attachments.url(for: name), maxPixelSize)))
    }

    private static func cacheKey(_ url: URL, _ maxPixelSize: Int?) -> NSString {
        "\(url.path)#\(maxPixelSize ?? 0)" as NSString
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
            let key = Self.cacheKey(url, maxPixelSize)
            if let cached = Self.cache.object(forKey: key) {
                image = cached
                isMissing = false
                return
            }
            let maxPixelSize = maxPixelSize
            if let maxPixelSize, let decoded = await Task.detached(operation: { DecodedImage(url: url, maxPixelSize: maxPixelSize) }).value {
                let loaded = decoded.platformImage
                image = loaded
                isMissing = false
                Self.cache.setObject(loaded, forKey: key, cost: decoded.cost)
                return
            }
            // Без уменьшения или формат, который ImageIO не читает (например PDF): как раньше.
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            image = data.flatMap(PlatformImage.init(data:))
            isMissing = image == nil
            if let image, let data {
                Self.cache.setObject(image, forKey: key, cost: data.count)
            }
        }
    }
}

/// Картинка, уменьшенная и раскодированная в фоне: на главном потоке её остаётся только показать.
private struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage

    init?(url: URL, maxPixelSize: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cgImage = image
    }

    /// Сколько памяти занимает картинка: столько она весит в кэше.
    var cost: Int { cgImage.bytesPerRow * cgImage.height }

    @MainActor
    var platformImage: PlatformImage {
        #if canImport(UIKit)
        UIImage(cgImage: cgImage)
        #else
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
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
