import Foundation
import LumenCore
import LumenStorage
import PencilKit

#if canImport(UIKit)
import UIKit
private typealias ExportFont = UIFont
private typealias ExportColor = UIColor
#else
import AppKit
private typealias ExportFont = NSFont
private typealias ExportColor = NSColor
#endif

/// Страница в PDF для печати и отправки: белый лист A4, тёмный текст, страницы режутся сами.
/// Текст собирается в `NSAttributedString` и раскладывается по листам системной вёрсткой текста,
/// поэтому PDF получается с настоящим текстом: его можно искать и копировать.
@MainActor
enum PagePDFRenderer {
    /// A4 в пунктах.
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 56

    static var contentSize: CGSize {
        CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
    }

    static func pdf(for export: PageExport, attachments: AttachmentStore) -> Data {
        pdf(from: attributedText(for: export, attachments: attachments), title: export.page.displayTitle)
    }

    // MARK: Текст

    private static let ink = ExportColor(white: 0.12, alpha: 1)
    private static let secondary = ExportColor(white: 0.45, alpha: 1)
    private static let accent = ExportColor(red: 0.85, green: 0.42, blue: 0.24, alpha: 1)
    private static let codeBackground = ExportColor(white: 0.94, alpha: 1)
    private static let calloutBackground = ExportColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)
    private static let bodySize: CGFloat = 11.5
    private static let listIndent: CGFloat = 20

    static func attributedText(for export: PageExport, attachments: AttachmentStore) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let icon = export.page.icon.flatMap { $0.unicodeScalars.first?.isASCII == false ? "\($0) " : nil } ?? ""
        text.append(NSAttributedString(
            string: icon + export.page.displayTitle + "\n",
            attributes: [
                .font: font(size: 24, bold: true),
                .foregroundColor: ink,
                .paragraphStyle: paragraph(after: 14),
            ]
        ))

        for item in export.items {
            let block = item.block
            let indent = CGFloat(item.listDepth) * listIndent
            switch block.type {
            case .paragraph:
                guard !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                text.append(runs(block.content.runs, size: bodySize))
                text.append(newline(paragraph(indent: indent)))
            case .heading1, .heading2, .heading3:
                let size: CGFloat = block.type == .heading1 ? 19 : block.type == .heading2 ? 15.5 : 13
                text.append(runs(block.content.runs, size: size, bold: true))
                text.append(newline(paragraph(indent: indent, before: size * 0.7, after: 4)))
            case .bulletedList, .numberedList, .todo, .toggle:
                let marker: String = switch block.type {
                case .numberedList: "\(item.number ?? 1)."
                case .todo: block.content.isChecked ? "☑" : "☐"
                case .toggle: "▸"
                default: "•"
                }
                text.append(NSAttributedString(string: marker + "\t", attributes: [
                    .font: font(size: bodySize),
                    .foregroundColor: block.type == .bulletedList ? accent : secondary,
                ]))
                let body = NSMutableAttributedString(attributedString: runs(block.content.runs, size: bodySize))
                if block.type == .todo, block.content.isChecked {
                    let range = NSRange(location: 0, length: body.length)
                    body.addAttribute(.foregroundColor, value: secondary, range: range)
                    body.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
                text.append(body)
                text.append(newline(paragraph(indent: indent, hanging: 18, after: 3)))
            case .quote:
                text.append(NSAttributedString(string: "┃\t", attributes: [.font: font(size: bodySize), .foregroundColor: accent]))
                text.append(runs(block.content.runs, size: bodySize, italic: true))
                text.append(newline(paragraph(indent: indent, hanging: 14)))
            case .callout:
                text.append(NSAttributedString(string: "💡\t", attributes: [.font: font(size: bodySize)]))
                let body = NSMutableAttributedString(attributedString: runs(block.content.runs, size: bodySize))
                body.addAttribute(.backgroundColor, value: calloutBackground, range: NSRange(location: 0, length: body.length))
                text.append(body)
                text.append(newline(paragraph(indent: indent, hanging: 22)))
            case .code:
                text.append(NSAttributedString(string: block.text, attributes: [
                    .font: font(size: 10, monospaced: true),
                    .foregroundColor: ink,
                    .backgroundColor: codeBackground,
                ]))
                text.append(newline(paragraph(indent: indent + 6, after: 8)))
            case .divider:
                text.append(NSAttributedString(attachment: lineAttachment()))
                text.append(newline(paragraph(indent: indent, before: 4, after: 10)))
            case .page:
                text.append(NSAttributedString(string: "📄 " + export.linkedTitle(block), attributes: [
                    .font: font(size: bodySize, bold: true),
                    .foregroundColor: accent,
                ]))
                text.append(newline(paragraph(indent: indent)))
            case .image:
                guard let name = block.content.attachment,
                      let data = attachments.data(for: name),
                      let attachment = imageAttachment(data)
                else { continue }
                text.append(NSAttributedString(attachment: attachment))
                let style = paragraph(indent: indent, before: 4, after: 10)
                style.alignment = .center
                text.append(newline(style))
            case .excerpt:
                text.append(NSAttributedString(string: "┃\t", attributes: [.font: font(size: bodySize), .foregroundColor: accent]))
                text.append(runs(block.content.runs, size: bodySize, italic: true))
                if let caption = export.excerptCaption(block) {
                    text.append(NSAttributedString(string: "\u{2028}— " + caption, attributes: [
                        .font: font(size: 9.5),
                        .foregroundColor: secondary,
                    ]))
                }
                text.append(newline(paragraph(indent: indent, hanging: 14, after: 8)))
            case .drawing:
                for attachment in drawingAttachments(block, attachments: attachments) {
                    text.append(NSAttributedString(attachment: attachment))
                    let style = paragraph(indent: indent, before: 4, after: 10)
                    style.alignment = .center
                    text.append(newline(style))
                }
            case .columnList, .column:
                continue
            }
        }
        return text
    }

    private static func runs(_ runs: [TextRun], size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(
                    size: size,
                    bold: bold || run.marks.contains(.bold),
                    italic: italic || run.marks.contains(.italic),
                    monospaced: run.marks.contains(.code)
                ),
                .foregroundColor: ink,
            ]
            if run.marks.contains(.code) {
                attributes[.backgroundColor] = codeBackground
            }
            if run.marks.contains(.underline) {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if run.marks.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link, !link.isEmpty {
                attributes[.foregroundColor] = accent
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let url = URL(string: link) {
                    attributes[.link] = url
                }
            }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }

    /// Конец абзаца: стиль ставится на весь абзац, включая этот перенос строки.
    private static func newline(_ style: NSParagraphStyle) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: font(size: bodySize), .paragraphStyle: style])
    }

    private static func paragraph(
        indent: CGFloat = 0,
        hanging: CGFloat = 0,
        before: CGFloat = 0,
        after: CGFloat = 6
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent + hanging
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineSpacing = 2
        if hanging > 0 {
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)]
        }
        return style
    }

    private static func font(size: CGFloat, bold: Bool = false, italic: Bool = false, monospaced: Bool = false) -> ExportFont {
        let weight: ExportFont.Weight = bold ? .semibold : .regular
        let base = monospaced
            ? ExportFont.monospacedSystemFont(ofSize: size, weight: weight)
            : ExportFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return base }
        #if canImport(UIKit)
        let traits = base.fontDescriptor.symbolicTraits.union(.traitItalic)
        return base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: size) } ?? base
        #else
        let traits = base.fontDescriptor.symbolicTraits.union(.italic)
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
        #endif
    }

    // MARK: Картинки

    private static func imageAttachment(_ data: Data) -> NSTextAttachment? {
        guard let image = PlatformImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        // Картинка помещается в ширину листа и не выше половины листа, чтобы её не резало между страницами.
        let scale = min(1, contentSize.width / image.size.width, contentSize.height * 0.55 / image.size.height)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        return attachment(image, size: size)
    }

    /// Рисунок от руки на белом листе: чернила в светлой теме. Область рисунка в заметке
    /// это одна картинка, рукописная заметка даёт по картинке на каждый лист.
    private static func drawingAttachments(_ block: Block, attachments: AttachmentStore) -> [NSTextAttachment] {
        let drawing = DrawingSupport.drawing(from: block.drawing)
        if block.content.sheetCount != nil {
            // Лист тетради попадает в PDF, если на нём пишут или под ним страница PDF. Пустые нет.
            return (0..<NotebookLayout.sheetCount(of: block.content)).compactMap { index in
                let rect = NotebookLayout.sheetRect(index)
                let background = NotebookSheets.background(of: block.content, sheet: index)
                let hasInk = drawing.strokes.contains { $0.renderBounds.intersects(rect) }
                guard hasInk || background != nil else { return nil }
                guard let image = sheetImage(drawing: drawing, rect: rect, background: background, attachments: attachments) else {
                    return nil
                }
                return sheetAttachment(image, rect: rect)
            }
        }
        guard !drawing.strokes.isEmpty else { return [] }
        // Область шире листа PDF: рисунок берётся по его штрихам, а не по ширине окна.
        let bounds = drawing.bounds
        let rect = CGRect(x: 0, y: 0, width: max(bounds.maxX, 1), height: max(bounds.maxY, 1)).insetBy(dx: -8, dy: -8)
        guard let image = DrawingSupport.image(of: drawing, in: rect, scale: 2, isDark: false) else { return [] }
        return [sheetAttachment(image, rect: rect)]
    }

    private static func sheetAttachment(_ image: PlatformImage, rect: CGRect) -> NSTextAttachment {
        let scale = min(1, contentSize.width / rect.width, contentSize.height * 0.92 / rect.height)
        let size = CGSize(width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
        return attachment(image, size: size)
    }

    /// Лист тетради одной картинкой: страница PDF (если есть) и чернила поверх неё.
    private static func sheetImage(
        drawing: PKDrawing,
        rect: CGRect,
        background: SheetBackground?,
        attachments: AttachmentStore
    ) -> PlatformImage? {
        let ink = drawing.strokes.isEmpty ? nil : DrawingSupport.image(of: drawing, in: rect, scale: 2, isDark: false)
        guard let background else { return ink }
        let pageSize = SheetPDFImages.pageSize(background, attachments: attachments)
        let bounds = CGRect(origin: .zero, size: rect.size)
        let frame = pageSize.map { NotebookSheets.fit(pageSize: $0, in: bounds) } ?? bounds
        guard let page = SheetPDFImages.image(background, attachments: attachments, pixelWidth: frame.width * 2, dark: false) else {
            return ink
        }
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(bounds)
            UIImage(cgImage: page).draw(in: frame)
            ink?.draw(in: bounds)
        }
        #else
        return NSImage(size: rect.size, flipped: true) { _ in
            NSColor.white.setFill()
            bounds.fill()
            // Картинка страницы рисуется в перевёрнутых координатах: иначе встала бы вверх ногами.
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.translateBy(x: frame.minX, y: frame.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(page, in: CGRect(origin: .zero, size: frame.size))
                context.restoreGState()
            }
            ink?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        #endif
    }

    /// Тонкая линия разделителя во всю ширину текста.
    private static func lineAttachment() -> NSTextAttachment {
        let size = CGSize(width: contentSize.width, height: 9)
        #if canImport(UIKit)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 0.82, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 4, width: size.width, height: 1))
        }
        #else
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.82, alpha: 1).setFill()
            NSRect(x: 0, y: 4, width: rect.width, height: 1).fill()
            return true
        }
        #endif
        return attachment(image, size: size)
    }

    private static func attachment(_ image: PlatformImage, size: CGSize) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        #if canImport(UIKit)
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: size)
        #else
        // На Mac старая вёрстка текста рисует вложение через ячейку: её размер это размер картинки.
        image.size = size
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        #endif
        return attachment
    }

    // MARK: Листы

    /// Раскладывает текст по листам A4 и рисует их в PDF.
    static func pdf(from text: NSAttributedString, title: String) -> Data {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        var containers: [NSTextContainer] = []
        // Новые листы добавляются, пока весь текст не разложен. Ограничение страхует от зацикливания,
        // если что-то не помещается даже на пустой лист.
        while containers.count < 1000 {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            let range = layout.glyphRange(for: container)
            if NSMaxRange(range) >= layout.numberOfGlyphs { break }
            if range.length == 0, containers.count > 1 {
                layout.removeTextContainer(at: containers.count - 1)
                containers.removeLast()
                break
            }
        }
        let origin = CGPoint(x: margin, y: margin)

        #if canImport(UIKit)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Lumen"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            for container in containers {
                context.beginPage()
                let range = layout.glyphRange(for: container)
                layout.drawBackground(forGlyphRange: range, at: origin)
                layout.drawGlyphs(forGlyphRange: range, at: origin)
            }
        }
        #else
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Lumen"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info)
        else { return Data() }
        for container in containers {
            context.beginPDFPage(nil)
            context.saveGState()
            // Текст раскладывается сверху вниз, а у PDF начало координат внизу: лист переворачивается.
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let range = layout.glyphRange(for: container)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
        #endif
    }
}
