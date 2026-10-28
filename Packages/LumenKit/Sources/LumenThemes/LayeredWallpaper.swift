import SwiftUI

/// Палитра многослойных обоев: небо, солнце и цвета гряд от дальней к ближней.
public struct WallpaperPalette: Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// Небо сверху вниз, последний цвет у горизонта.
    var sky: [UInt32]
    var sun: UInt32
    /// Самая дальняя гряда, почти растворённая в небе.
    var far: UInt32
    /// Ближняя гряда, самая тёмная.
    var near: UInt32
    /// Туман в долинах между грядами.
    var haze: UInt32

    public static let all: [WallpaperPalette] = [
        WallpaperPalette(id: 0, name: "Закат", sky: [0x3B2740, 0x8A4A6A, 0xF29A7A], sun: 0xFFD9A8, far: 0xB07A9E, near: 0x1E1424, haze: 0xF6B49A),
        WallpaperPalette(id: 1, name: "Лаванда", sky: [0x2B2350, 0x6C5AA8, 0xD8B4E8], sun: 0xFFF0D0, far: 0x9C8AD0, near: 0x17122E, haze: 0xE6CCF2),
        WallpaperPalette(id: 2, name: "Туман", sky: [0x24323F, 0x5C7385, 0xC9D6DE], sun: 0xFFF6E5, far: 0x8FA3B3, near: 0x111A22, haze: 0xDCE6EC),
        WallpaperPalette(id: 3, name: "Лес", sky: [0x1F2B26, 0x4E6B5A, 0xE8C79A], sun: 0xFFE2A8, far: 0x7F9C84, near: 0x0E1A14, haze: 0xF0D5AA),
        WallpaperPalette(id: 4, name: "Ночь", sky: [0x070B1E, 0x1B2350, 0x4A3C7A], sun: 0xF4F1FF, far: 0x3E4780, near: 0x05060F, haze: 0x7E76C0),
    ]

    public static func palette(_ index: Int) -> WallpaperPalette {
        all[((index % all.count) + all.count) % all.count]
    }

    /// Цвет неба у горизонта: им можно подкрашивать превью.
    public var horizon: Color { Color(hex: sky.last ?? sun) }
}

/// Объёмные обои: гряды гор одна за другой, дальние светлее и прозрачнее,
/// между ними туман, по гребням контровой свет от солнца. Форма гор задаётся зерном.
public struct LayeredWallpaper: View {
    let palette: WallpaperPalette
    let layers: Int
    let hasSun: Bool
    let seed: Int

    public init(palette: Int, layers: Int, hasSun: Bool, seed: Int) {
        self.palette = .palette(palette)
        self.layers = max(layers, 1)
        self.hasSun = hasSun
        self.seed = seed
    }

    public var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let w = size.width
        let h = size.height

        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: palette.sky.map { Color(hex: $0) }),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: h * 0.72)
            )
        )

        let sunCenter = CGPoint(x: w * 0.68, y: h * 0.34)
        let sunRadius = min(w, h) * 0.085
        if hasSun {
            context.fill(
                Path(rect),
                with: .radialGradient(
                    Gradient(colors: [Color(hex: palette.sun, opacity: 0.45), Color(hex: palette.sun, opacity: 0)]),
                    center: sunCenter,
                    startRadius: sunRadius * 0.6,
                    endRadius: max(w, h) * 0.42
                )
            )
            context.fill(
                Path(ellipseIn: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: palette.sun), Color(hex: palette.haze)]),
                    startPoint: CGPoint(x: sunCenter.x, y: sunCenter.y - sunRadius),
                    endPoint: CGPoint(x: sunCenter.x, y: sunCenter.y + sunRadius)
                )
            )
        }

        for index in 0..<layers {
            // 0 это самая дальняя гряда, 1 это передний план.
            let depth = layers == 1 ? 1 : Double(index) / Double(layers - 1)
            let base = h * (0.50 + 0.40 * depth)
            let amplitude = h * (0.10 + 0.10 * depth)
            let ridge = ridgePath(width: w, height: h, base: base, amplitude: amplitude, layer: index)

            let crest = Self.mix(palette.far, palette.near, depth * 0.85)
            let foot = Self.mix(palette.far, palette.near, min(1, depth * 0.85 + 0.25))
            var layer = context
            layer.opacity = 0.72 + 0.28 * depth
            layer.fill(
                ridge.fill,
                with: .linearGradient(
                    Gradient(colors: [crest, foot]),
                    startPoint: CGPoint(x: 0, y: base - amplitude),
                    endPoint: CGPoint(x: 0, y: min(h, base + amplitude))
                )
            )
            if hasSun {
                // Контровой свет: гребни ближе к солнцу подсвечены сильнее.
                layer.stroke(
                    ridge.crest,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: palette.sun, opacity: 0.05),
                            Color(hex: palette.sun, opacity: 0.55 * (1 - depth * 0.7)),
                            Color(hex: palette.sun, opacity: 0.05),
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: 0)
                    ),
                    lineWidth: 1.5
                )
            }

            // Туман в долине перед следующей грядой придаёт глубину.
            if index < layers - 1 {
                let mistTop = base - amplitude * 0.3
                context.fill(
                    Path(CGRect(x: 0, y: mistTop, width: w, height: h - mistTop)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: palette.haze, opacity: 0),
                            Color(hex: palette.haze, opacity: 0.22 * (1 - depth)),
                            Color(hex: palette.haze, opacity: 0),
                        ]),
                        startPoint: CGPoint(x: 0, y: mistTop),
                        endPoint: CGPoint(x: 0, y: min(h, base + amplitude * 1.2))
                    )
                )
            }
        }
    }

    /// Гребень гряды из «острых» синусоид разной частоты: сумма даёт естественные пики и седловины.
    private func ridgePath(width: CGFloat, height: CGFloat, base: CGFloat, amplitude: CGFloat, layer: Int) -> (fill: Path, crest: Path) {
        var random = SeededRandom(seed: UInt64(bitPattern: Int64(seed)) &* 31 &+ UInt64(layer) &* 7919)
        // Первая волна даёт пару крупных вершин, следующие (вдвое чаще и слабее) добавляют скалистость.
        let waves = (0..<6).map { octave in
            (
                frequency: random.next(in: 0.7...1.4) * pow(2.1, Double(octave)) * .pi,
                phase: random.next(in: 0...(2 * .pi)),
                weight: pow(0.48, Double(octave))
            )
        }
        let total = waves.reduce(0) { $0 + $1.weight }

        var crest = Path()
        let step: CGFloat = 3
        var x: CGFloat = 0
        while x <= width + step {
            let u = Double(x / max(width, 1))
            var value = 0.0
            for wave in waves {
                let ridged = 1 - abs(sin(wave.frequency * u + wave.phase))
                value += wave.weight * ridged * ridged
            }
            let y = base - amplitude * CGFloat(value / total) * 1.6 + amplitude * 0.3
            if x == 0 {
                crest.move(to: CGPoint(x: x, y: y))
            } else {
                crest.addLine(to: CGPoint(x: x, y: y))
            }
            x += step
        }
        var fill = crest
        fill.addLine(to: CGPoint(x: width + step, y: height))
        fill.addLine(to: CGPoint(x: 0, y: height))
        fill.closeSubpath()
        return (fill, crest)
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) / 255 }
        let t = min(max(t, 0), 1)
        return Color(
            .sRGB,
            red: channel(a, 16) * (1 - t) + channel(b, 16) * t,
            green: channel(a, 8) * (1 - t) + channel(b, 8) * t,
            blue: channel(a, 0) * (1 - t) + channel(b, 0) * t
        )
    }
}

/// Простой детерминированный генератор SplitMix64: одни и те же горы при одном зерне.
private struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

#Preview("Обои") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(WallpaperPalette.all) { palette in
                LayeredWallpaper(palette: palette.id, layers: 5, hasSun: true, seed: 7)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding()
    }
}
