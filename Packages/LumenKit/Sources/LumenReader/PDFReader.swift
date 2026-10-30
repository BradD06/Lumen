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
    /// Прокрутили страницу или поменяли масштаб: место чтения сдвинулось.
    case moved
    /// Новый масштаб, 1 это настоящий размер страницы.
    case scaleChanged(Double)
    case highlightTapped(UUID)
}

/// Управляет видом PDF: открывает файл, переходит к странице или выделению, рисует выделения.
@MainActor
public final class PDFReaderController: NSObject {
    public let pdfView = PDFView()
    public var onEvent: (@MainActor (PDFReaderEvent) -> Void)?

    private var annotations: [UUID: [PDFAnnotation]] = [:]
    private var highlights: [PDFHighlight] = []
    private let pageFactory = TintedPageFactory()
    private var pageStyle = PDFPageStyle.original
    private static let highlightKey = PDFAnnotationKey(rawValue: "LumenHighlight")
    /// Зафиксированный масштаб: пока он есть, страницы не подгоняются под окно и щипок не меняет размер.
    public private(set) var lockedScale: Double?
    public static let scaleRange: ClosedRange<Double> = 0.25...8
    #if os(macOS)
    private weak var observedClipView: NSClipView?
    #else
    private var scrollObservation: NSKeyValueObservation?
    private weak var observedScrollView: UIScrollView?
    #endif

    public override init() {
        super.init()
        pdfView.autoScales = true
        pdfView.minScaleFactor = CGFloat(Self.scaleRange.lowerBound)
        pdfView.maxScaleFactor = CGFloat(Self.scaleRange.upperBound)
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = Self.color(pageStyle.backdrop)
        // Страницы сами рисуют себе скруглённые углы, поэтому прямоугольная тень не нужна.
        pdfView.pageShadowsEnabled = false
        pdfView.displaysPageBreaks = true
        #if os(macOS)
        pdfView.pageBreakMargins = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        #else
        pdfView.pageBreakMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        #endif
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        center.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        center.addObserver(self, selector: #selector(annotationHit(_:)), name: .PDFViewAnnotationHit, object: pdfView)
        center.addObserver(self, selector: #selector(scaleChanged), name: .PDFViewScaleChanged, object: pdfView)
    }

    public var pageCount: Int { pdfView.document?.pageCount ?? 0 }

    @discardableResult
    public func load(_ url: URL) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        document.delegate = pageFactory
        applyStyle(to: document)
        pdfView.document = document
        annotations = [:]
        let current = highlights
        highlights = []
        setHighlights(current)
        applyZoom()
        observeScrolling()
        return true
    }

    /// Переходит к месту: к прямоугольнику выделения, к точке, где остановились, или к началу страницы.
    public func go(to locator: SourceLocator) {
        observeScrolling()
        guard let document = pdfView.document, let page = document.page(at: min(locator.section, max(document.pageCount - 1, 0))) else { return }
        if let rect = locator.rects?.first(where: { $0.page == nil || $0.page == locator.section }) {
            let bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            pdfView.go(to: bounds.insetBy(dx: 0, dy: -80), on: page)
        } else if let point = locator.point, point.x.isFinite, point.y.isFinite {
            pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: point.x, y: point.y)))
        } else {
            pdfView.go(to: page)
        }
    }

    /// Где сейчас читают: страница и её точка в левом верхнем углу экрана.
    public var readingLocator: SourceLocator {
        guard let document = pdfView.document else { return SourceLocator(section: 0) }
        var index = currentPageIndex
        var point: LocatorPoint?
        if let destination = pdfView.currentDestination, let page = destination.page {
            index = document.index(for: page)
            let at = destination.point
            // Пока вид не разложен, PDFKit отдаёт вместо точки огромные числа.
            if at.x.isFinite, at.y.isFinite, abs(at.x) < 100_000, abs(at.y) < 100_000 {
                point = LocatorPoint(x: at.x, y: at.y)
            }
        }
        let progression = document.pageCount > 1 ? Double(index) / Double(document.pageCount - 1) : 0
        return SourceLocator(section: index, progression: progression, point: point)
    }

    // MARK: Масштаб

    /// Масштаб страниц, 1 это настоящий размер.
    public var scale: Double { Double(pdfView.scaleFactor) }

    /// Масштаб, при котором страница целиком входит по ширине.
    public var fitScale: Double { Double(pdfView.scaleFactorForSizeToFit) }

    /// Фиксирует масштаб (`nil` отпускает). Отпущенный масштаб остаётся каким был, щипок снова работает.
    public func lockZoom(at scale: Double?) {
        lockedScale = scale.map { min(max($0, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) }
        applyZoom()
    }

    /// Крупнее или мельче в `factor` раз. Зафиксированный масштаб остаётся зафиксированным, только новым.
    public func zoom(by factor: Double) {
        let target = min(max(scale * factor, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        if lockedScale != nil {
            lockZoom(at: target)
        } else {
            pdfView.autoScales = false
            pdfView.scaleFactor = CGFloat(target)
        }
    }

    /// Страница по ширине окна. Если масштаб зафиксирован, фиксируется этот.
    public func zoomToFit() {
        if lockedScale != nil {
            lockZoom(at: fitScale)
        } else {
            pdfView.autoScales = true
        }
    }

    private func applyZoom() {
        let range = Self.scaleRange
        if let lockedScale {
            let value = CGFloat(lockedScale)
            pdfView.autoScales = false
            // Сначала раздвигаем границы, иначе PDFView обрежет новый масштаб по старым.
            pdfView.minScaleFactor = CGFloat(range.lowerBound)
            pdfView.maxScaleFactor = CGFloat(range.upperBound)
            pdfView.scaleFactor = value
            // Равные границы и есть фиксация: щипок и жест трекпада масштаб больше не меняют.
            pdfView.minScaleFactor = value
            pdfView.maxScaleFactor = value
        } else {
            pdfView.minScaleFactor = CGFloat(range.lowerBound)
            pdfView.maxScaleFactor = CGFloat(range.upperBound)
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

    /// Перекрашивает страницы под тему читалки и остаётся на том же месте.
    public func setPageStyle(_ style: PDFPageStyle) {
        guard style != pageStyle else { return }
        let wasNight = pageStyle.isNight
        pageStyle = style
        pdfView.backgroundColor = Self.color(style.backdrop)
        guard let document = pdfView.document else { return }
        applyStyle(to: document)
        if wasNight != style.isNight {
            for highlight in highlights {
                for annotation in annotations[highlight.id] ?? [] {
                    annotation.color = highlightColor(highlight.colorHex)
                }
            }
        }
        // Уже нарисованные страницы PDFView держит в кэше: перерисовываем документ заново.
        let destination = pdfView.currentDestination
        pdfView.document = nil
        pdfView.document = document
        if let destination { pdfView.go(to: destination) }
        observeScrolling()
    }

    private func applyStyle(to document: PDFDocument) {
        for index in 0..<document.pageCount {
            (document.page(at: index) as? TintedPDFPage)?.style = pageStyle
        }
    }

    /// Ночью страница инвертируется целиком, поэтому выделение красится в обратный цвет:
    /// после инверсии оно снова того цвета, который выбрали.
    private func highlightColor(_ hex: UInt32) -> PlatformColor {
        let shown = pageStyle.isNight ? (~hex & 0xFFFFFF) : hex
        return Self.color(shown).withAlphaComponent(0.45)
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
                annotation.color = highlightColor(highlight.colorHex)
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

    @objc private func scaleChanged() {
        onEvent?(.scaleChanged(scale))
        onEvent?(.moved)
    }

    /// Прокрутка внутри страницы уведомления PDFView не даёт: слушаем его прокручиваемый вид.
    private func observeScrolling() {
        #if os(macOS)
        guard let clipView = pdfView.documentView?.enclosingScrollView?.contentView, clipView !== observedClipView else { return }
        if let observedClipView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clipView)
        #else
        guard let scrollView = Self.firstScrollView(in: pdfView), scrollView !== observedScrollView else { return }
        observedScrollView = scrollView
        scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scrolled() }
        }
        #endif
    }

    #if os(iOS)
    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView { return scrollView }
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
    #endif

    @objc private func scrolled() {
        onEvent?(.moved)
    }

    @objc private func annotationHit(_ notification: Notification) {
        guard let annotation = notification.userInfo?["PDFAnnotationHit"] as? PDFAnnotation,
              let value = annotation.value(forAnnotationKey: Self.highlightKey) as? String,
              let id = UUID(uuidString: value) else { return }
        onEvent?(.highlightTapped(id))
    }

    #if os(macOS)
    typealias PlatformColor = NSColor
    #else
    typealias PlatformColor = UIColor
    #endif

    static func color(_ hex: UInt32) -> PlatformColor {
        PlatformColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
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
