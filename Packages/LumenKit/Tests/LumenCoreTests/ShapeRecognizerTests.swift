import CoreGraphics
import Foundation
import Testing
@testable import LumenCore

struct ShapeRecognizerTests {
    /// Дрожание руки: одинаковое при каждом запуске.
    private func wobble(_ index: Int, amount: CGFloat) -> CGFloat {
        amount * sin(CGFloat(index) * 1.7) * cos(CGFloat(index) * 0.37)
    }

    private func handLine(from a: CGPoint, to b: CGPoint, steps: Int = 40, wobble amount: CGFloat = 1.5) -> [CGPoint] {
        (0...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t + wobble(step, amount: amount), y: a.y + (b.y - a.y) * t + wobble(step + 7, amount: amount))
        }
    }

    private func handPolygon(_ corners: [CGPoint], stepsPerSide: Int = 25, wobble amount: CGFloat = 1.5) -> [CGPoint] {
        var points: [CGPoint] = []
        for index in corners.indices {
            let side = handLine(from: corners[index], to: corners[(index + 1) % corners.count], steps: stepsPerSide, wobble: amount)
            points += index == 0 ? side : Array(side.dropFirst())
        }
        return points
    }

    private func handEllipse(center: CGPoint, rx: CGFloat, ry: CGFloat, turns: CGFloat = 1.05, wobble amount: CGFloat = 0.04) -> [CGPoint] {
        let steps = 120
        return (0...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps) * turns * 2 * .pi
            let r = 1 + wobble(step, amount: amount)
            return CGPoint(x: center.x + rx * r * cos(t), y: center.y + ry * r * sin(t))
        }
    }

    @Test func wobblyStraightStrokeBecomesALine() throws {
        let shape = try #require(ShapeRecognizer.recognize(handLine(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 210, y: 120))))
        guard case .line(let a, let b) = shape else {
            Issue.record("ожидалась линия, а не \(shape)")
            return
        }
        #expect(abs(a.x - 10) < 4 && abs(a.y - 10) < 4)
        #expect(abs(b.x - 210) < 4 && abs(b.y - 120) < 4)
    }

    @Test func almostHorizontalLineBecomesExactlyHorizontal() throws {
        let shape = try #require(ShapeRecognizer.recognize(handLine(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 300, y: 112), wobble: 0.5)))
        guard case .line(let a, let b) = shape else {
            Issue.record("ожидалась линия")
            return
        }
        #expect(abs(a.y - b.y) < 0.001)
        #expect(abs(a.y - 106) < 2)
        #expect(abs((b.x - a.x) - 300) < 3)
    }

    @Test func roundStrokeBecomesACircle() throws {
        let shape = try #require(ShapeRecognizer.recognize(handEllipse(center: CGPoint(x: 200, y: 200), rx: 80, ry: 76)))
        guard case .ellipse(let center, let radii, let angle) = shape else {
            Issue.record("ожидался круг, а не \(shape)")
            return
        }
        #expect(abs(center.x - 200) < 6 && abs(center.y - 200) < 6)
        #expect(radii.width == radii.height)
        #expect(abs(radii.width - 78) < 8)
        #expect(angle == 0)
        #expect(shape.title == "Круг")
    }

    @Test func flatOvalBecomesAStraightEllipse() throws {
        let shape = try #require(ShapeRecognizer.recognize(handEllipse(center: CGPoint(x: 300, y: 150), rx: 140, ry: 60)))
        guard case .ellipse(_, let radii, let angle) = shape else {
            Issue.record("ожидался эллипс, а не \(shape)")
            return
        }
        #expect(angle == 0)
        #expect(radii.width > radii.height * 1.8)
        #expect(shape.title == "Эллипс")
    }

    @Test func tallOvalKeepsItsTallRadius() throws {
        let shape = try #require(ShapeRecognizer.recognize(handEllipse(center: CGPoint(x: 100, y: 300), rx: 50, ry: 130)))
        guard case .ellipse(_, let radii, let angle) = shape else {
            Issue.record("ожидался эллипс, а не \(shape)")
            return
        }
        #expect(angle == 0)
        #expect(radii.height > radii.width * 1.8)
    }

    @Test func boxBecomesAnAxisAlignedRectangle() throws {
        let corners = [CGPoint(x: 50, y: 50), CGPoint(x: 290, y: 54), CGPoint(x: 286, y: 200), CGPoint(x: 48, y: 196)]
        let shape = try #require(ShapeRecognizer.recognize(handPolygon(corners)))
        guard case .polygon(let points) = shape else {
            Issue.record("ожидался прямоугольник, а не \(shape)")
            return
        }
        #expect(points.count == 4)
        #expect(ShapeRecognizer.isRectangle(points))
        #expect(shape.title == "Прямоугольник")
        let xs = Set(points.map { ($0.x * 1000).rounded() })
        let ys = Set(points.map { ($0.y * 1000).rounded() })
        // Стороны ровно по горизонтали и вертикали: всего две разные x и две разные y.
        #expect(xs.count == 2)
        #expect(ys.count == 2)
    }

    @Test func tiltedBoxStaysTiltedButSquare() throws {
        let center = CGPoint(x: 300, y: 300)
        let turn = CGAffineTransform(rotationAngle: 30 * .pi / 180)
        let corners = [CGPoint(x: -120, y: -60), CGPoint(x: 120, y: -60), CGPoint(x: 120, y: 60), CGPoint(x: -120, y: 60)]
            .map { $0.applying(turn) }
            .map { CGPoint(x: $0.x + center.x, y: $0.y + center.y) }
        let shape = try #require(ShapeRecognizer.recognize(handPolygon(corners)))
        guard case .polygon(let points) = shape else {
            Issue.record("ожидался прямоугольник, а не \(shape)")
            return
        }
        #expect(ShapeRecognizer.isRectangle(points))
        let edge = atan2(points[1].y - points[0].y, points[1].x - points[0].x)
        let tilt = abs(edge.truncatingRemainder(dividingBy: .pi / 2))
        #expect(tilt > 0.3 && tilt < 1.3)
    }

    @Test func threeCornersBecomeATriangle() throws {
        let corners = [CGPoint(x: 150, y: 40), CGPoint(x: 260, y: 220), CGPoint(x: 40, y: 220)]
        let shape = try #require(ShapeRecognizer.recognize(handPolygon(corners)))
        guard case .polygon(let points) = shape else {
            Issue.record("ожидался треугольник, а не \(shape)")
            return
        }
        #expect(points.count == 3)
        #expect(shape.title == "Треугольник")
        for corner in corners {
            #expect(points.contains { hypot($0.x - corner.x, $0.y - corner.y) < 8 })
        }
    }

    @Test func handwritingAndScribblesAreLeftAlone() {
        // Маленькая буква.
        #expect(ShapeRecognizer.recognize(handEllipse(center: CGPoint(x: 20, y: 20), rx: 5, ry: 6)) == nil)
        // Буква «Г»: два отрезка, концы далеко друг от друга.
        let corner = handLine(from: CGPoint(x: 0, y: 200), to: CGPoint(x: 0, y: 0)) + handLine(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 150, y: 0))
        #expect(ShapeRecognizer.recognize(corner) == nil)
        // Волна.
        let wave = (0...80).map { CGPoint(x: CGFloat($0) * 4, y: 100 + 40 * sin(CGFloat($0) / 6)) }
        #expect(ShapeRecognizer.recognize(wave) == nil)
        // Туда и обратно по одной линии.
        let back = handLine(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0)) + handLine(from: CGPoint(x: 200, y: 0), to: CGPoint(x: 0, y: 4))
        #expect(ShapeRecognizer.recognize(back) == nil)
    }

    @Test func holdIsCountedFromWhenThePenStopped() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 101, y: 1), CGPoint(x: 100, y: 0)]
        let times: [TimeInterval] = [0, 0.1, 0.2, 0.5, 0.6]
        #expect(abs(ShapeRecognizer.holdDuration(points: points, times: times, end: 0.9) - 0.7) < 0.0001)
        #expect(ShapeRecognizer.holdDuration(points: points, times: times, end: 0.6) >= 0.4 - 0.0001)
        // Перо ушло сразу: держали ноль секунд.
        #expect(ShapeRecognizer.holdDuration(points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)], times: [0, 0.2], end: 0.2) == 0)
    }

    @Test func outlineHasSharpCornersAndClosesTheShape() {
        let square: RecognizedShape = .polygon([CGPoint(x: 0, y: 0), CGPoint(x: 90, y: 0), CGPoint(x: 90, y: 90), CGPoint(x: 0, y: 90)])
        let points = ShapeRecognizer.outline(of: square, spacing: 3)
        #expect(points.first == CGPoint(x: 0, y: 0))
        #expect(points.last == CGPoint(x: 0, y: 0))
        // Каждый угол повторён, чтобы сплайн штриха прошёл через него.
        #expect(points.filter { $0 == CGPoint(x: 90, y: 90) }.count == 3)
        // Стороны набраны частыми точками.
        #expect(points.count > 100)

        let circle: RecognizedShape = .ellipse(center: CGPoint(x: 50, y: 50), radii: CGSize(width: 40, height: 40), angle: 0)
        for point in ShapeRecognizer.outline(of: circle) {
            #expect(abs(hypot(point.x - 50, point.y - 50) - 40) < 0.001)
        }
    }
}
