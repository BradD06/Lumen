import LumenCore
import LumenThemes
import SwiftMath
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Формулы TeX картинкой. Вёрстку делает SwiftMath (как в TeX, шрифт Latin Modern).
/// Картинка шаблонная: цвет она берёт из `foregroundStyle`, поэтому одна подходит обеим темам.
@MainActor
enum MathRenderer {
    struct Rendered {
        let image: PlatformImage
        let size: CGSize
        /// Насколько формула уходит ниже линии строки: дробь в тексте стоит на строке, как буквы.
        let descent: CGFloat
    }

    enum Outcome {
        case image(Rendered)
        /// TeX не прочитался: сообщение SwiftMath.
        case failure(String)
    }

    private struct Key: Hashable {
        let latex: String
        let fontSize: CGFloat
        let display: Bool
    }

    private static var cache: [Key: Outcome] = [:]

    /// Формула для экрана. `display` это отдельная строка (крупные дроби и суммы), иначе формула в тексте.
    static func render(_ latex: String, fontSize: CGFloat, display: Bool) -> Outcome {
        let key = Key(latex: latex, fontSize: fontSize, display: display)
        if let cached = cache[key] { return cached }
        let outcome = make(latex, fontSize: fontSize, display: display, color: .black, template: true)
        // Память не растёт без конца: формул на странице немного, кэш просто начинается заново.
        if cache.count > 400 { cache.removeAll() }
        cache[key] = outcome
        return outcome
    }

    /// Формула для PDF: настоящий цвет, без шаблона.
    static func exportImage(_ latex: String, fontSize: CGFloat, display: Bool, color: MTColor) -> Rendered? {
        if case .image(let rendered) = make(latex, fontSize: fontSize, display: display, color: color, template: false) {
            return rendered
        }
        return nil
    }

    private static func make(_ latex: String, fontSize: CGFloat, display: Bool, color: MTColor, template: Bool) -> Outcome {
        let source = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return .failure("Пустая формула") }
        var math = MathImage(
            latex: source,
            fontSize: fontSize,
            textColor: color,
            labelMode: display ? .display : .text,
            textAlignment: .left
        )
        let (error, image, layout) = math.asImage()
        guard error == nil, let image, let layout, image.size.width > 0, image.size.height > 0 else {
            return .failure(error?.localizedDescription ?? "Формула не читается")
        }
        #if canImport(UIKit)
        let result = template ? image.withRenderingMode(.alwaysTemplate) : image
        #else
        let result = image
        result.isTemplate = template
        #endif
        return .image(Rendered(image: result, size: image.size, descent: layout.descent))
    }
}

/// Формула на экране. Если TeX не читается, виден исходник и что с ним не так.
struct MathFormula: View {
    let latex: String
    var fontSize: CGFloat = 21
    var display = true

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        switch MathRenderer.render(latex, fontSize: fontSize, display: display) {
        case .image(let rendered):
            Image(platformImage: rendered.image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                // Своего размера, а широкая формула уменьшается до ширины листа.
                .frame(maxWidth: rendered.size.width, maxHeight: rendered.size.height)
                .foregroundStyle(theme.textPrimary)
                .accessibilityLabel(Text(verbatim: latex))
        case .failure(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: latex)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

/// Блок «Формула». Пока курсор в блоке, сверху исходник TeX, под ним формула меняется на ходу.
/// Вне правки видна только формула, нажатие на неё ставит курсор в исходник.
/// Поле не убирается, а складывается в линию: так в него попадают и стрелками, и нажатием.
struct EquationBlockBody<Field: View>: View {
    let latex: String
    let isEditing: Bool
    let onTap: () -> Void
    @ViewBuilder let field: () -> Field

    @Environment(\.lumenTheme) private var theme

    private var isEmpty: Bool {
        latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isEditing ? 8 : 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "TeX")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                field()
            }
            .padding(isEditing ? 10 : 0)
            .frame(height: isEditing ? nil : 1, alignment: .top)
            .clipped()
            .opacity(isEditing ? 1 : 0)
            .allowsHitTesting(isEditing)
            .background(isEditing ? theme.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            preview
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityIdentifier("equation-preview")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var preview: some View {
        if !isEmpty {
            MathFormula(latex: latex)
        } else if isEditing {
            Text(verbatim: #"Например: x^2,  \frac{a}{b},  \sqrt{x},  \sum_{i=1}^{n} i,  \int_0^1 f(x)\,dx"#)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        } else {
            Label("Пустая формула: нажмите, чтобы написать TeX", systemImage: BlockType.equation.symbolName)
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
        }
    }
}

extension MathRenderer {
    /// Формула внутри строки текста: картинка стоит на линии строки, как буквы.
    /// Если TeX не читается, в строке остаётся исходник моноширинным шрифтом.
    static func inlineText(_ latex: String, fontSize: CGFloat) -> Text {
        switch render(latex, fontSize: fontSize, display: false) {
        case .image(let rendered):
            Text(Image(platformImage: rendered.image).renderingMode(.template))
                .baselineOffset(-rendered.descent)
        case .failure:
            Text(verbatim: latex)
                .font(.system(size: fontSize * 0.85, design: .monospaced))
        }
    }

    /// Размер формул в строке по типу блока: как у его текста.
    static func inlineSize(for type: BlockType) -> CGFloat {
        switch type {
        case .heading1: 30
        case .heading2: 24
        case .heading3: 19
        default: 17
        }
    }
}
