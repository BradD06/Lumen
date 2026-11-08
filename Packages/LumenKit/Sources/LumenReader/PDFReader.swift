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
    /// Масштаб поменяли руками (щипком или жестом трекпада): его стоит запомнить для книги.
    case zoomedByHand
    case highlightTapped(UUID)
}

/// Управляет видом PDF: открывает файл, переходит к странице или выделению, рисует выделения.
/// Умеет показывать страницы без белых полей и по колонкам: тогда на экране не сами страницы файла,
/// а их куски, но места, выделения и события всегда считаются в страницах файла.
@MainActor
public final class PDFReaderController: NSObject {
    public let pdfView: PDFView
    public var onEvent: (@MainActor (PDFReaderEvent) -> Void)?

    private var annotations: [UUID: [PDFAnnotation]] = [:]
    private var highlights: [PDFHighlight] = []
    private let pageFactory = TintedPageFactory()
    private var pageStyle = PDFPageStyle.original
    private static let highlightKey = PDFAnnotationKey(rawValue: "LumenHighlight")
    /// Зафиксированный масштаб: пока он есть, страницы не подгоняются под окно и щипок не меняет размер.
    public private(set) var lockedScale: Double?
    /// Свободный масштаб относительно «по ширине»: 1.3 значит на 30% крупнее. `nil` это ровно по ширине.
    /// Держится при повороте телефона и смене размера окна.
    public private(set) var zoomFactor: Double?
    public static let scaleRange: ClosedRange<Double> = 0.25...8

    private var fileURL: URL?
    /// Документы, из которых взяты страницы на экране: пока страницы показываются, документы нужны.
    private var documents: [PDFDocument] = []
    private var bookLayout: PDFBookLayout?
    public private(set) var layoutOptions = PDFLayoutOptions.original
    /// Для каждой страницы на экране: какая это страница файла и какой её кусок показан.
    private var displayPages: [Int] = []
    private var displayRects: [CGRect] = []
    /// Для каждой страницы файла: какие страницы на экране её показывают.
    private var displayRanges: [Range<Int>] = []
    private var originalCount = 0
    private var tocEntries: [TocEntry] = []
    /// Ширина обычной страницы на экране, если страницы обрезаны или разбиты на колонки.
    /// «По ширине» тогда считается по ней, а не так, как считает PDFKit.
    private var referenceWidth: CGFloat?
    /// Пока страницы перекладываются, события места чтения молчат: иначе запомнится промежуточное место.
    private var isQuiet = false
    private var relayoutTask: Task<Void, Never>?
    #if os(macOS)
    private weak var observedClipView: NSClipView?
    #else
    private var scrollObservation: NSKeyValueObservation?
    private weak var observedScrollView: UIScrollView?
    #endif

    public override init() {
        let view = LumenPDFView()
        pdfView = view
        super.init()
        view.onResize = { [weak self] in self?.viewResized() }
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
        #if os(macOS)
        // Прокрутку забирает внутренний вид PDFView, поэтому свайп по трекпаду ловится до него.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let scroll = TrackpadScroll(event)
            let swallowed = MainActor.assumeIsolated { () -> Bool in
                self?.handleSwipe(scroll) ?? false
            }
            return swallowed ? nil : event
        }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .smartMagnify]) { [weak self] event in
            let ended = event.type == .smartMagnify || (event.type == .magnify && event.phase == .ended)
            let windowNumber = event.windowNumber
            let location = event.locationInWindow
            if ended {
                MainActor.assumeIsolated { self?.magnifyEnded(windowNumber: windowNumber, location: location) }
            }
            return event
        }
        #else
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            swipe.delegate = self
            pdfView.addGestureRecognizer(swipe)
        }
        #endif
    }

    /// Листает на страницу вперёд или назад, как в книге.
    public func turnPage(forward: Bool) {
        if forward {
            guard pdfView.canGoToNextPage else { return }
            pdfView.goToNextPage(nil)
        } else {
            guard pdfView.canGoToPreviousPage else { return }
            pdfView.goToPreviousPage(nil)
        }
    }

    /// Стрелка на клавиатуре. Если страница не влезла в окно (крупный масштаб), сначала
    /// докручивается её скрытая часть, экран за экраном, а потом открывается соседняя страница.
    public func step(forward: Bool) {
        guard let page = pdfView.currentPage else {
            turnPage(forward: forward)
            return
        }
        let rect = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
        let visible = pdfView.bounds
        #if os(macOS)
        let flipped = pdfView.isFlipped
        #else
        let flipped = true
        #endif
        let hiddenBelow = flipped ? rect.maxY - visible.maxY : visible.minY - rect.minY
        let hiddenAbove = flipped ? visible.minY - rect.minY : rect.maxY - visible.maxY
        let hidden = forward ? hiddenBelow : hiddenAbove
        guard hidden > 8 else {
            turnPage(forward: forward)
            return
        }
        scrollVertically(by: min(hidden, max(visible.height - 48, 40)) * (forward ? 1 : -1))
    }

    /// Прокрутка на `distance` пунктов вниз (меньше нуля: вверх) в пределах документа.
    private func scrollVertically(by distance: CGFloat) {
        #if os(macOS)
        guard let clip = pdfView.documentView?.enclosingScrollView?.contentView else { return }
        var origin = clip.bounds.origin
        origin.y += clip.isFlipped ? distance : -distance
        let target = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin
        clip.animator().setBoundsOrigin(target)
        clip.enclosingScrollView?.reflectScrolledClipView(clip)
        #else
        guard let scrollView = Self.firstScrollView(in: pdfView) else { return }
        let maxY = max(scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom, 0)
        let minY = -scrollView.adjustedContentInset.top
        var offset = scrollView.contentOffset
        offset.y = min(max(offset.y + distance, minY), maxY)
        scrollView.setContentOffset(offset, animated: true)
        #endif
    }

    /// Свайп листает, только пока страница целиком входит по ширине: в увеличенной им двигают страницу.
    var canSwipe: Bool {
        Double(pdfView.scaleFactor) <= fitScale * 1.02
    }

    #if os(macOS)
    nonisolated(unsafe) private var scrollMonitor: Any?
    nonisolated(unsafe) private var magnifyMonitor: Any?
    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    /// Страницу уже перелистнули этим жестом: остаток жеста и инерция больше ничего не делают.
    private var swipeTurned = false

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
    }

    /// Горизонтальный свайп двумя пальцами по трекпаду над PDF: одна страница на жест.
    /// Возвращает `true`, если жест забран и прокручивать страницу не нужно.
    private func handleSwipe(_ event: TrackpadScroll) -> Bool {
        guard event.isTrackpad, let window = pdfView.window, event.windowNumber == window.windowNumber,
              pdfView.bounds.contains(pdfView.convert(event.location, from: nil)), canSwipe else { return false }
        if event.phase == .began {
            swipeX = 0
            swipeY = 0
            swipeTurned = false
        }
        if event.phase == .changed {
            // Движение пальцев, а не страницы: свайп влево всегда вперёд, как бы ни была настроена прокрутка.
            swipeX += event.fingersX
            swipeY += abs(event.deltaY)
            if !swipeTurned, abs(swipeX) > 70, abs(swipeX) > swipeY * 2 {
                swipeTurned = true
                turnPage(forward: swipeX < 0)
            }
        }
        let sideways = abs(swipeX) > 6 && abs(swipeX) > swipeY * 2
        return swipeTurned || (sideways && event.momentumPhase == [])
    }
    private func magnifyEnded(windowNumber: Int, location: CGPoint) {
        guard let window = pdfView.window, window.windowNumber == windowNumber,
              pdfView.bounds.contains(pdfView.convert(location, from: nil)) else { return }
        // Масштаб PDFView поменяет уже после этого события.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            self?.zoomEndedByHand()
        }
    }
    #else
    @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
        guard canSwipe else { return }
        turnPage(forward: recognizer.direction == .left)
    }
    #endif

    /// Сколько страниц в файле (кусков на экране может быть больше).
    public var pageCount: Int { pdfView.document == nil ? 0 : originalCount }

    /// Открывает файл. `layout` это разметка полей и колонок, если она уже известна.
    @discardableResult
    public func load(_ url: URL, layout: PDFBookLayout? = nil, options: PDFLayoutOptions = .original) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        relayoutTask?.cancel()
        isQuiet = false
        fileURL = url
        document.delegate = pageFactory
        tocEntries = Self.outline(of: document)
        bookLayout = layout?.pages.count == document.pageCount ? layout : nil
        layoutOptions = options
        show(build(from: document))
        return true
    }

    /// Новая разметка или новые настройки полей и колонок. Место чтения остаётся тем же.
    public func setLayout(_ layout: PDFBookLayout?, options: PDFLayoutOptions) {
        let layout = layout?.pages.count == originalCount ? layout : nil
        let wasChanged = referenceWidth != nil
        bookLayout = layout
        layoutOptions = options
        let willChange = layout != nil && options.changesPages
        guard let url = fileURL, pdfView.document != nil, wasChanged || willChange,
              let document = PDFDocument(url: url) else { return }
        let place = readingLocator
        relayoutTask?.cancel()
        isQuiet = true
        document.delegate = pageFactory
        show(build(from: document))
        go(to: place)
        // Точно перейти к месту PDFView может только после раскладки новых страниц.
        relayoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            self.applyZoom()
            self.go(to: place)
            self.isQuiet = false
            self.emit(.pageChanged(index: self.currentPageIndex, count: self.pageCount))
            self.emit(.scaleChanged(self.scale))
        }
    }

    /// Раскладывает страницы файла по настройкам: обрезает поля, режет на колонки.
    private func build(from first: PDFDocument) -> PDFDocument {
        originalCount = first.pageCount
        documents = [first]
        let pages = (0..<originalCount).compactMap { first.page(at: $0) }
        let plan = bookLayout.flatMap { layout in
            layoutOptions.changesPages ? PDFLayoutPlan.pieces(for: layout, options: layoutOptions) : nil
        }
        guard let plan, pages.count == originalCount, plan.count == originalCount else {
            displayPages = Array(0..<originalCount)
            displayRects = pages.map { $0.bounds(for: .cropBox) }
            displayRanges = (0..<originalCount).map { $0..<($0 + 1) }
            referenceWidth = nil
            return first
        }
        var display = first
        var copies: [PDFPage] = []
        if plan.contains(where: { $0.count > 1 }), let url = fileURL, let second = PDFDocument(url: url) {
            // Вторая колонка это та же страница файла, а одна страница PDFKit не может стоять дважды:
            // берём её из второго экземпляра того же файла.
            second.delegate = pageFactory
            copies = (0..<originalCount).compactMap { second.page(at: $0) }
            if copies.count == originalCount {
                display = PDFDocument()
                documents.append(second)
            } else {
                copies = []
            }
        }
        displayPages = []
        displayRects = []
        displayRanges = []
        for index in 0..<originalCount {
            let pieces = copies.isEmpty ? Array(plan[index].prefix(1)) : plan[index]
            let start = displayPages.count
            for (number, rect) in pieces.enumerated() {
                let page = number == 0 ? pages[index] : copies[index]
                page.setBounds(rect, for: .cropBox)
                if display !== first { display.insert(page, at: display.pageCount) }
                displayPages.append(index)
                displayRects.append(rect)
            }
            displayRanges.append(start..<displayPages.count)
        }
        if display !== first { documents.append(display) }
        // Обычная ширина: по середине списка, чтобы редкие широкие страницы её не раздували.
        let widths = zip(displayPages, displayRects).map { index, rect in
            pages[index].rotation % 180 == 0 ? rect.width : rect.height
        }.sorted()
        referenceWidth = widths.isEmpty ? nil : widths[widths.count / 2]
        return display
    }

    private func show(_ document: PDFDocument) {
        applyStyle(to: document)
        pdfView.document = document
        annotations = [:]
        let current = highlights
        highlights = []
        setHighlights(current)
        applyZoom()
        observeScrolling()
    }

    /// Страница файла, которую показывает страница экрана.
    private func originalIndex(of page: PDFPage) -> Int? {
        guard let document = pdfView.document else { return nil }
        let index = document.index(for: page)
        return displayPages.indices.contains(index) ? displayPages[index] : nil
    }

    /// Страница экрана, которая показывает страницу файла `original` в точке `x` (колонку, где эта точка).
    private func displayPage(_ original: Int, x: CGFloat? = nil) -> PDFPage? {
        guard let document = pdfView.document, displayRanges.indices.contains(original) else { return nil }
        let range = displayRanges[original]
        guard let first = range.first else { return nil }
        var chosen = first
        if let x, range.count > 1 {
            chosen = range.min { distance(x, displayRects[$0]) < distance(x, displayRects[$1]) } ?? first
        }
        return document.page(at: chosen)
    }

    private func distance(_ x: CGFloat, _ rect: CGRect) -> CGFloat {
        x < rect.minX ? rect.minX - x : (x >= rect.maxX ? x - rect.maxX + 0.01 : 0)
    }

    /// Переходит к месту: к прямоугольнику выделения, к точке, где остановились, или к началу страницы.
    public func go(to locator: SourceLocator) {
        observeScrolling()
        let section = min(locator.section, max(originalCount - 1, 0))
        if let rect = locator.rects?.first(where: { $0.page == nil || $0.page == locator.section }) {
            let bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            guard let page = displayPage(section, x: bounds.midX) else { return }
            pdfView.go(to: bounds.insetBy(dx: 0, dy: -80), on: page)
        } else if let point = locator.point, point.x.isFinite, point.y.isFinite {
            // Точка это левый верхний угол экрана: колонку ищем чуть правее неё.
            guard let page = displayPage(section, x: CGFloat(point.x + 8)) else { return }
            pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: point.x, y: point.y)))
        } else if let page = displayPage(section) {
            pdfView.go(to: page)
        }
    }

    /// Где сейчас читают: страница и её точка в левом верхнем углу экрана.
    public var readingLocator: SourceLocator {
        guard pdfView.document != nil else { return SourceLocator(section: 0) }
        var index = currentPageIndex
        var point: LocatorPoint?
        if let destination = pdfView.currentDestination, let page = destination.page, let original = originalIndex(of: page) {
            index = original
            let at = destination.point
            // Пока вид не разложен, PDFKit отдаёт вместо точки огромные числа.
            if at.x.isFinite, at.y.isFinite, abs(at.x) < 100_000, abs(at.y) < 100_000 {
                point = LocatorPoint(x: at.x, y: at.y)
            }
        }
        let progression = originalCount > 1 ? Double(index) / Double(originalCount - 1) : 0
        return SourceLocator(section: index, progression: progression, point: point)
    }

    // MARK: Масштаб

    /// Масштаб страниц, 1 это настоящий размер.
    public var scale: Double { Double(pdfView.scaleFactor) }

    /// Масштаб, при котором обычная страница (или колонка) целиком входит по ширине.
    public var fitScale: Double {
        guard let referenceWidth, referenceWidth > 1, pdfView.bounds.width > 1 else {
            return Double(pdfView.scaleFactorForSizeToFit)
        }
        let margins = pdfView.pageBreakMargins.left + pdfView.pageBreakMargins.right
        var width = pdfView.bounds.width
        #if os(iOS)
        width -= pdfView.safeAreaInsets.left + pdfView.safeAreaInsets.right
        #endif
        // PDFKit где-то масштабирует отступы между страницами, а где-то нет: берём меньший масштаб,
        // чтобы страница точно не вылезала вбок.
        let fit = min((width - margins) / referenceWidth, width / (referenceWidth + margins)) * 0.995
        return Self.clamp(Double(fit))
    }

    /// Свободный масштаб сейчас, относительно «по ширине». `nil`, если это и есть «по ширине».
    public var currentZoomFactor: Double? {
        let fit = fitScale
        guard fit > 0 else { return nil }
        let factor = scale / fit
        return abs(factor - 1) < 0.02 ? nil : factor
    }

    /// Масштаб при открытии книги: зафиксированный или свободный, относительно «по ширине».
    public func setZoom(locked: Double?, factor: Double?) {
        lockedScale = locked.map(Self.clamp)
        zoomFactor = factor
        applyZoom()
    }

    /// Фиксирует масштаб (`nil` отпускает). Отпущенный масштаб остаётся каким был, щипок снова работает.
    public func lockZoom(at scale: Double?) {
        if scale == nil, lockedScale != nil { zoomFactor = currentZoomFactor }
        lockedScale = scale.map(Self.clamp)
        applyZoom()
    }

    /// Ставит масштаб заново: после раскладки страниц или смены размера.
    public func refreshZoom() {
        applyZoom()
    }

    /// Крупнее или мельче в `factor` раз. Зафиксированный масштаб остаётся зафиксированным, только новым.
    public func zoom(by factor: Double) {
        let target = Self.clamp(scale * factor)
        if lockedScale != nil {
            lockZoom(at: target)
        } else {
            let fit = fitScale
            zoomFactor = fit > 0 && abs(target / fit - 1) >= 0.02 ? target / fit : nil
            applyZoom()
        }
    }

    /// Страница по ширине окна. Если масштаб зафиксирован, фиксируется этот.
    public func zoomToFit() {
        if lockedScale != nil {
            lockZoom(at: fitScale)
        } else {
            zoomFactor = nil
            applyZoom()
        }
    }

    /// Щипок или жест трекпада закончился: новый масштаб становится масштабом книги.
    private func zoomEndedByHand() {
        guard lockedScale == nil, pdfView.document != nil else { return }
        zoomFactor = currentZoomFactor
        emit(.zoomedByHand)
    }

    private func viewResized() {
        // Свободный масштаб держится относительно ширины: при повороте телефона текст остаётся по ширине.
        guard lockedScale == nil, referenceWidth != nil || zoomFactor != nil else { return }
        applyZoom()
    }

    static func clamp(_ scale: Double) -> Double {
        min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    private func setScale(_ value: Double) {
        let target = CGFloat(Self.clamp(value))
        if abs(pdfView.scaleFactor - target) > 0.0005 { pdfView.scaleFactor = target }
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
            return
        }
        pdfView.minScaleFactor = CGFloat(range.lowerBound)
        pdfView.maxScaleFactor = CGFloat(range.upperBound)
        if referenceWidth != nil {
            // Пока вид не разложен, ширины нет: масштаб поставится, когда она появится.
            guard pdfView.bounds.width > 1 else { return }
            pdfView.autoScales = false
            setScale(fitScale * (zoomFactor ?? 1))
        } else if let zoomFactor {
            guard pdfView.bounds.width > 1 else { return }
            pdfView.autoScales = false
            setScale(Double(pdfView.scaleFactorForSizeToFit) * zoomFactor)
        } else {
            pdfView.autoScales = true
        }
        hookPinch()
    }

    /// Оглавление PDF (закладки файла). Якорь пункта это точка на странице: `x,y`.
    public func outline() -> [TocEntry] {
        tocEntries
    }

    private static func outline(of document: PDFDocument) -> [TocEntry] {
        guard let root = document.outlineRoot else { return [] }
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
        let parts = entry.anchor?.split(separator: ",").compactMap { Double($0) } ?? []
        let x: CGFloat? = parts.count == 2 ? CGFloat(parts[0] + 8) : nil
        guard let page = displayPage(entry.section, x: x) else { return }
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
        guard let page = pdfView.currentPage else { return 0 }
        return originalIndex(of: page) ?? 0
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
        applyZoom()
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
                let original = rect.page ?? highlight.locator.section
                guard displayRanges.indices.contains(original) else { continue }
                let bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
                let range = displayRanges[original]
                // Страница в две колонки показана двумя кусками: выделение рисуется на том, где оно видно.
                for displayIndex in range where range.count == 1 || displayRects[displayIndex].intersects(bounds) {
                    guard let page = document.page(at: displayIndex) else { continue }
                    let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    annotation.color = highlightColor(highlight.colorHex)
                    annotation.setValue(highlight.id.uuidString, forAnnotationKey: Self.highlightKey)
                    page.addAnnotation(annotation)
                    added.append(annotation)
                }
            }
            annotations[highlight.id] = added
        }
    }

    // MARK: Уведомления PDFView

    @objc private func selectionChanged() {
        guard let selection = pdfView.currentSelection,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let firstPage = selection.pages.first,
              let section = originalIndex(of: firstPage) else {
            emit(.selectionCleared)
            return
        }
        var rects: [LocatorRect] = []
        for line in selection.selectionsByLine() {
            guard let page = line.pages.first, let index = originalIndex(of: page) else { continue }
            let bounds = line.bounds(for: page)
            guard bounds.width > 0.5, bounds.height > 0.5 else { continue }
            rects.append(LocatorRect(
                page: index == section ? nil : index,
                x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height
            ))
        }
        let progression = originalCount > 1 ? Double(section) / Double(originalCount - 1) : 0
        emit(.selection(
            text: text,
            locator: SourceLocator(section: section, progression: progression, text: text, rects: rects)
        ))
    }

    private func emit(_ event: PDFReaderEvent) {
        guard !isQuiet else { return }
        onEvent?(event)
    }

    @objc private func pageChanged() {
        emit(.pageChanged(index: currentPageIndex, count: pageCount))
    }

    @objc private func scaleChanged() {
        emit(.scaleChanged(scale))
        emit(.moved)
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
        // Палец, который ведёт почти вертикально, двигает страницу только вверх-вниз, без съезда вбок.
        scrollView.isDirectionalLockEnabled = true
        scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scrolled() }
        }
        hookPinch()
        #endif
    }

    #if os(iOS)
    private weak var hookedPinch: UIPinchGestureRecognizer?

    /// Узнаёт, когда щипок закончился. Распознаватель щипка бывает только у незафиксированного масштаба.
    private func hookPinch() {
        guard let pinch = observedScrollView?.pinchGestureRecognizer, pinch !== hookedPinch else { return }
        hookedPinch = pinch
        pinch.addTarget(self, action: #selector(pinched(_:)))
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        zoomEndedByHand()
    }
    #else
    private func hookPinch() {}
    #endif

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
        emit(.moved)
    }

    @objc private func annotationHit(_ notification: Notification) {
        guard let annotation = notification.userInfo?["PDFAnnotationHit"] as? PDFAnnotation,
              let value = annotation.value(forAnnotationKey: Self.highlightKey) as? String,
              let id = UUID(uuidString: value) else { return }
        emit(.highlightTapped(id))
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

#if os(iOS)
extension PDFReaderController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        canSwipe
    }
}
#endif

#if os(macOS)
/// То, что нужно от события прокрутки, чтобы узнать свайп. Само событие на главный поток не передаётся.
struct TrackpadScroll: Sendable {
    var isTrackpad: Bool
    var windowNumber: Int
    var location: CGPoint
    var phase: NSEvent.Phase
    var momentumPhase: NSEvent.Phase
    /// Куда двигались пальцы по горизонтали, без учёта настройки «естественной» прокрутки.
    var fingersX: CGFloat
    var deltaY: CGFloat

    init(_ event: NSEvent) {
        isTrackpad = event.hasPreciseScrollingDeltas
        windowNumber = event.windowNumber
        location = event.locationInWindow
        phase = event.phase
        momentumPhase = event.momentumPhase
        fingersX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        deltaY = event.scrollingDeltaY
    }
}
#endif

/// PDFView, который говорит, когда поменялся его размер: «по ширине» тогда считается заново.
final class LumenPDFView: PDFView {
    var onResize: (@MainActor () -> Void)?
    private var lastSize = CGSize.zero

    #if os(macOS)
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sizeMaybeChanged()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        sizeMaybeChanged()
    }
    #endif

    private func sizeMaybeChanged() {
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onResize?()
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
