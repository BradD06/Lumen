import LumenCore
import LumenThemes
import SwiftUI

extension HexColor {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// Как цвет выглядит на экране. На тёмном фоне чёрный пишет белым, как и у PencilKit.
    func display(isDark: Bool) -> Color {
        if isDark, isNearBlack { return Color(white: 0.94) }
        return swiftUIColor
    }

    /// Цвет из системной пипетки и колеса цветов: компоненты в sRGB.
    init?(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = resolved.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3
        else { return nil }
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

/// Кружок цвета для выбора.
struct ColorDot: View {
    let color: HexColor
    let isSelected: Bool
    var size: CGFloat = 22
    var action: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(theme.accent, lineWidth: isSelected ? 2 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Цвет \(color.hex)")
    }
}

/// Большая палитра: 72 готовых цвета сеткой и любой цвет через системное колесо и пипетку.
struct ColorPalette: View {
    let selection: HexColor
    var onSelect: (HexColor) -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(Array(HexColor.palette.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(row, id: \.self) { color in
                            Button {
                                onSelect(color)
                            } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(color.swiftUIColor)
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(
                                                selection == color ? theme.accent : .white.opacity(0.12),
                                                lineWidth: selection == color ? 2 : 0.5
                                            )
                                    }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Цвет \(color.hex)")
                        }
                    }
                }
            }
            ColorPicker(
                "Любой цвет",
                selection: Binding(
                    get: { selection.swiftUIColor },
                    set: { if let color = HexColor($0) { onSelect(color) } }
                ),
                supportsOpacity: false
            )
            .font(.subheadline)
            .foregroundStyle(theme.textPrimary)
        }
    }
}
