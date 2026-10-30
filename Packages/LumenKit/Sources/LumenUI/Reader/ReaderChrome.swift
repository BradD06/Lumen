import LumenReader
import LumenThemes
import SwiftUI

/// Мягкие цвета и формы читалки: скруглённые листы, пастельные акценты.
enum ReaderStyle {
    static let peach = Color(hex: 0xFFB59A)
    static let peachDeep = Color(hex: 0xF59482)
    static let lilac = Color(hex: 0xCBB2F2)
    /// Тёмно-сливовый ink для текста на кнопке-персике.
    static let onPeach = Color(hex: 0x3A1C22)

    static let sheetRadius: CGFloat = 32
    static let cardRadius: CGFloat = 28
    static let gap: CGFloat = 14
    /// Фон PDF совпадает с цветом, который задаёт PDFReader.
    static let pdfSheet = Color(red: 0.13, green: 0.09, blue: 0.12)

    static var peachGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xFFC6A6), peachDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension ReaderAppearance.Palette {
    /// Цвета листа книги сверху вниз.
    var sheetColors: [Color] {
        switch self {
        case .night: [Color(hex: 0x2B1E31), Color(hex: 0x33243A)]
        case .paper: [Color(hex: 0xF4EADB), Color(hex: 0xF4EADB)]
        case .dawn: [Color(hex: 0xFBE6DA), Color(hex: 0xFBE6DA)]
        case .original: [.white, .white]
        }
    }

    /// Цвет текста на листе: им же рисуются прогресс и подписи поверх книги.
    var ink: Color {
        switch self {
        case .night: Color(hex: 0xF3E3DA)
        case .paper: Color(hex: 0x4A3A30)
        case .dawn: Color(hex: 0x5B3B3E)
        case .original: Color(hex: 0x2A2226)
        }
    }

    var isDark: Bool { self == .night }
}

// MARK: - Карточки

extension View {
    /// Стеклянная карточка: заметки и содержание рядом с книгой.
    func readerGlassCard(_ theme: Theme, radius: CGFloat = ReaderStyle.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(theme.cardFill.opacity(0.45), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            ))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
    }

    /// Лист книги: свой цвет, большое скругление и мягкая тень.
    func readerSheet(_ colors: [Color], radius: CGFloat = ReaderStyle.sheetRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
    }
}

// MARK: - Прогресс

/// Мягкая дорожка прогресса с точками глав.
struct SoftProgressTrack: View {
    let progress: Double
    var marks: Int = 0
    let ink: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.12))
                if marks > 1 {
                    ForEach(1..<marks, id: \.self) { index in
                        Circle()
                            .fill(ink.opacity(0.35))
                            .frame(width: 4, height: 4)
                            .position(x: width * CGFloat(index) / CGFloat(marks), y: geometry.size.height / 2)
                    }
                }
                Capsule()
                    .fill(LinearGradient(colors: [ReaderStyle.peach, ReaderStyle.peachDeep], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(width * min(max(progress, 0), 1), 8))
                    .shadow(color: ReaderStyle.peachDeep.opacity(0.6), radius: 6)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Прочитано")
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}

/// Кольцо прогресса для нижней панели на iPhone.
struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(ReaderStyle.peach, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
        }
        .frame(width: 42, height: 42)
        .accessibilityElement()
        .accessibilityLabel("Прочитано")
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}

// MARK: - Кнопки

/// Круглая кнопка-иконка на стекле.
struct ReaderRoundButtonStyle: ButtonStyle {
    var size: CGFloat = 36
    var isOn = false
    var tint: Color = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isOn ? ReaderStyle.peach : tint)
            .frame(width: size, height: size)
            .background(Circle().fill(isOn ? ReaderStyle.peach.opacity(0.2) : Color.white.opacity(0.0001)))
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Оформление

/// Тема страницы, размер и шрифт текста. На iPhone открывается шторкой, на Mac и iPad поповером.
struct ReaderAppearancePanel: View {
    @Binding var paletteRaw: String
    @Binding var fontSize: Int
    @Binding var typefaceRaw: String
    @Environment(\.lumenTheme) private var theme

    private let palettes: [ReaderAppearance.Palette] = [.night, .paper, .dawn, .original]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            caption("Тема страницы")
            HStack(spacing: 10) {
                ForEach(palettes) { palette in
                    themeTile(palette)
                }
            }
            caption("Размер")
            HStack(spacing: 12) {
                Text("А").font(.system(size: 13, design: .serif))
                Slider(
                    value: Binding(
                        get: { Double(fontSize) },
                        set: { fontSize = Int($0.rounded()) }
                    ),
                    in: Double(ReaderAppearance.fontSizes.lowerBound)...Double(ReaderAppearance.fontSizes.upperBound),
                    step: 1
                )
                .tint(ReaderStyle.peach)
                Text("А").font(.system(size: 21, design: .serif))
            }
            .foregroundStyle(theme.textPrimary)
            HStack(spacing: 8) {
                ForEach(ReaderAppearance.Typeface.allCases) { typeface in
                    let isOn = typeface.rawValue == typefaceRaw
                    Button {
                        typefaceRaw = typeface.rawValue
                    } label: {
                        Text(typeface.title)
                            .font(.system(size: 13, weight: .bold, design: typeface.design))
                            .lineLimit(1)
                            .foregroundStyle(isOn ? ReaderStyle.peach : theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                (isOn ? ReaderStyle.peach.opacity(0.2) : Color.white.opacity(0.07)),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        .fontDesign(.rounded)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(theme.textSecondary)
    }

    private func themeTile(_ palette: ReaderAppearance.Palette) -> some View {
        let isOn = palette.rawValue == paletteRaw
        return Button {
            paletteRaw = palette.rawValue
        } label: {
            VStack(spacing: 7) {
                Text("Аа")
                    .font(.system(size: 19, design: .serif))
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(colors: palette.sheetColors, startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isOn ? ReaderStyle.peach : Color.white.opacity(0.12), lineWidth: isOn ? 2 : 1)
                    )
                    .shadow(color: isOn ? ReaderStyle.peach.opacity(0.35) : .clear, radius: 6)
                Text(palette.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isOn ? theme.textPrimary : theme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Тема: \(palette.title)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension ReaderAppearance.Typeface {
    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        }
    }
}
