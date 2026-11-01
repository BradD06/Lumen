import CoreGraphics
import Foundation

/// Текст или картинка на листе рукописной заметки. Лежит под чернилами: поверх картинки
/// можно писать, как в Goodnotes. Координаты в пунктах холста тетради, как у штрихов.
public struct NotebookItem: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case image
    }

    public var id: UUID
    public var kind: Kind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Текст текстового блока.
    public var text: String
    /// Имя файла картинки во вложениях.
    public var attachment: String?
    public var fontSize: Double
    /// Цвет текста `#RRGGBB` для светлой бумаги. На тёмной чёрный показывается белым, как и чернила.
    public var color: String
    public var isBold: Bool

    public static let minSize: Double = 24
    public static let defaultFontSize: Double = 22
    public static let fontSizeRange: ClosedRange<Double> = 10...96

    public init(
        id: UUID = UUID(),
        kind: Kind,
        frame: CGRect,
        text: String = "",
        attachment: String? = nil,
        fontSize: Double = NotebookItem.defaultFontSize,
        color: String = "#141414",
        isBold: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.x = frame.minX
        self.y = frame.minY
        self.width = max(frame.width, Self.minSize)
        self.height = max(frame.height, Self.minSize)
        self.text = text
        self.attachment = attachment
        self.fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        self.color = color
        self.isBold = isBold
    }

    public var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.minX
            y = newValue.minY
            width = max(newValue.width, Self.minSize)
            height = max(newValue.height, Self.minSize)
        }
    }

    /// Пустой текстовый блок не нужен: его убирают, когда закончили править.
    public var isEmpty: Bool { kind == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, kind, x, y, width, height, text, attachment, fontSize, color, isBold
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 200
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 60
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        attachment = try container.decodeIfPresent(String.self, forKey: .attachment)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? Self.defaultFontSize
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#141414"
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
    }
}

/// Цвет `#RRGGBB` для чернил и текста: компоненты от 0 до 1.
public struct HexColor: Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public var hex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Почти чёрный: на тёмной бумаге и в тёмной теме такой цвет показывается белым.
    public var isNearBlack: Bool { red < 0.2 && green < 0.2 && blue < 0.2 }

    /// Цвет из оттенка, насыщенности и яркости (0…1).
    public init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    /// Большая палитра, как в Goodnotes: ряд серых от чёрного до белого и 12 оттенков
    /// по кругу в пяти вариантах, от насыщенных тёмных до пастельных.
    public static let palette: [[HexColor]] = {
        let grays = (0..<12).map { index in
            let value = Double(index) / 11
            return HexColor(red: value, green: value, blue: value)
        }
        let shades: [(saturation: Double, brightness: Double)] = [
            (0.95, 0.45), (0.9, 0.7), (0.85, 0.92), (0.55, 0.98), (0.28, 1),
        ]
        let rows = shades.map { shade in
            (0..<12).map { index in
                HexColor(hue: Double(index) / 12, saturation: shade.saturation, brightness: shade.brightness)
            }
        }
        return [grays] + rows
    }()
}
