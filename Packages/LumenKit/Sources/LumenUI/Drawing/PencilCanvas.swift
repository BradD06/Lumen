#if os(iOS)
import LumenCore
import LumenStorage
import PencilKit
import SwiftUI
import UIKit

/// Холст PencilKit: Apple Pencil с нажимом и наклоном, на iPhone палец.
/// Внизу системная панель инструментов PencilKit: ручки, маркер, ластик, линейка, цвета.
///
/// Два режима. Область рисунка в заметке (`notebook == nil`) не прокручивается, у неё размер блока.
/// Рукописная заметка прокручивается и масштабируется щипком, под штрихами лежат листы бумаги.
struct PencilCanvas: UIViewRepresentable {
    struct Notebook: Equatable {
        var sheets: Int
        var pattern: PaperPattern
        var tone: PaperTone
    }

    var data: Data?
    /// Принимает ли холст штрихи. Выключенный холст пропускает пальцы к прокрутке.
    var isDrawingEnabled: Bool
    var showsToolPicker: Bool
    var isDark: Bool
    var notebook: Notebook?
    /// Масштаб области рисунка в заметке (`notebook == nil`): меньше 1, когда холст шире области.
    var areaZoom: CGFloat = 1
    var onChange: (Data?) -> Void
    /// Лист рукописной заметки, который сейчас посередине экрана.
    var onVisibleSheet: (Int) -> Void = { _ in }
    /// Тексты и картинки тетради: лежат под чернилами.
    var items: NotebookItemsContent?
    /// Нажатие на пустое место холста, в координатах холста. Пока `nil`, нажатия не ловятся.
    var onTap: ((CGPoint) -> Void)?
    /// Где сейчас холст на экране: по нему слой правки ставит рамки поверх элементов.
    var onViewport: ((NotebookViewport) -> Void)?

    struct NotebookItemsContent: Equatable {
        var items: [NotebookItem]
        var hiddenId: UUID?
        var attachments: AttachmentStore

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.items == rhs.items && lhs.hiddenId == rhs.hiddenId && lhs.attachments.folder == rhs.attachments.folder
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NotebookCanvasView {
        let canvas = NotebookCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Рисунок ставится до делегата: иначе открытие заметки выглядело бы как правка.
        canvas.drawing = DrawingSupport.drawing(from: data)
        canvas.delegate = context.coordinator
        // На iPhone пишут пальцем. На iPad как в системе: если включено «Только Apple Pencil», палец листает.
        canvas.drawingPolicy = UIDevice.current.userInterfaceIdiom == .phone ? .anyInput : .default
        canvas.contentInsetAdjustmentBehavior = .never
        if notebook == nil {
            canvas.isScrollEnabled = false
            canvas.minimumZoomScale = 1
            canvas.maximumZoomScale = 1
            canvas.showsVerticalScrollIndicator = false
            canvas.showsHorizontalScrollIndicator = false
        } else {
            canvas.alwaysBounceVertical = true
        }
        let coordinator = context.coordinator
        coordinator.canvas = canvas
        coordinator.lastData = data
        coordinator.toolPicker.addObserver(canvas)
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.isEnabled = false
        canvas.addGestureRecognizer(tap)
        coordinator.tap = tap
        return canvas
    }

    func updateUIView(_ canvas: NotebookCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        coordinator.onVisibleSheet = onVisibleSheet
        coordinator.onTap = onTap
        coordinator.tap?.isEnabled = onTap != nil
        let wantsViewport = onViewport != nil && coordinator.onViewport == nil
        coordinator.onViewport = onViewport
        if wantsViewport {
            // Слой правки только что появился: ему сразу нужно знать, где холст.
            Task { @MainActor in coordinator.reportViewport() }
        }
        if data != coordinator.lastData {
            // Рисунок поменялся не на холсте (отмена, удаление листа): холст показывает новый.
            coordinator.isApplying = true
            canvas.drawing = DrawingSupport.drawing(from: data)
            coordinator.isApplying = false
            coordinator.lastData = data
        }
        let style: UIUserInterfaceStyle = isDark ? .dark : .light
        if canvas.overrideUserInterfaceStyle != style {
            canvas.overrideUserInterfaceStyle = style
        }
        canvas.drawingGestureRecognizer.isEnabled = isDrawingEnabled
        canvas.areaZoom = notebook == nil ? areaZoom : 1
        canvas.paper = notebook
        canvas.items = items
        canvas.isPaperDark = isDark
        coordinator.setToolPicker(visible: showsToolPicker && isDrawingEnabled)
    }

    static func dismantleUIView(_ canvas: NotebookCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
        canvas.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        weak var canvas: NotebookCanvasView?
        var lastData: Data?
        var isApplying = false
        var onChange: (Data?) -> Void = { _ in }
        var onVisibleSheet: (Int) -> Void = { _ in }
        var onTap: ((CGPoint) -> Void)?
        var onViewport: ((NotebookViewport) -> Void)?
        weak var tap: UITapGestureRecognizer?
        private var isToolPickerShown = false
        private var visibleSheet = -1

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplying else { return }
            let data = DrawingSupport.data(of: canvasView.drawing)
            guard data != lastData else { return }
            lastData = data
            onChange(data)
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let canvas, canvas.zoomScale > 0 else { return }
            let point = recognizer.location(in: canvas)
            onTap?(CGPoint(x: point.x / canvas.zoomScale, y: point.y / canvas.zoomScale))
        }

        func reportViewport() {
            guard let canvas, let onViewport, canvas.zoomScale > 0 else { return }
            let scale = canvas.zoomScale
            onViewport(NotebookViewport(
                origin: CGPoint(x: canvas.contentOffset.x / scale, y: canvas.contentOffset.y / scale),
                scale: scale
            ))
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportViewport()
            guard let canvas, let paper = canvas.paper, canvas.zoomScale > 0 else { return }
            let middle = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / canvas.zoomScale
            let index = NotebookLayout.sheetIndex(at: middle, sheets: paper.sheets)
            if index != visibleSheet {
                visibleSheet = index
                onVisibleSheet(index)
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            canvas?.setNeedsLayout()
            reportViewport()
        }

        /// Панель инструментов видна, пока холст первый отвечающий. Холст становится им
        /// в следующем кадре: в момент обновления SwiftUI его может ещё не быть в окне.
        func setToolPicker(visible: Bool) {
            guard visible != isToolPickerShown else { return }
            isToolPickerShown = visible
            Task { @MainActor [weak self] in
                guard let self, let canvas = self.canvas else { return }
                self.toolPicker.setVisible(visible, forFirstResponder: canvas)
                if visible {
                    canvas.becomeFirstResponder()
                } else if canvas.isFirstResponder {
                    canvas.resignFirstResponder()
                }
            }
        }
    }
}

/// PKCanvasView с листами бумаги под штрихами. Листы это векторные слои, а не картинки:
/// они не съедают память на длинной тетради. При увеличении линии строятся заново под масштаб,
/// поэтому остаются чёткими.
final class NotebookCanvasView: PKCanvasView {
    var paper: PencilCanvas.Notebook? {
        didSet {
            guard paper != oldValue else { return }
            setNeedsLayout()
        }
    }

    var items: PencilCanvas.NotebookItemsContent? {
        didSet {
            guard items != oldValue else { return }
            setNeedsLayout()
        }
    }

    var isPaperDark = false {
        didSet {
            guard isPaperDark != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// Масштаб области рисунка в заметке, когда холст шире области. У тетради свой, щипком.
    var areaZoom: CGFloat = 1 {
        didSet {
            guard areaZoom != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// Тексты и картинки: SwiftUI внутри холста, под штрихами. Перестраивается под масштаб,
    /// поэтому текст остаётся чётким при увеличении.
    private var itemsHost: UIHostingController<NotebookItemsLayer>?
    private var laidOutItems: (content: PencilCanvas.NotebookItemsContent, scale: CGFloat, isDark: Bool)?

    private struct SheetLayers {
        var sheet = CALayer()
        var lines = CAShapeLayer()
        var margin = CAShapeLayer()
        var dots = CAShapeLayer()
    }

    private let paperView = UIView()
    private var sheets: [SheetLayers] = []
    private var fittedWidth: CGFloat = 0
    private var laidOutScale: CGFloat = 0
    private var laidOutPaper: PencilCanvas.Notebook?

    override init(frame: CGRect) {
        super.init(frame: frame)
        paperView.isUserInteractionEnabled = false
        paperView.backgroundColor = .clear
        insertSubview(paperView, at: 0)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let paper, bounds.width > 0 else {
            paperView.isHidden = true
            if paper == nil {
                layoutArea()
            }
            return
        }
        paperView.isHidden = false
        // Лист во всю ширину экрана. Увеличить щипком можно в четыре раза.
        let fit = bounds.width / NotebookLayout.sheetWidth
        if abs(fit - fittedWidth) > 0.0001 {
            let wasFitted = fittedWidth == 0 || abs(zoomScale - fittedWidth) < 0.0001
            fittedWidth = fit
            minimumZoomScale = fit
            maximumZoomScale = fit * 4
            if wasFitted || zoomScale < fit {
                zoomScale = fit
            }
            // Снизу место под панель инструментов, чтобы последний лист можно было дописать.
            contentInset.bottom = 140
        }
        let scale = zoomScale
        let size = CGSize(
            width: NotebookLayout.sheetWidth * scale,
            height: (NotebookLayout.canvasHeight(sheets: paper.sheets) + NotebookLayout.sheetGap) * scale
        )
        if contentSize != size {
            contentSize = size
        }
        if scale != laidOutScale || paper != laidOutPaper {
            layoutSheets(paper, scale: scale, size: size)
        }
        layoutItems(scale: scale, size: size)
        sendSubviewToBack(paperView)
    }

    /// Область в заметке не прокручивается: масштаб задан снаружи, холст ровно по размеру области.
    private func layoutArea() {
        let zoom = max(areaZoom, 0.05)
        if abs(zoomScale - zoom) > 0.0001 {
            minimumZoomScale = min(minimumZoomScale, zoom)
            maximumZoomScale = max(maximumZoomScale, zoom)
            zoomScale = zoom
            minimumZoomScale = zoom
            maximumZoomScale = zoom
        }
        if contentSize != bounds.size {
            contentSize = bounds.size
        }
        if contentOffset != .zero {
            contentOffset = .zero
        }
    }

    private func layoutItems(scale: CGFloat, size: CGSize) {
        guard let items, !items.items.isEmpty || itemsHost != nil else { return }
        let layer = NotebookItemsLayer(
            items: items.items,
            viewport: NotebookViewport(origin: .zero, scale: scale),
            isDark: isPaperDark,
            attachments: items.attachments,
            hiddenId: items.hiddenId
        )
        let host: UIHostingController<NotebookItemsLayer>
        if let itemsHost {
            host = itemsHost
            if let laid = laidOutItems, laid.content == items, laid.scale == scale, laid.isDark == isPaperDark {
                if host.view.frame.size != size { host.view.frame = CGRect(origin: .zero, size: size) }
                return
            }
            host.rootView = layer
        } else {
            host = UIHostingController(rootView: layer)
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.safeAreaRegions = []
            paperView.addSubview(host.view)
            itemsHost = host
        }
        host.view.frame = CGRect(origin: .zero, size: size)
        laidOutItems = (items, scale, isPaperDark)
    }

    private func layoutSheets(_ paper: PencilCanvas.Notebook, scale: CGFloat, size: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        paperView.frame = CGRect(origin: .zero, size: size)
        while sheets.count > paper.sheets {
            sheets.removeLast().sheet.removeFromSuperlayer()
        }
        while sheets.count < paper.sheets {
            let layers = SheetLayers()
            for shape in [layers.lines, layers.margin, layers.dots] {
                shape.lineWidth = PaperGeometry.lineWidth
                layers.sheet.addSublayer(shape)
            }
            layers.sheet.cornerRadius = 6
            layers.sheet.shadowColor = UIColor.black.cgColor
            layers.sheet.shadowOpacity = 0.18
            layers.sheet.shadowRadius = 10
            layers.sheet.shadowOffset = CGSize(width: 0, height: 4)
            paperView.layer.addSublayer(layers.sheet)
            sheets.append(layers)
        }

        let colors = PaperColors(paper.tone)
        let logical = CGSize(width: NotebookLayout.sheetWidth, height: NotebookLayout.sheetHeight)
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        let lines = PaperGeometry.lines(paper.pattern, size: logical).flatMap { $0.copy(using: &transform) }
        let margin = PaperGeometry.margin(paper.pattern, size: logical).flatMap { $0.copy(using: &transform) }
        let dots = PaperGeometry.dots(paper.pattern, size: logical).flatMap { $0.copy(using: &transform) }
        let bounds = CGRect(origin: .zero, size: logical.applying(transform))
        let shadow = UIBezierPath(roundedRect: bounds, cornerRadius: 6).cgPath
        let displayScale = max(traitCollection.displayScale, 1)

        for (index, layers) in sheets.enumerated() {
            layers.sheet.frame = NotebookLayout.sheetRect(index).applying(transform)
            layers.sheet.backgroundColor = colors.paper
            layers.sheet.shadowPath = shadow
            for shape in [layers.lines, layers.margin, layers.dots] {
                shape.frame = bounds
                shape.contentsScale = displayScale
            }
            layers.lines.path = lines
            layers.lines.strokeColor = colors.line
            layers.lines.fillColor = nil
            layers.margin.path = margin
            layers.margin.strokeColor = colors.margin
            layers.margin.fillColor = nil
            layers.dots.path = dots
            layers.dots.fillColor = colors.line
            layers.dots.strokeColor = nil
        }
        laidOutScale = scale
        laidOutPaper = paper
    }
}
#endif
