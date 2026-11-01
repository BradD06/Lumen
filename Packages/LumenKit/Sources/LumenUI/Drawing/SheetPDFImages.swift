import CoreImage
import LumenCore
import LumenStorage
import PDFKit
import SwiftUI

/// Картинки страниц PDF для листов тетради. Документы открываются один раз, готовые картинки
/// хранятся в кэше по ширине в пикселях (с шагом, чтобы не перерисовывать на каждый сдвиг
/// разделителя). В тёмной бумаге страница тоже тёмная: белое становится тёмным, цвета остаются,
/// иначе светлые чернила тёмной темы были бы не видны на белой странице.
@MainActor
enum SheetPDFImages {
    private static var documents: [String: PDFDocument] = [:]
    private static let images: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// Шаг ширины картинки в пикселях.
    private static let widthStep = 256
    private static let maxWidth = 2304

    static func document(_ attachment: String, attachments: AttachmentStore) -> PDFDocument? {
        if let document = documents[attachment] { return document }
        guard let document = PDFDocument(url: attachments.url(for: attachment)) else { return nil }
        documents[attachment] = document
        return document
    }

    /// Размер страницы с учётом поворота, в пунктах PDF.
    static func pageSize(_ background: SheetBackground, attachments: AttachmentStore) -> CGSize? {
        guard let page = document(background.attachment, attachments: attachments)?.page(at: background.page) else { return nil }
        return size(of: page)
    }

    static func size(of page: PDFPage) -> CGSize {
        let box = page.bounds(for: .mediaBox).size
        return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    /// Страница шириной не меньше `pixelWidth` пикселей.
    static func image(
        _ background: SheetBackground,
        attachments: AttachmentStore,
        pixelWidth: CGFloat,
        dark: Bool
    ) -> CGImage? {
        let width = min(max(Int((pixelWidth / CGFloat(widthStep)).rounded(.up)) * widthStep, widthStep), maxWidth)
        let key = "\(background.attachment)#\(background.page)@\(width)\(dark ? "d" : "")" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let page = document(background.attachment, attachments: attachments)?.page(at: background.page) else { return nil }
        let size = size(of: page)
        guard size.width > 0, size.height > 0 else { return nil }
        let target = CGSize(width: CGFloat(width), height: (CGFloat(width) * size.height / size.width).rounded())
        guard var image = cgImage(page.thumbnail(of: target, for: .mediaBox)) else { return nil }
        if dark, let darkened = darkened(image) {
            image = darkened
        }
        images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    /// Белое в тёмное с теми же оттенками: негатив и поворот цвета на пол-круга, как ночной режим читалки.
    private static func darkened(_ image: CGImage) -> CGImage? {
        var output = CIImage(cgImage: image)
        output = output.applyingFilter("CIColorInvert")
        output = output.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: Double.pi])
        return context.createCGImage(output, from: output.extent)
    }

    #if canImport(UIKit)
    private static func cgImage(_ image: UIImage) -> CGImage? { image.cgImage }
    #else
    private static func cgImage(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    #endif
}

/// Страница PDF на листе тетради: целиком, по центру, под чернилами.
struct SheetPDFPage: View {
    let background: SheetBackground
    let attachments: AttachmentStore
    let dark: Bool

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let pageSize = SheetPDFImages.pageSize(background, attachments: attachments)
            let frame = pageSize.map { NotebookSheets.fit(pageSize: $0, in: bounds) } ?? bounds
            if let image = SheetPDFImages.image(
                background,
                attachments: attachments,
                pixelWidth: frame.width * displayScale,
                dark: dark
            ) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            } else {
                Label("Страница PDF не найдена", systemImage: "doc.questionmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: bounds.width, height: bounds.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Выбор страниц

/// PDF, из которого кладут страницы на листы тетради.
struct PDFImportRequest: Identifiable {
    let id = UUID()
    let document: PDFDocument
    let title: String
}

/// Какие страницы PDF положить на листы: с какой по какую. Каждая страница становится листом.
struct PDFImportSheet: View {
    let request: PDFImportRequest
    /// Сколько листов ещё влезает в тетрадь.
    let room: Int
    var onInsert: (ClosedRange<Int>) -> Void
    var onCancel: () -> Void

    @State private var first = 1
    @State private var last = 1

    private var pageCount: Int { max(request.document.pageCount, 1) }
    private var chosen: Int { max(last - first + 1, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Страницы на листы")
                    .font(.title3.weight(.bold))
                Text("«\(request.title)», \(pageCount) стр.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Text("С")
                pageField($first, range: 1...last)
                Text("по")
                pageField($last, range: first...pageCount)
                Spacer(minLength: 0)
                Button("Все") {
                    first = 1
                    last = pageCount
                }
            }
            Text(note)
                .font(.footnote)
                .foregroundStyle(chosen > room ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Отмена", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Вставить") {
                    onInsert((first - 1)...(last - 1))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == 0 || room == 0)
            }
        }
        .padding(22)
        .frame(minWidth: 340, idealWidth: 380)
        .onAppear {
            first = 1
            // Большую книгу целиком не вставляем: сначала предлагаем первые страницы.
            last = min(pageCount, min(room, 30))
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    private var note: String {
        if room == 0 { return "В тетради уже \(NotebookLayout.maxSheets) листов, больше не поместится." }
        if chosen > room { return "Поместится только \(room): в тетради не больше \(NotebookLayout.maxSheets) листов." }
        return "Каждая страница станет отдельным листом, писать можно прямо поверх неё."
    }

    private func pageField(_ value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            TextField("", value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 64)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
    }
}
