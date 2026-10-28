import LumenCore
import LumenThemes
import SwiftUI

/// Оттенки цветов блоков, подобранные под тёмную тему: яркий текст и приглушённый фон.
extension BlockColor {
    var textColor: Color {
        switch self {
        case .gray: Color(hex: 0xA8A29E)
        case .brown: Color(hex: 0xC9A27E)
        case .orange: Color(hex: 0xFFA26B)
        case .yellow: Color(hex: 0xFFD66B)
        case .green: Color(hex: 0x9EDB7A)
        case .blue: Color(hex: 0x7CC4FF)
        case .purple: Color(hex: 0xC8A2FF)
        case .pink: Color(hex: 0xFF9ECF)
        case .red: Color(hex: 0xFF7F7F)
        }
    }

    var backgroundColor: Color {
        textColor.opacity(0.2)
    }
}

extension View {
    /// Фон блока, если он выбран в меню «Цвет». Цвет текста задаёт само поле.
    @ViewBuilder
    func blockBackground(_ color: BlockColor?) -> some View {
        if let background = color {
            self
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(background.backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            self
        }
    }
}
