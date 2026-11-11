import CoreGraphics
import Foundation

/// Прямоугольник в долях страницы (0...1): x слева направо, y снизу вверх, как в PDF.
public struct PDFUnitRect: Hashable, Sendable, Codable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    /// Тот же прямоугольник в координатах страницы с рамкой `box`.
    public func absolute(in box: CGRect) -> CGRect {
        CGRect(
            x: Double(box.minX) + minX * Double(box.width),
            y: Double(box.minY) + minY * Double(box.height),
            width: width * Double(box.width),
            height: height * Double(box.height)
        )
    }
}

/// Что нашлось на одной странице: где содержимое и есть ли две колонки.
public struct PDFPageInk: Hashable, Sendable, Codable {
    /// Где на странице что-то напечатано, в долях её рамки. `nil` у пустой страницы.
    public var content: PDFUnitRect?
    /// Где проходит промежуток между двумя колонками, в долях ширины. `nil`, если колонка одна.
    public var columnSplit: Double?

    public init(content: PDFUnitRect?, columnSplit: Double? = nil) {
        self.content = content
        self.columnSplit = columnSplit
    }
}

/// Разметка всей книги: рамка и содержимое каждой страницы.
public struct PDFBookLayout: Equatable, Sendable, Codable {
    /// Рамка страницы (cropBox) в её координатах.
    public struct Page: Equatable, Sendable, Codable {
        public var box: CGRect
        public var ink: PDFPageInk

        public init(box: CGRect, ink: PDFPageInk) {
            self.box = box
            self.ink = ink
        }
    }

    public var pages: [Page]

    public init(pages: [Page]) {
        self.pages = pages
    }

    public var hasColumns: Bool { pages.contains { $0.ink.columnSplit != nil } }
}

/// Как показывать страницы PDF: без белых полей и по колонкам.
public struct PDFLayoutOptions: Hashable, Sendable {
    public var cropsMargins: Bool
    public var splitsColumns: Bool

    public init(cropsMargins: Bool = true, splitsColumns: Bool = false) {
        self.cropsMargins = cropsMargins
        self.splitsColumns = splitsColumns
    }

    public static let original = PDFLayoutOptions(cropsMargins: false, splitsColumns: false)

    var changesPages: Bool { cropsMargins || splitsColumns }
}

/// Какие куски страниц показывать и в каком порядке.
public enum PDFLayoutPlan {
    /// Для каждой страницы файла куски, которые идут на экран один под другим (в координатах страницы).
    /// Обычно кусок один: страница без полей. У страницы в две колонки два: левая колонка, потом правая.
    /// Ширина всех обычных страниц одна и та же, поэтому при одном масштабе все они ровно по ширине экрана.
    public static func pieces(for layout: PDFBookLayout, options: PDFLayoutOptions) -> [[CGRect]] {
        let crops = options.cropsMargins ? cropRects(for: layout) : layout.pages.map(\.box)
        return zip(layout.pages, crops).map { page, crop in
            guard options.splitsColumns, let split = page.ink.columnSplit else { return [crop] }
            let box = page.box
            let x = Double(box.minX) + split * Double(box.width)
            let width = Double(crop.width)
            guard x > Double(crop.minX) + width * 0.2, x < Double(crop.maxX) - width * 0.2 else { return [crop] }
            // Колонка по высоте ровно как текст на странице, даже если поля оставлены.
            var bottom = Double(crop.minY)
            var top = Double(crop.maxY)
            if let content = page.ink.content {
                let pad = Double(box.height) * verticalPad
                bottom = max(Double(box.minY) + content.minY * Double(box.height) - pad, Double(box.minY))
                top = min(Double(box.minY) + content.maxY * Double(box.height) + pad, Double(box.maxY))
            }
            let left = CGRect(x: Double(crop.minX), y: bottom, width: x - Double(crop.minX), height: top - bottom)
            let right = CGRect(x: x, y: bottom, width: Double(crop.maxX) - x, height: top - bottom)
            return [left, right]
        }
    }

    static let sidePad = 0.025
    static let verticalPad = 0.02

    /// Страницы без полей. Ширина у всех обычных страниц общая: по самой широкой из обычных
    /// (очень широкие, вроде страницы с большой таблицей, не в счёт), а левый край стоит там же, где у
    /// соседних страниц той же чётности. Так текст не прыгает и размер не меняется от страницы к странице.
    static func cropRects(for layout: PDFBookLayout) -> [CGRect] {
        let pages = layout.pages
        func contentWidth(_ page: PDFBookLayout.Page) -> Double? {
            page.ink.content.map { $0.width * Double(page.box.width) }
        }
        let widths = pages.compactMap(contentWidth).sorted()
        guard !widths.isEmpty else { return pages.map(\.box) }
        let median = widths[widths.count / 2]
        let common = widths.filter { $0 <= median * 1.25 }
        let typical = common[min(common.count - 1, Int(Double(common.count) * 0.95))]
        // Обычный левый край для чётных и нечётных страниц: у книг поля бывают зеркальными.
        // Считается только по страницам с обычным текстом, а не по коротким заголовкам.
        var lefts: [[Double]] = [[], []]
        for (index, page) in pages.enumerated() {
            guard let content = page.ink.content, let width = contentWidth(page),
                  width >= median * 0.8, width <= median * 1.25 else { continue }
            lefts[index % 2].append(content.minX * Double(page.box.width))
        }
        func usualLeft(_ parity: Int) -> Double? {
            let values = (lefts[parity].isEmpty ? lefts[1 - parity] : lefts[parity]).sorted()
            return values.isEmpty ? nil : values[values.count / 2]
        }

        return pages.enumerated().map { index, page in
            let box = page.box
            let boxMinX = Double(box.minX)
            let boxMaxX = Double(box.maxX)
            let pad = Double(box.width) * sidePad
            let width = min(typical + pad * 2, Double(box.width))
            guard let content = page.ink.content else {
                // Пустая страница: та же ширина, что у соседних, чтобы масштаб не прыгал.
                let left = max(boxMinX + (usualLeft(index % 2) ?? 0) - pad, boxMinX)
                return CGRect(x: left, y: Double(box.minY), width: width, height: Double(box.height)).intersection(box)
            }
            let contentMinX = boxMinX + content.minX * Double(box.width)
            let contentMaxX = boxMinX + content.maxX * Double(box.width)
            var minX = contentMinX - pad
            var maxX = contentMaxX + pad
            if maxX - minX < width {
                // Узкое содержимое (заголовок главы, короткие строки) ставим туда, где обычно начинается текст.
                let usual = boxMinX + (usualLeft(index % 2) ?? content.minX * Double(box.width)) - pad
                minX = min(max(usual, maxX - width), minX)
                maxX = minX + width
                if maxX > boxMaxX {
                    maxX = boxMaxX
                    minX = maxX - width
                }
                if minX < boxMinX {
                    minX = boxMinX
                    maxX = min(minX + width, boxMaxX)
                }
            }
            let padY = Double(box.height) * verticalPad
            let bottom = Double(box.minY) + content.minY * Double(box.height) - padY
            let top = Double(box.minY) + content.maxY * Double(box.height) + padY
            return CGRect(x: minX, y: bottom, width: maxX - minX, height: top - bottom).intersection(box)
        }
    }
}

/// Находит на страницах PDF поля и колонки: рисует страницу маленькой серой картинкой
/// и смотрит, где на ней тёмное. Работает и со сканами, где текста нет.
public enum PDFLayoutAnalyzer {
    /// Меняется, когда меняется способ разбора: старые результаты из кэша тогда не годятся.
    static let version = 2
    /// Длинная сторона картинки страницы в точках: хватает, чтобы увидеть промежуток между колонками.
    static let longSide = 300

    /// Разметка книги: из кэша или разбором всех страниц. Долго для больших сканов, поэтому в фоне.
    public static func layout(of file: URL, cacheKey: String) async -> PDFBookLayout? {
        let cache = cacheURL(for: cacheKey)
        if let cached = cached(at: cache) { return cached }
        let task = Task.detached(priority: .utility) { () -> PDFBookLayout? in
            guard let layout = analyze(file) else { return nil }
            if let data = try? JSONEncoder().encode(layout) {
                try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cache, options: .atomic)
            }
            return layout
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Разметка из кэша, если книгу уже разбирали. Не ждёт.
    public static func cachedLayout(cacheKey: String) -> PDFBookLayout? {
        cached(at: cacheURL(for: cacheKey))
    }

    static func cached(at url: URL) -> PDFBookLayout? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PDFBookLayout.self, from: data)
    }

    static func cacheURL(for cacheKey: String) -> URL {
        let caches = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let safeKey = (cacheKey as NSString).lastPathComponent
        return caches
            .appendingPathComponent("LumenReader", isDirectory: true)
            .appendingPathComponent("pdf-layout", isDirectory: true)
            .appendingPathComponent("\(safeKey)-v\(version).json")
    }

    static func analyze(_ file: URL) -> PDFBookLayout? {
        guard let document = CGPDFDocument(file as CFURL), document.numberOfPages > 0 else { return nil }
        var pages: [PDFBookLayout.Page] = []
        for number in 1...document.numberOfPages {
            if Task.isCancelled { return nil }
            guard let page = document.page(at: number) else {
                pages.append(PDFBookLayout.Page(box: .zero, ink: PDFPageInk(content: nil)))
                continue
            }
            let box = page.getBoxRect(.cropBox)
            // Повёрнутые страницы оставляем как есть: колонки у них идут поперёк.
            let ink = autoreleasepool { () -> PDFPageInk in
                // Страницу, которую не разобрать, показываем целиком: пустой её считать нельзя.
                guard page.rotationAngle % 360 == 0, let map = InkMap(page: page, longSide: longSide) else {
                    return PDFPageInk(content: PDFUnitRect(minX: 0, minY: 0, maxX: 1, maxY: 1))
                }
                return map.ink()
            }
            pages.append(PDFBookLayout.Page(box: box, ink: ink))
        }
        return PDFBookLayout(pages: pages)
    }
}

/// Маленькая серая картинка страницы: где тёмное.
struct InkMap {
    let width: Int
    let height: Int
    /// Сколько тёмных точек в строке левее каждого столбца: `prefix[row * (width + 1) + column]`.
    /// Так любой кусок строки считается сразу, без перебора точек.
    private let prefix: [Int32]

    /// `dark` построчно, сверху вниз.
    init(width: Int, height: Int, dark: [Bool]) {
        self.width = width
        self.height = height
        var prefix = [Int32](repeating: 0, count: (width + 1) * height)
        for row in 0..<height {
            var sum: Int32 = 0
            for column in 0..<width {
                if dark[row * width + column] { sum += 1 }
                prefix[row * (width + 1) + column + 1] = sum
            }
        }
        self.prefix = prefix
    }

    init?(page: CGPDFPage, longSide: Int) {
        let box = page.getBoxRect(.cropBox)
        guard box.width > 1, box.height > 1 else { return nil }
        let scale = CGFloat(longSide) / max(box.width, box.height)
        let width = max(Int((box.width * scale).rounded()), 8)
        let height = max(Int((box.height * scale).rounded()), 8)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .low
        context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        guard let data = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var dark = [Bool](repeating: false, count: width * height)
        // Первая строка в памяти это верх страницы.
        for row in 0..<height {
            for column in 0..<width where pixels[row * bytesPerRow + column] < 200 {
                dark[row * width + column] = true
            }
        }
        self.init(width: width, height: height, dark: dark)
    }

    /// Сколько тёмных точек в строке `row` между столбцами `columns`.
    func ink(row: Int, _ columns: Range<Int>) -> Int {
        guard !columns.isEmpty else { return 0 }
        let base = row * (width + 1)
        return Int(prefix[base + columns.upperBound] - prefix[base + columns.lowerBound])
    }

    func isDark(_ column: Int, _ row: Int) -> Bool {
        ink(row: row, column..<(column + 1)) > 0
    }

    func ink() -> PDFPageInk {
        guard let bounds = contentBounds() else { return PDFPageInk(content: nil) }
        let content = PDFUnitRect(
            minX: Double(bounds.columns.lowerBound) / Double(width),
            minY: 1 - Double(bounds.rows.upperBound + 1) / Double(height),
            maxX: Double(bounds.columns.upperBound + 1) / Double(width),
            maxY: 1 - Double(bounds.rows.lowerBound) / Double(height)
        )
        let split = columnSplit(columns: bounds.columns, rows: bounds.rows).map { Double($0) / Double(width) }
        return PDFPageInk(content: content, columnSplit: split)
    }

    /// Где содержимое: столбцы и строки картинки с краской. Одиночные точки (пыль на скане),
    /// тёмные полосы у самого края (тень от сканера) и маленькие метки в стороне от текста
    /// (водяной знак программы, которой прогнали файл, вроде «by colt» у нижнего края) не в счёт.
    func contentBounds() -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>)? {
        var rowInk = [Int](repeating: 0, count: height)
        for row in 0..<height { rowInk[row] = ink(row: row, 0..<width) }
        var rowRuns = Self.runs(rowInk, length: height)
        // Метка сверху или снизу: низкая, узкая и отделена от текста просветом.
        let lowRun = max(2, Int(Double(height) * 0.04))
        let rowGap = max(3, Int(Double(height) * 0.025))
        func isStray(_ run: ClosedRange<Int>, gap: Int) -> Bool {
            guard run.count <= lowRun, gap >= rowGap, let columns = inkedColumns(rows: run) else { return false }
            return Double(columns.count) <= Double(width) * 0.15
        }
        while rowRuns.count >= 2, let last = rowRuns.last, isStray(last, gap: last.lowerBound - rowRuns[rowRuns.count - 2].upperBound) {
            rowRuns.removeLast()
        }
        while rowRuns.count >= 2, let first = rowRuns.first, isStray(first, gap: rowRuns[1].lowerBound - first.upperBound) {
            rowRuns.removeFirst()
        }
        guard let top = rowRuns.first, let bottom = rowRuns.last else { return nil }
        let rows = top.lowerBound...bottom.upperBound

        var columnInk = [Int](repeating: 0, count: width)
        for row in rows where rowInk[row] > 0 {
            for column in 0..<width where isDark(column, row) {
                columnInk[column] += 1
            }
        }
        var columnRuns = Self.runs(columnInk, length: width)
        // Метка сбоку: узкая, низкая и отделена от текста просветом.
        let narrowRun = max(2, Int(Double(width) * 0.1))
        let columnGap = max(2, Int(Double(width) * 0.015))
        func isStrayColumn(_ run: ClosedRange<Int>, gap: Int) -> Bool {
            guard run.count <= narrowRun, gap >= columnGap, let inked = inkedRows(columns: run, within: rows) else { return false }
            return inked.count <= lowRun
        }
        while columnRuns.count >= 2, let last = columnRuns.last, isStrayColumn(last, gap: last.lowerBound - columnRuns[columnRuns.count - 2].upperBound) {
            columnRuns.removeLast()
        }
        while columnRuns.count >= 2, let first = columnRuns.first, isStrayColumn(first, gap: columnRuns[1].lowerBound - first.upperBound) {
            columnRuns.removeFirst()
        }
        guard let left = columnRuns.first, let right = columnRuns.last else { return nil }
        return (left.lowerBound...right.upperBound, rows)
    }

    /// Столбцы, где есть краска в строках `rows`.
    private func inkedColumns(rows: ClosedRange<Int>) -> ClosedRange<Int>? {
        var first: Int?
        var last: Int?
        for column in 0..<width where rows.contains(where: { isDark(column, $0) }) {
            if first == nil { first = column }
            last = column
        }
        guard let first, let last else { return nil }
        return first...last
    }

    /// Строки из `within`, где есть краска в столбцах `columns`.
    private func inkedRows(columns: ClosedRange<Int>, within: ClosedRange<Int>) -> ClosedRange<Int>? {
        let range = columns.lowerBound..<(columns.upperBound + 1)
        let inked = within.filter { ink(row: $0, range) > 0 }
        guard let first = inked.first, let last = inked.last else { return nil }
        return first...last
    }

    /// Куски строк (или столбцов) с краской подряд, без узких полос, прилипших к краю.
    static func runs(_ counts: [Int], length: Int) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for index in 0..<length {
            if counts[index] >= 2 {
                if start == nil { start = index }
            } else if let begin = start {
                runs.append(begin...(index - 1))
                start = nil
            }
        }
        if let begin = start { runs.append(begin...(length - 1)) }
        let edgeStrip = max(2, Int(Double(length) * 0.03))
        runs.removeAll { run in
            let touchesEdge = run.lowerBound == 0 || run.upperBound == length - 1
            return touchesEdge && run.count <= edgeStrip
        }
        return runs
    }

    /// Первый и последний столбец (или строка) с краской, без узких полос, прилипших к краю.
    static func span(_ counts: [Int], length: Int) -> ClosedRange<Int>? {
        let found = Self.runs(counts, length: length)
        guard let first = found.first, let last = found.last else { return nil }
        return first.lowerBound...last.upperBound
    }

    /// Ищет промежуток между двумя колонками в середине содержимого: узкую полосу, где на большей
    /// части высоты нет краски, а слева и справа от неё есть текст. Заголовок во всю ширину
    /// или широкая картинка сверху колонкам не мешают. Возвращает столбец посередине промежутка.
    func columnSplit(columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> Int? {
        let contentWidth = columns.count
        let contentHeight = rows.count
        guard contentWidth >= 40, contentHeight >= 40 else { return nil }
        let band = max(2, Int((Double(contentWidth) * 0.02).rounded()))
        let from = columns.lowerBound + Int(Double(contentWidth) * 0.3)
        let to = columns.lowerBound + Int(Double(contentWidth) * 0.7) - band
        guard from < to else { return nil }
        let tallRun = max(4, Int(Double(contentHeight) * 0.08))
        let middle = columns.lowerBound + contentWidth / 2

        var best: (column: Int, coverage: Int)?
        for start in from...to {
            let bandRange = start..<(start + band)
            let leftRange = columns.lowerBound..<start
            let rightRange = (start + band)..<(columns.upperBound + 1)
            var covered = 0
            var runLength = 0
            var leftRows = 0
            var rightRows = 0
            func closeRun() {
                // Полоса пуста долго, и текст в эти строки есть с обеих сторон, а не с одной.
                let needed = Double(runLength) * 0.25
                if runLength >= tallRun, Double(leftRows) >= needed, Double(rightRows) >= needed { covered += runLength }
                runLength = 0
                leftRows = 0
                rightRows = 0
            }
            for row in rows {
                if ink(row: row, bandRange) > 0 {
                    closeRun()
                } else {
                    runLength += 1
                    if ink(row: row, leftRange) > 0 { leftRows += 1 }
                    if ink(row: row, rightRange) > 0 { rightRows += 1 }
                }
            }
            closeRun()
            let center = start + band / 2
            if let current = best {
                if covered > current.coverage || (covered == current.coverage && abs(center - middle) < abs(current.column - middle)) {
                    best = (center, covered)
                }
            } else {
                best = (center, covered)
            }
        }
        guard let best, Double(best.coverage) >= Double(contentHeight) * 0.5 else { return nil }
        // Середина всего пустого промежутка, а не первой найденной полосы.
        func blank(_ column: Int) -> Bool {
            var inked = 0
            for row in rows where isDark(column, row) { inked += 1 }
            return Double(inked) <= Double(contentHeight) * 0.1
        }
        var left = best.column
        var right = best.column
        while left - 1 > columns.lowerBound, blank(left - 1) { left -= 1 }
        while right + 1 < columns.upperBound, blank(right + 1) { right += 1 }
        return (left + right + 1) / 2
    }
}
