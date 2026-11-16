import CoreImage
import ImageIO
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Цвет обложки открытой заметки. Окно берёт его себе (фон, акцент), если в Настройках
/// включено «Окно в цвет обложки». Цвет задаёт заметка в активной панели, уходя, она его снимает.
@MainActor
@Observable
final class CoverTint {
    static let shared = CoverTint()
    /// Ключ настройки в UserDefaults. По умолчанию включено.
    static let enabledKey = "appearance.coverTint"

    private(set) var color: Color?
    @ObservationIgnored private var owner: UUID?

    /// Заметка `pageId` показана: окно красится в `color` (`nil`: у заметки нет обложки).
    func show(_ color: Color?, for pageId: UUID) {
        owner = pageId
        guard self.color != color else { return }
        withAnimation(LumenMotion.gentle) { self.color = color }
    }

    /// Заметка закрыта или ушла из активной панели. Чужой цвет не трогаем: его уже поставила
    /// заметка, открытая следом.
    func clear(for pageId: UUID) {
        guard owner == pageId else { return }
        owner = nil
        guard color != nil else { return }
        withAnimation(LumenMotion.gentle) { color = nil }
    }
}

/// Главный цвет обложки. У картинки это её средний цвет, он считается в фоне один раз на файл.
enum CoverColor {
    @MainActor private static var cache: [String: Color] = [:]

    @MainActor
    static func color(of cover: PageCover, theme: Theme, attachments: AttachmentStore) async -> Color? {
        switch cover {
        case .gradient(let index):
            let colors = theme.vividCard(index).colors
            guard let first = colors.first else { return nil }
            return colors.count > 1 ? first.mix(with: colors[1], by: 0.5) : first
        case .wallpaper(let wallpaper):
            return WallpaperPalette.palette(wallpaper.palette).mainColor
        case .image(let name):
            if let cached = cache[name] { return cached }
            let url = attachments.url(for: name)
            guard let rgb = await Task.detached(operation: { CoverColor.averageColor(url: url) }).value else { return nil }
            let color = Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
            cache[name] = color
            return color
        }
    }

    /// Средний цвет картинки: её крошечная копия, усреднённая Core Image.
    nonisolated static func averageColor(url: URL) -> (red: Double, green: Double, blue: Double)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let input = CIImage(cgImage: thumbnail)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}
