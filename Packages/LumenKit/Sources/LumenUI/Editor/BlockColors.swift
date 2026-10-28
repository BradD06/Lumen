import LumenCore
import LumenThemes
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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

/// Цветные образцы для меню «Цвет». Системное меню перекрашивает обычные значки в один цвет,
/// поэтому образец рисуется готовой картинкой, которую меню показывает как есть.
enum ColorSwatch {
    private static let size = CGSize(width: 16, height: 16)

    /// Буква «A» цветом текста в рамке.
    static func text(_ color: Color) -> Image {
        render { rect in
            let path = roundedRect(rect.insetBy(dx: 0.5, dy: 0.5))
            PlatformColor.gray.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1
            path.stroke()
            let font = PlatformFont.systemFont(ofSize: 11, weight: .bold)
            let letter = NSAttributedString(string: "A", attributes: [
                .font: font,
                .foregroundColor: PlatformColor(color),
            ])
            let letterSize = letter.size()
            letter.draw(at: CGPoint(x: rect.midX - letterSize.width / 2, y: rect.midY - letterSize.height / 2))
        }
    }

    /// Закрашенный квадратик цветом фона.
    static func fill(_ color: Color) -> Image {
        render { rect in
            PlatformColor(color).withAlphaComponent(0.75).setFill()
            roundedRect(rect.insetBy(dx: 0.5, dy: 0.5)).fill()
        }
    }

    #if canImport(UIKit)
    private typealias PlatformColor = UIColor
    private typealias PlatformFont = UIFont

    private static func roundedRect(_ rect: CGRect) -> UIBezierPath {
        UIBezierPath(roundedRect: rect, cornerRadius: 4)
    }

    private static func render(_ draw: @escaping (CGRect) -> Void) -> Image {
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            draw(CGRect(origin: .zero, size: size))
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }
    #else
    private typealias PlatformColor = NSColor
    private typealias PlatformFont = NSFont

    private static func roundedRect(_ rect: CGRect) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
    }

    private static func render(_ draw: @escaping (CGRect) -> Void) -> Image {
        let image = NSImage(size: size, flipped: true) { rect in
            draw(rect)
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image)
    }
    #endif
}
