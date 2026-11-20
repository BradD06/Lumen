import CoreGraphics
import Foundation
import LumenCore
import PencilKit
import Vision

/// Читает почерк на листах тетради (Vision, прямо на устройстве), чтобы тетрадь находилась
/// в поиске по написанным от руки словам. Читает только листы, где чернила поменялись:
/// результат помнится по содержимому листа, поэтому переставленный лист заново не читается.
@MainActor
final class HandwritingReader {
    /// Прочитанный текст по отпечатку чернил листа (в координатах самого листа).
    private var known: [Int: String] = [:]
    private var isFirstPass = true

    /// Тексты листов после чтения или `nil`, если ничего не поменялось.
    func read(drawing: PKDrawing, content: BlockContent) async -> [String?]? {
        let count = NotebookLayout.sheetCount(of: content)
        var texts = Array(NotebookSheets.padded(content.sheetTexts, to: count).prefix(count))
        let original = NotebookSheets.normalized(texts)
        for sheet in 0..<count {
            if Task.isCancelled { return nil }
            let strokes = NotebookEditing.strokes(onSheet: sheet, sheets: count, in: drawing)
            guard !strokes.isEmpty else {
                texts[sheet] = nil
                continue
            }
            let local = Self.onSheet(strokes, sheet: sheet)
            let key = local.dataRepresentation().hashValue
            if let text = known[key] {
                texts[sheet] = text
                continue
            }
            // Только что открытая тетрадь: то, что уже прочитано раньше, не читаем заново.
            if isFirstPass, let stored = texts[sheet] {
                known[key] = stored
                continue
            }
            guard let image = Self.image(of: local) else { continue }
            let text = await Self.recognize(image)
            known[key] = text
            if Task.isCancelled { return nil }
            texts[sheet] = text
        }
        isFirstPass = false
        let result = NotebookSheets.normalized(texts)
        return result == original ? nil : result
    }

    /// Штрихи листа в его собственных координатах.
    static func onSheet(_ strokes: [PKStroke], sheet: Int) -> PKDrawing {
        let lift = CGAffineTransform(translationX: 0, y: -NotebookLayout.sheetRect(sheet).minY)
        return PKDrawing(strokes: strokes.map { stroke in
            var stroke = stroke
            stroke.transform = stroke.transform.concatenating(lift)
            return stroke
        })
    }

    /// Лист чёрными чернилами на белом: так Vision читает лучше всего.
    static func image(of drawing: PKDrawing) -> SendableImage? {
        let size = CGSize(width: NotebookLayout.sheetWidth, height: NotebookLayout.sheetHeight)
        let scale: CGFloat = 1.5
        guard let ink = DrawingSupport.image(of: drawing, in: CGRect(origin: .zero, size: size), scale: scale, isDark: false),
              let cgInk = cgImage(of: ink) else { return nil }
        let width = cgInk.width
        let height = cgInk.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(cgInk, in: bounds)
        return context.makeImage().map(SendableImage.init)
    }

    private static func cgImage(of image: PlatformImage) -> CGImage? {
        #if canImport(UIKit)
        image.cgImage
        #else
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    /// Строки, которые Vision нашёл на картинке, по одной на строку. Русский и английский.
    nonisolated static func recognize(_ image: SendableImage) async -> String {
        await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let wanted = ["ru-RU", "en-US"]
            if let supported = try? request.supportedRecognitionLanguages() {
                let languages = wanted.filter(supported.contains)
                if !languages.isEmpty { request.recognitionLanguages = languages }
            }
            let handler = VNImageRequestHandler(cgImage: image.image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return ""
            }
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

/// Картинка листа для чтения в фоне. CGImage не меняется после создания.
struct SendableImage: @unchecked Sendable {
    let image: CGImage
}
