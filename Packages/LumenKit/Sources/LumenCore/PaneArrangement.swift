import Foundation

/// Как стоят два окна: книга и заметка к ней или две панели разделённого экрана.
/// Рядом (слева и справа) или друг под другом (сверху и снизу), и какое из них первое.
///
/// Выбор помнится отдельно для широкого окна и для высокого: iPad, поставленный вертикально,
/// сам ставит окна друг под другом, а повёрнутый обратно снова ставит их рядом.
public struct PaneArrangement: Codable, Hashable, Sendable {
    public enum Axis: String, Codable, Hashable, Sendable, CaseIterable {
        case sideBySide
        case stacked
    }

    /// Окна в широком окне (Mac, iPad лёжа).
    public var wideAxis: Axis
    /// Окна в высоком окне (iPad стоя).
    public var tallAxis: Axis
    /// Второе окно идёт первым: заметка слева или сверху, книга справа или снизу.
    public var isSwapped: Bool
    /// Доля второго окна (заметки), когда окна рядом.
    public var sideFraction: Double
    /// Доля второго окна (заметки), когда окна друг под другом.
    public var stackedFraction: Double

    public static let sideRange: ClosedRange<Double> = 0.25...0.65
    public static let stackedRange: ClosedRange<Double> = 0.2...0.8

    public init(
        wideAxis: Axis = .sideBySide,
        tallAxis: Axis = .stacked,
        isSwapped: Bool = false,
        sideFraction: Double = 0.42,
        stackedFraction: Double = 0.55
    ) {
        self.wideAxis = wideAxis
        self.tallAxis = tallAxis
        self.isSwapped = isSwapped
        self.sideFraction = Self.clamped(sideFraction, to: Self.sideRange)
        self.stackedFraction = Self.clamped(stackedFraction, to: Self.stackedRange)
    }

    /// Высокое окно: выше, чем шире.
    public static func isTall(width: Double, height: Double) -> Bool {
        height > width
    }

    public func axis(isTall: Bool) -> Axis {
        isTall ? tallAxis : wideAxis
    }

    /// Выбор относится к окну, какое оно сейчас: широкое или высокое.
    public mutating func setAxis(_ axis: Axis, isTall: Bool) {
        if isTall { tallAxis = axis } else { wideAxis = axis }
    }

    public mutating func swap() {
        isSwapped.toggle()
    }

    public func fraction(for axis: Axis) -> Double {
        axis == .stacked ? stackedFraction : sideFraction
    }

    public static func range(for axis: Axis) -> ClosedRange<Double> {
        axis == .stacked ? stackedRange : sideRange
    }

    public mutating func setFraction(_ value: Double, for axis: Axis) {
        let value = Self.clamped(value, to: Self.range(for: axis))
        if axis == .stacked { stackedFraction = value } else { sideFraction = value }
    }

    /// Новая доля второго окна, когда ручку между окнами сдвинули на `delta` точек
    /// по оси окон при общей длине `length`. Второе окно в конце растёт, когда ручку тянут
    /// к началу, а второе окно в начале (поменяли местами) растёт, когда тянут к концу.
    public static func dragged(
        from start: Double,
        delta: Double,
        length: Double,
        axis: Axis,
        isSwapped: Bool
    ) -> Double {
        let change = delta / max(length, 1)
        return clamped(isSwapped ? start + change : start - change, to: range(for: axis))
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return (range.lowerBound + range.upperBound) / 2 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // Старые сохранения и сохранения от будущих версий читаются без ошибок: чего нет, берётся по умолчанию.
    private enum CodingKeys: String, CodingKey {
        case wideAxis, tallAxis, isSwapped, sideFraction, stackedFraction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PaneArrangement()
        self.init(
            wideAxis: (try? container.decodeIfPresent(Axis.self, forKey: .wideAxis)) ?? defaults.wideAxis,
            tallAxis: (try? container.decodeIfPresent(Axis.self, forKey: .tallAxis)) ?? defaults.tallAxis,
            isSwapped: (try? container.decodeIfPresent(Bool.self, forKey: .isSwapped)) ?? defaults.isSwapped,
            sideFraction: (try? container.decodeIfPresent(Double.self, forKey: .sideFraction)) ?? defaults.sideFraction,
            stackedFraction: (try? container.decodeIfPresent(Double.self, forKey: .stackedFraction)) ?? defaults.stackedFraction
        )
    }
}
