import CoreGraphics
import Foundation

/// Ровная фигура вместо нарисованной от руки.
public enum RecognizedShape: Equatable, Sendable {
    /// Прямая от точки до точки.
    case line(CGPoint, CGPoint)
    /// Эллипс с полуосями `radii`, повёрнутый на `angle` радиан. Круг это эллипс с равными полуосями.
    case ellipse(center: CGPoint, radii: CGSize, angle: CGFloat)
    /// Замкнутый многоугольник по вершинам: треугольник, прямоугольник, четырёхугольник, пяти- и шестиугольник.
    case polygon([CGPoint])

    public var title: String {
        switch self {
        case .line: "Линия"
        case .ellipse(_, let radii, _): abs(radii.width - radii.height) < 0.5 ? "Круг" : "Эллипс"
        case .polygon(let points):
            switch points.count {
            case 3: "Треугольник"
            case 4: ShapeRecognizer.isRectangle(points) ? "Прямоугольник" : "Четырёхугольник"
            default: "Многоугольник"
            }
        }
    }
}

/// Узнаёт в штрихе от руки линию, круг, эллипс, треугольник, прямоугольник или многоугольник,
/// как в Goodnotes. Всё в координатах рисунка, без PencilKit, поэтому проверяется тестами.
public enum ShapeRecognizer {
    /// Сколько секунд держать перо на месте в конце штриха, чтобы он стал ровной фигурой.
    public static let holdToSnap: TimeInterval = 0.5
    /// Штрихи меньше этого (в пунктах рисунка) не трогаем: это буквы и точки.
    public static let minSize: CGFloat = 16

    // MARK: Распознавание

    public static func recognize(_ raw: [CGPoint]) -> RecognizedShape? {
        let points = withoutRepeats(raw)
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        let length = pathLength(points)
        let box = bounds(of: points)
        let size = max(box.width, box.height)
        guard size >= minSize, length >= minSize else { return nil }

        // Линия: путь почти не длиннее отрезка между концами и нигде от него не уходит.
        let chord = distance(first, last)
        if chord >= length * 0.85 {
            let deviation = points.map { distance($0, toSegment: first, last) }.max() ?? 0
            if deviation <= max(3, chord * 0.06) {
                return snappedLine(first, last)
            }
        }

        guard let loop = closedLoop(points, size: size) else { return nil }
        let samples = resampled(loop, count: 96, closed: true)
        let ellipse = fitEllipse(samples)
        let corners = polygonCorners(loop, size: size)
        let polygonError = corners.count >= 3 ? meanDistance(samples, toPolygon: corners) / size : .infinity

        if let ellipse, ellipse.error < 0.06 {
            return ellipse.shape
        }
        if (3...4).contains(corners.count), polygonError < 0.05, isSolid(corners) {
            return .polygon(snappedPolygon(corners))
        }
        if let ellipse, ellipse.error < 0.1 {
            return ellipse.shape
        }
        if (5...6).contains(corners.count), polygonError < 0.04, isSolid(corners) {
            return .polygon(corners)
        }
        return nil
    }

    /// Сколько перо простояло на месте в конце штриха: от момента, когда оно пришло в конечную точку
    /// (с допуском `tolerance`), до `end`, когда штрих закончили. `times` идут вместе с `points`.
    public static func holdDuration(points: [CGPoint], times: [TimeInterval], end: TimeInterval, tolerance: CGFloat = 4) -> TimeInterval {
        guard let last = points.last, points.count == times.count, var arrived = times.last else { return 0 }
        for index in stride(from: points.count - 1, through: 0, by: -1) {
            if distance(points[index], last) > tolerance { break }
            arrived = times[index]
        }
        return max(0, end - arrived)
    }

    // MARK: Контур ровной фигуры

    /// Точки контура для штриха. Штрих PencilKit сглаживается сплайном, поэтому стороны
    /// многоугольника набраны частыми точками, а углы и концы повторены: так углы острые,
    /// а стороны прямые. Замкнутые фигуры заканчиваются в первой точке.
    public static func outline(of shape: RecognizedShape, spacing: CGFloat = 3) -> [CGPoint] {
        switch shape {
        case .line(let a, let b):
            return corner(a) + edge(a, b, spacing: spacing) + corner(b)
        case .polygon(let corners):
            guard let start = corners.first else { return [] }
            var points: [CGPoint] = []
            let closed = corners + [start]
            for index in 0..<(closed.count - 1) {
                points += corner(closed[index]) + edge(closed[index], closed[index + 1], spacing: spacing)
            }
            return points + corner(start)
        case .ellipse(let center, let radii, let angle):
            let perimeter = 2 * CGFloat.pi * sqrt((radii.width * radii.width + radii.height * radii.height) / 2)
            let count = min(max(Int(perimeter / spacing), 24), 720)
            let rotation = CGAffineTransform(rotationAngle: angle)
            var points: [CGPoint] = []
            // Немного дальше полного круга: иначе у сплайна в месте стыка остаётся щель.
            for step in 0...(count + 2) {
                let t = CGFloat(step) / CGFloat(count) * 2 * .pi
                let local = CGPoint(x: radii.width * cos(t), y: radii.height * sin(t)).applying(rotation)
                points.append(CGPoint(x: center.x + local.x, y: center.y + local.y))
            }
            return points
        }
    }

    private static func corner(_ point: CGPoint) -> [CGPoint] {
        [point, point, point]
    }

    /// Точки стороны без её концов.
    private static func edge(_ a: CGPoint, _ b: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let count = Int(distance(a, b) / max(spacing, 0.5))
        guard count > 1 else { return [] }
        return (1..<count).map { step in
            let t = CGFloat(step) / CGFloat(count)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    // MARK: Выравнивание

    /// Насколько угол линии может отличаться от горизонтали или вертикали, чтобы выровняться.
    static let axisSnap: CGFloat = 6 * .pi / 180

    /// Почти горизонтальная или вертикальная линия становится ровно такой, середина на месте.
    static func snappedLine(_ a: CGPoint, _ b: CGPoint) -> RecognizedShape {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let snapped = (angle / (.pi / 2)).rounded() * (.pi / 2)
        guard abs(angle - snapped) <= axisSnap else { return .line(a, b) }
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let half = distance(a, b) / 2
        let direction = CGPoint(x: cos(snapped).rounded(), y: sin(snapped).rounded())
        return .line(
            CGPoint(x: middle.x - direction.x * half, y: middle.y - direction.y * half),
            CGPoint(x: middle.x + direction.x * half, y: middle.y + direction.y * half)
        )
    }

    /// Четырёхугольник с почти прямыми углами становится прямоугольником. Если он почти
    /// не наклонён, его стороны ложатся ровно по горизонтали и вертикали.
    static func snappedPolygon(_ corners: [CGPoint]) -> [CGPoint] {
        guard corners.count == 4, isRectangle(corners, tolerance: 20 * .pi / 180) else { return corners }
        // Наклон по самой длинной стороне.
        var longest = (length: CGFloat(0), angle: CGFloat(0))
        for index in 0..<4 {
            let a = corners[index]
            let b = corners[(index + 1) % 4]
            let length = distance(a, b)
            if length > longest.length {
                longest = (length, atan2(b.y - a.y, b.x - a.x))
            }
        }
        var angle = longest.angle - (longest.angle / (.pi / 2)).rounded() * (.pi / 2)
        if abs(angle) <= axisSnap { angle = 0 }
        let center = centroid(corners)
        let unrotate = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: -angle)
            .translatedBy(x: -center.x, y: -center.y)
        let box = bounds(of: corners.map { $0.applying(unrotate) })
        let rotate = unrotate.inverted()
        return [
            CGPoint(x: box.minX, y: box.minY),
            CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.maxX, y: box.maxY),
            CGPoint(x: box.minX, y: box.maxY),
        ].map { $0.applying(rotate) }
    }

    /// Все четыре угла прямые с допуском `tolerance` радиан.
    public static func isRectangle(_ corners: [CGPoint], tolerance: CGFloat = 1 * .pi / 180) -> Bool {
        guard corners.count == 4 else { return false }
        for index in 0..<4 {
            let previous = corners[(index + 3) % 4]
            let point = corners[index]
            let next = corners[(index + 1) % 4]
            if abs(angle(at: point, from: previous, to: next) - .pi / 2) > tolerance { return false }
        }
        return true
    }

    // MARK: Замкнутость

    /// Замкнутая петля штриха. Если конец заехал за начало, лишний хвост отрезается.
    /// `nil`, если концы далеко друг от друга.
    static func closedLoop(_ points: [CGPoint], size: CGFloat) -> [CGPoint]? {
        guard points.count >= 8, let start = points.first else { return nil }
        // Где конец ближе всего к началу: ищем в последних 40% штриха.
        let from = Int(Double(points.count) * 0.6)
        var best = points.count - 1
        var bestDistance = CGFloat.infinity
        for index in from..<points.count {
            let gap = distance(points[index], start)
            if gap < bestDistance {
                bestDistance = gap
                best = index
            }
        }
        guard bestDistance <= size * 0.25 else { return nil }
        let loop = Array(points[0...best])
        // Петля должна обходить фигуру, а не идти туда и обратно по одной линии.
        guard pathLength(loop) >= size * 2.2 else { return nil }
        return loop
    }

    // MARK: Эллипс

    struct EllipseFit {
        var shape: RecognizedShape
        /// Среднее отклонение точек от эллипса в долях его радиуса.
        var error: CGFloat
    }

    /// Эллипс по главным осям точек. Почти круг становится кругом, почти ровный эллипс встаёт ровно.
    static func fitEllipse(_ samples: [CGPoint]) -> EllipseFit? {
        guard samples.count >= 8 else { return nil }
        let mean = centroid(samples)
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for point in samples {
            let dx = point.x - mean.x
            let dy = point.y - mean.y
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        var angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let unrotate = CGAffineTransform(rotationAngle: -angle)
        let local = samples.map { CGPoint(x: $0.x - mean.x, y: $0.y - mean.y).applying(unrotate) }
        let box = bounds(of: local)
        var radii = CGSize(width: box.width / 2, height: box.height / 2)
        guard min(radii.width, radii.height) >= minSize * 0.25 else { return nil }
        let localCenter = CGPoint(x: box.midX, y: box.midY)
        var error: CGFloat = 0
        for point in local {
            let x = (point.x - localCenter.x) / radii.width
            let y = (point.y - localCenter.y) / radii.height
            error += abs(sqrt(x * x + y * y) - 1)
        }
        error /= CGFloat(local.count)
        let shift = localCenter.applying(CGAffineTransform(rotationAngle: angle))
        let center = CGPoint(x: mean.x + shift.x, y: mean.y + shift.y)

        let ratio = radii.width / radii.height
        if ratio > 0.85, ratio < 1 / 0.85 {
            let radius = (radii.width + radii.height) / 2
            radii = CGSize(width: radius, height: radius)
            angle = 0
        } else {
            // Ось ближе к горизонтали: наклон в пределах ±45°.
            let quarter = (angle / (.pi / 2)).rounded() * (.pi / 2)
            if abs(angle - quarter) <= axisSnap * 1.5 {
                if Int((quarter / (.pi / 2)).rounded()) % 2 != 0 {
                    radii = CGSize(width: radii.height, height: radii.width)
                }
                angle = 0
            }
        }
        return EllipseFit(shape: .ellipse(center: center, radii: radii, angle: angle), error: error)
    }

    // MARK: Многоугольник

    /// Углы замкнутой петли. Начинаем с точки, дальше всех от середины: это наверняка угол.
    static func polygonCorners(_ loop: [CGPoint], size: CGFloat) -> [CGPoint] {
        let middle = centroid(loop)
        guard let startIndex = loop.indices.max(by: { distance(loop[$0], middle) < distance(loop[$1], middle) }) else { return [] }
        var ring = Array(loop[startIndex...]) + Array(loop[..<startIndex])
        ring.append(ring[0])
        var corners = simplified(ring, tolerance: max(4, size * 0.07))
        corners.removeLast()
        // Близкие углы сливаются, почти прямые «углы» на стороне пропадают.
        var changed = true
        while changed, corners.count > 3 {
            changed = false
            for index in corners.indices {
                let previous = corners[(index + corners.count - 1) % corners.count]
                let point = corners[index]
                let next = corners[(index + 1) % corners.count]
                if distance(point, next) < size * 0.12 || angle(at: point, from: previous, to: next) > 160 * .pi / 180 {
                    corners.remove(at: index)
                    changed = true
                    break
                }
            }
        }
        return corners
    }

    /// Фигура не сплющена в линию: узкая сторона хотя бы седьмая часть широкой.
    static func isSolid(_ corners: [CGPoint]) -> Bool {
        var area: CGFloat = 0
        for index in corners.indices {
            let a = corners[index]
            let b = corners[(index + 1) % corners.count]
            area += a.x * b.y - b.x * a.y
        }
        area = abs(area) / 2
        var span: CGFloat = 0
        for a in corners {
            for b in corners {
                span = max(span, distance(a, b))
            }
        }
        guard span > 0 else { return false }
        return area / (span * span) >= 0.07
    }

    /// Рамер — Дуглас — Пекер: оставляет точки, которые уходят от прямой дальше `tolerance`.
    static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var farthest = 0
        var farthestDistance: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let gap = distance(points[index], toSegment: first, last)
            if gap > farthestDistance {
                farthestDistance = gap
                farthest = index
            }
        }
        guard farthestDistance > tolerance else { return [first, last] }
        let left = simplified(Array(points[0...farthest]), tolerance: tolerance)
        let right = simplified(Array(points[farthest...]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    static func meanDistance(_ samples: [CGPoint], toPolygon corners: [CGPoint]) -> CGFloat {
        guard !samples.isEmpty, corners.count >= 2 else { return .infinity }
        var total: CGFloat = 0
        for point in samples {
            var nearest = CGFloat.infinity
            for index in corners.indices {
                nearest = min(nearest, distance(point, toSegment: corners[index], corners[(index + 1) % corners.count]))
            }
            total += nearest
        }
        return total / CGFloat(samples.count)
    }

    // MARK: Геометрия

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    static func distance(_ point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return distance(point, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// Угол при вершине `point` между направлениями на `a` и `b`, от 0 до π.
    static func angle(at point: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let u = CGPoint(x: a.x - point.x, y: a.y - point.y)
        let v = CGPoint(x: b.x - point.x, y: b.y - point.y)
        let lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
        guard lengths > 0 else { return .pi }
        return acos(min(max((u.x * v.x + u.y * v.y) / lengths, -1), 1))
    }

    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    static func withoutRepeats(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points where result.last.map({ distance($0, point) > 0.01 }) ?? true {
            result.append(point)
        }
        return result
    }

    /// `count` точек на равных расстояниях вдоль пути: частые и редкие места руки весят одинаково.
    static func resampled(_ points: [CGPoint], count: Int, closed: Bool) -> [CGPoint] {
        var path = points
        if closed, let first = points.first { path.append(first) }
        let total = pathLength(path)
        guard path.count >= 2, total > 0, count >= 2 else { return points }
        let step = total / CGFloat(closed ? count : count - 1)
        var result: [CGPoint] = [path[0]]
        var carried: CGFloat = 0
        for index in 1..<path.count {
            var a = path[index - 1]
            let b = path[index]
            var segment = distance(a, b)
            while carried + segment >= step, result.count < count {
                let t = (step - carried) / segment
                let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                result.append(point)
                a = point
                segment = distance(a, b)
                carried = 0
            }
            carried += segment
        }
        while result.count < count, let last = path.last {
            result.append(last)
        }
        return result
    }
}
