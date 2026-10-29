import Foundation
import ImageIO
import LumenCore
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Что удалось узнать о файле при добавлении: название, автор и картинка обложки.
public struct ImportedMetadata: Sendable {
    public var title: String?
    public var author: String?
    /// Обложка в JPEG, уже уменьшенная.
    public var cover: Data?
}

public enum SourceMetadata {
    /// Ширина обложки в пикселях: плитке библиотеки хватает с запасом для Retina.
    static let coverPixelSize = 600

    /// Читает метаданные и готовит обложку. Для книг заодно переводит их в HTML,
    /// так что первое открытие уже не ждёт (`cacheKey` тот же, что потом у читалки).
    public static func read(file: URL, format: SourceFormat, cacheKey: String) async -> ImportedMetadata {
        var metadata = ImportedMetadata()
        if DocumentConverter.canConvert(format),
           let prepared = try? await DocumentConverter.prepare(file: file, format: format, cacheKey: cacheKey) {
            metadata.title = prepared.document.title
            metadata.author = prepared.document.author
            if let cover = prepared.coverURL {
                metadata.cover = jpegThumbnail(of: cover)
            }
        } else if format == .pdf {
            metadata = pdfMetadata(file)
        }
        if metadata.cover == nil {
            metadata.cover = await systemThumbnail(of: file)
        }
        return metadata
    }

    static func pdfMetadata(_ file: URL) -> ImportedMetadata {
        var metadata = ImportedMetadata()
        guard let document = PDFDocument(url: file) else { return metadata }
        let attributes = document.documentAttributes ?? [:]
        metadata.title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?.trimmed.nilIfEmpty
        metadata.author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?.trimmed.nilIfEmpty
        if let page = document.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            let scale = Double(coverPixelSize) / max(bounds.width, 1)
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            #if os(macOS)
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #else
            let cgImage = image.cgImage
            #endif
            metadata.cover = cgImage.flatMap(jpeg)
        }
        return metadata
    }

    /// Миниатюра от системы: так же, как её показывает Finder или «Файлы».
    static func systemThumbnail(of file: URL) async -> Data? {
        let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: CGSize(width: 300, height: 420),
            scale: 2,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        return jpeg(representation.cgImage)
    }

    static func jpegThumbnail(of url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: coverPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpeg(image)
    }

    static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
