import Foundation
import LumenCore
import PDFKit
import SwiftUI

/// Выделение на страницах PDF, которое показывает читалка.
public struct PDFHighlight: Hashable, Sendable {
    public var id: UUID
    public var locator: SourceLocator
    public var colorHex: UInt32

    public init(id: UUID, locator: SourceLocator, colorHex: UInt32) {
        self.id = id
        self.locator = locator
        self.colorHex = colorHex
    }
}

public enum PDFReaderEvent: Sendable {
    /// Выделили текст: место уже готово для выделения цветом.
    case selection(text: String, locator: SourceLocator)
    case selectionCleared
    /// Открыта страница `index` из `count`.
    case pageChanged(index: Int, count: Int)
    case highlightTapped(UUID)
}

/// Управляет видом PDF: открывает файл, переходит к странице или выделению, рисует выделения.
@MainActor
public final class PDFReaderController: NSObject {
    public let pdfView = PDFView()
    public var onEvent: (@MainActor (PDFReaderEvent) -> Void)?

    private var annotations: [UUID: [PDFAnnotation]] = [:]
    private var highlights: [PDFHighlight] = []
    private static let highlightKey = PDFAnnotationKey(rawValue: "LumenHighlight")

    public override init() {
        super.init()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        #if os(macOS)
        pdfView.backgroundColor = NSColor(red: 0.13, green: 0.09, blue: 0.12, alpha: 1)
        #else
        pdfView.backgroundColor = UIColor(red: 0.13, green: 0.09, blue: 0.12, alpha: 1)
        pdfView.pageShadowsEnabled = true
        #endif
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        center.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        center.addObserver(self, selector: #selector(annotationHit(_:)), name: .PDFViewAnnotationHit, object: pdfView)
    }

    public var pageCount: Int { pdfView.document?.pageCount ?? 0 }

    @discardableResult
    public func load(_ url: URL) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        pdfView.document = document
        annotations = [:]
        let current = highlights
        highlights = []
        setHighlights(current)
        return true
    }

    /// Переходит к месту: к прямоугольнику выделения или к началу страницы.
    public func go(to locator: SourceLocator) {
        guard let document = pdfView.document, let page = document.page(at: min(locator.section, max(document.pageCount - 1, 0))) else { return }
        if let rect = locator.rects?.first(where: { $0.page == nil || $0.page == locator.section }) {
            let bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            pdfView.go(to: bounds.insetBy(dx: 0, dy: -80), on: page)
        } else {
            pdfView.go(to: page)
        }
    }

    /// Оглавление PDF (закладки файла). Якорь пункта это точка на странице: `x,y`.
    public func outline() -> [TocEntry] {
        guard let document = pdfView.document, let root = document.outlineRoot else { return [] }
        var entries: [TocEntry] = []
        func walk(_ item: PDFOutline, level: Int) {
            for index in 0..<item.numberOfChildren {
                guard let child = item.child(at: index) else { continue }
                let title = (child.label ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if !title.isEmpty, let destination = child.destination, let page = destination.page {
                    let point = destination.point
                    let anchor = point.x.isFinite && point.y.isFinite && point.y < 1_000_000 ? "\(point.x),\(point.y)" : nil
                    entries.append(TocEntry(title: title, section: document.index(for: page), anchor: anchor, level: level))
                }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 0)
        return entries
    }

    /// Переход к пункту оглавления: к точке на странице, если она известна.
    public func go(to entry: TocEntry) {
        guard let document = pdfView.document, let page = document.page(at: entry.section) else { return }
        let parts = entry.anchor?.split(separator: ",").compactMap { Double($0) } ?? []
        if parts.count == 2 {
            pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: parts[0], y: parts[1])))
        } else {
            pdfView.go(to: page)
        }
    }

    public func reveal(_ id: UUID) {
        guard let highlight = highlights.first(where: { $0.id == id }) else { return }
        go(to: highlight.locator)
    }

    public func clearSelection() {
        pdfView.clearSelection()
    }

    /// Номер открытой страницы, с нуля.
    public var currentPageIndex: Int {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return 0 }
        return document.index(for: page)
    }

    public func setHighlights(_ highlights: [PDFHighlight]) {
        guard highlights != self.highlights else { return }
        let removed = Set(self.highlights.map(\.id)).subtracting(highlights.map(\.id))
        for id in removed {
            for annotation in annotations.removeValue(forKey: id) ?? [] {
                annotation.page?.removeAnnotation(annotation)
            }
        }
        let previous = Dictionary(self.highlights.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.highlights = highlights
        guard let document = pdfView.document else { return }
        for highlight in highlights where previous[highlight.id] != highlight || annotations[highlight.id] == nil {
            for annotation in annotations.removeValue(forKey: highlight.id) ?? [] {
                annotation.page?.removeAnnotation(annotation)
            }
            var added: [PDFAnnotation] = []
            for rect in highlight.locator.rects ?? [] {
                guard let page = document.page(at: rect.page ?? highlight.locator.section) else { continue }
                let annotation = PDFAnnotation(
                    bounds: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
                    forType: .highlight,
                    withProperties: nil
                )
                annotation.color = Self.color(highlight.colorHex).withAlphaComponent(0.45)
                annotation.setValue(highlight.id.uuidString, forAnnotationKey: Self.highlightKey)
                page.addAnnotation(annotation)
                added.append(annotation)
            }
            annotations[highlight.id] = added
        }
    }

    // MARK: Уведомления PDFView

    @objc private func selectionChanged() {
        guard let document = pdfView.document,
              let selection = pdfView.currentSelection,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let firstPage = selection.pages.first else {
            onEvent?(.selectionCleared)
            return
        }
        let section = document.index(for: firstPage)
        var rects: [LocatorRect] = []
        for line in selection.selectionsByLine() {
            guard let page = line.pages.first else { continue }
            let bounds = line.bounds(for: page)
            guard bounds.width > 0.5, bounds.height > 0.5 else { continue }
            let index = document.index(for: page)
            rects.append(LocatorRect(
                page: index == section ? nil : index,
                x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height
            ))
        }
        let progression = document.pageCount > 1 ? Double(section) / Double(document.pageCount - 1) : 0
        onEvent?(.selection(
            text: text,
            locator: SourceLocator(section: section, progression: progression, text: text, rects: rects)
        ))
    }

    @objc private func pageChanged() {
        onEvent?(.pageChanged(index: currentPageIndex, count: pageCount))
    }

    @objc private func annotationHit(_ notification: Notification) {
        guard let annotation = notification.userInfo?["PDFAnnotationHit"] as? PDFAnnotation,
              let value = annotation.value(forAnnotationKey: Self.highlightKey) as? String,
              let id = UUID(uuidString: value) else { return }
        onEvent?(.highlightTapped(id))
    }

    #if os(macOS)
    static func color(_ hex: UInt32) -> NSColor {
        NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    #else
    static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    #endif
}

/// PDF в SwiftUI.
public struct PDFReaderView: View {
    let controller: PDFReaderController

    public init(controller: PDFReaderController) {
        self.controller = controller
    }

    public var body: some View {
        Representable(controller: controller)
    }

    #if os(macOS)
    private struct Representable: NSViewRepresentable {
        let controller: PDFReaderController
        func makeNSView(context: Context) -> PDFView { controller.pdfView }
        func updateNSView(_ nsView: PDFView, context: Context) {}
    }
    #else
    private struct Representable: UIViewRepresentable {
        let controller: PDFReaderController
        func makeUIView(context: Context) -> PDFView { controller.pdfView }
        func updateUIView(_ uiView: PDFView, context: Context) {}
    }
    #endif
}
