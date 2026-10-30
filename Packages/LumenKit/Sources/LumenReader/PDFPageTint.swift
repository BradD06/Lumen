import CoreGraphics
import Foundation
import PDFKit

/// Как перекрашивать страницы PDF под тему читалки.
public enum PDFPageTint: Hashable, Sendable {
    /// Как в файле.
    case original
    /// Тёмная страница `page` со светлым текстом цвета `ink`.
    case night(page: UInt32, ink: UInt32)
    /// Белое становится цветом бумаги, тёмный текст остаётся тёмным.
    case paper(UInt32)
}

/// Вид страниц PDF: перекраска и цвет листа вокруг них.
public struct PDFPageStyle: Hashable, Sendable {
    public var tint: PDFPageTint
    /// Цвет листа под страницами: им же закрашиваются скруглённые углы страниц.
    public var backdrop: UInt32

    public init(tint: PDFPageTint, backdrop: UInt32) {
        self.tint = tint
        self.backdrop = backdrop
    }

    public static let original = PDFPageStyle(tint: .original, backdrop: 0x21171F)

    var isNight: Bool {
        if case .night = tint { return true }
        return false
    }
}

extension ReaderAppearance.Palette {
    /// Те же темы для PDF. Текст PDF перекрасить нельзя, поэтому перекрашивается вся страница,
    /// а картинки на ней остаются цветными.
    public var pdfStyle: PDFPageStyle {
        switch self {
        case .night: PDFPageStyle(tint: .night(page: 0x3A2A40, ink: 0xF3E3DA), backdrop: 0x2B1E31)
        case .paper: PDFPageStyle(tint: .paper(0xF4EADB), backdrop: 0xE4D5C0)
        case .dawn: PDFPageStyle(tint: .paper(0xFBE6DA), backdrop: 0xEDCDBE)
        case .original: .original
        }
    }
}

/// Страница PDF, которая рисует себя в цветах темы: скруглённые углы, перекрашенные фон и текст,
/// а картинки поверх перекраски рисуются заново, как в файле.
final class TintedPDFPage: PDFPage {
    // PDFView рисует страницы в фоновых потоках, поэтому общее состояние под замком.
    private let lock = NSLock()
    private var currentStyle = PDFPageStyle.original
    private var cachedImageRects: [CGRect]?

    var style: PDFPageStyle {
        get { lock.withLock { currentStyle } }
        set { lock.withLock { currentStyle = newValue } }
    }

    /// Где на странице картинки. У сканов пусто: там картинка это вся страница.
    private var imageRects: [CGRect] {
        if let cached = lock.withLock({ cachedImageRects }) { return cached }
        var rects: [CGRect] = []
        if let pageRef {
            let found = PDFImageFinder.imageRects(in: pageRef)
            rects = PDFImageFinder.isScan(found, page: bounds(for: .mediaBox)) ? [] : found
        }
        lock.withLock { cachedImageRects = rects }
        return rects
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let style = self.style
        let rect = bounds(for: box)
        context.saveGState()
        defer { context.restoreGState() }

        // Углы вне скругления закрашены цветом листа, так страница выглядит мягкой карточкой.
        context.setFillColor(Self.cgColor(style.backdrop))
        context.fill(rect)
        let radius = min(rect.width, rect.height) * 0.025
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.setFillColor(Self.white)
        context.fill(rect)
        super.draw(with: box, to: context)

        switch style.tint {
        case .original:
            return
        case .night(let page, let ink):
            // Инверсия делает фон чёрным, а текст белым; «экран» поднимает чёрный до цвета страницы,
            // умножение окрашивает белый текст в тёплый светлый.
            fill(context, rect, Self.white, mode: .difference)
            fill(context, rect, Self.lift(page: page, ink: ink), mode: .screen)
            fill(context, rect, Self.cgColor(ink), mode: .multiply)
        case .paper(let paper):
            fill(context, rect, Self.cgColor(paper), mode: .multiply)
        }

        for imageRect in imageRects where imageRect.intersects(rect) {
            context.saveGState()
            context.clip(to: imageRect)
            context.setBlendMode(.normal)
            context.setFillColor(Self.white)
            context.fill(imageRect)
            super.draw(with: box, to: context)
            context.restoreGState()
        }
    }

    private func fill(_ context: CGContext, _ rect: CGRect, _ color: CGColor, mode: CGBlendMode) {
        context.setBlendMode(mode)
        context.setFillColor(color)
        context.fill(rect)
    }

    private static var white: CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) }

    static func cgColor(_ hex: UInt32) -> CGColor {
        let (red, green, blue) = channels(hex)
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// Цвет, который после умножения на `ink` даёт цвет страницы `page`.
    static func lift(page: UInt32, ink: UInt32) -> CGColor {
        let page = channels(page)
        let ink = channels(ink)
        func divide(_ value: CGFloat, _ by: CGFloat) -> CGFloat { by > 0 ? min(value / by, 1) : 0 }
        return CGColor(srgbRed: divide(page.0, ink.0), green: divide(page.1, ink.1), blue: divide(page.2, ink.2), alpha: 1)
    }

    static func channels(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }
}

/// Говорит документу создавать страницы, которые умеют перекрашиваться.
final class TintedPageFactory: NSObject, PDFDocumentDelegate {
    func classForPage() -> AnyClass {
        TintedPDFPage.self
    }
}

/// Находит картинки на странице PDF: проходит по командам рисования и запоминает,
/// куда матрица преобразования ставит каждую картинку.
enum PDFImageFinder {
    static func imageRects(in page: CGPDFPage) -> [CGRect] {
        let collector = Collector()
        let stream = CGPDFContentStreamCreateWithPage(page)
        collector.scan(stream)
        CGPDFContentStreamRelease(stream)
        return collector.rects
    }

    /// Скан: картинки закрывают почти всю страницу. Такую страницу перекрашивают целиком.
    static func isScan(_ rects: [CGRect], page: CGRect) -> Bool {
        let pageArea = page.width * page.height
        guard pageArea > 0 else { return false }
        let covered = rects.reduce(CGFloat(0)) { sum, rect in
            let visible = rect.intersection(page)
            return visible.isNull ? sum : sum + visible.width * visible.height
        }
        return covered / pageArea > 0.7
    }

    private final class Collector {
        var ctm = CGAffineTransform.identity
        var stack: [CGAffineTransform] = []
        var rects: [CGRect] = []
        var depth = 0

        static func from(_ info: UnsafeMutableRawPointer?) -> Collector? {
            info.map { Unmanaged<Collector>.fromOpaque($0).takeUnretainedValue() }
        }

        func scan(_ stream: CGPDFContentStreamRef) {
            guard let table = CGPDFOperatorTableCreate() else { return }
            defer { CGPDFOperatorTableRelease(table) }
            CGPDFOperatorTableSetCallback(table, "q") { _, info in
                Collector.from(info)?.push()
            }
            CGPDFOperatorTableSetCallback(table, "Q") { _, info in
                Collector.from(info)?.pop()
            }
            CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
                guard let collector = Collector.from(info) else { return }
                var values = [CGPDFReal](repeating: 0, count: 6)
                for index in (0..<6).reversed() {
                    guard CGPDFScannerPopNumber(scanner, &values[index]) else { return }
                }
                collector.concat(values)
            }
            CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
                Collector.from(info)?.drawObject(scanner)
            }
            // Встроенная прямо в страницу картинка.
            CGPDFOperatorTableSetCallback(table, "BI") { _, info in
                Collector.from(info)?.addImage()
            }
            let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(self).toOpaque())
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
        }

        func push() {
            stack.append(ctm)
        }

        func pop() {
            if let last = stack.popLast() { ctm = last }
        }

        func concat(_ values: [CGPDFReal]) {
            guard values.count == 6 else { return }
            let matrix = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            ctm = matrix.concatenating(ctm)
        }

        /// Картинка всегда рисуется в единичный квадрат, растянутый текущей матрицей.
        func addImage() {
            let rect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(ctm)
            if rect.width > 1, rect.height > 1 { rects.append(rect) }
        }

        func drawObject(_ scanner: CGPDFScannerRef) {
            var namePointer: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &namePointer), let name = namePointer else { return }
            let content = CGPDFScannerGetContentStream(scanner)
            guard let object = CGPDFContentStreamGetResource(content, "XObject", name) else { return }
            var streamPointer: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &streamPointer),
                  let stream = streamPointer,
                  let dictionary = CGPDFStreamGetDictionary(stream) else { return }
            var subtypePointer: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypePointer), let subtype = subtypePointer else { return }
            switch String(cString: subtype) {
            case "Image":
                addImage()
            case "Form":
                scanForm(stream, dictionary: dictionary, parent: content)
            default:
                break
            }
        }

        /// Форма это вложенный кусок страницы со своей матрицей: картинки бывают и внутри.
        private func scanForm(_ stream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef, parent: CGPDFContentStreamRef) {
            guard depth < 4 else { return }
            var resourcesPointer: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resourcesPointer), let resources = resourcesPointer else { return }
            push()
            defer { pop() }
            var matrixPointer: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(dictionary, "Matrix", &matrixPointer), let matrix = matrixPointer, CGPDFArrayGetCount(matrix) == 6 {
                var values = [CGPDFReal](repeating: 0, count: 6)
                for index in 0..<6 {
                    _ = CGPDFArrayGetNumber(matrix, index, &values[index])
                }
                concat(values)
            }
            let child = CGPDFContentStreamCreateWithStream(stream, resources, parent)
            depth += 1
            scan(child)
            depth -= 1
            CGPDFContentStreamRelease(child)
        }
    }
}
