import LumenCore
import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Блок кода: тёмная подложка, язык в углу и подсветка синтаксиса как в Xcode.
/// Вне редактирования поверх поля лежит подсвеченная копия того же текста тем же шрифтом.
/// Пока код набирают, на Mac цвета ставятся прямо в поле (`LiveCodeHighlighter`),
/// а на iPhone и iPad копия остаётся поверх прозрачного поля. Нажатие проходит к полю.
struct CodeBlockBody<Field: View>: View {
    let code: String
    let isEditing: Bool
    let font: Font
    @ViewBuilder let field: () -> Field

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        // Язык угадывается по тексту: один раз на сборку, а не для подписи и подсветки отдельно.
        let language = CodeLanguage.detect(code)
        return VStack(alignment: .leading, spacing: 6) {
            if language != .plain {
                Text(language.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("code-language")
            }
            field()
                .overlay(alignment: .topLeading) {
                    if !isEditing || CodePalette.overlaysWhileEditing {
                        Text(highlighted(language))
                            .font(font)
                            .fixedSize(horizontal: false, vertical: true)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .padding(12)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func highlighted(_ language: CodeLanguage) -> AttributedString {
        var result = AttributedString()
        for token in CodeHighlighter.tokens(in: code, language: language) {
            var run = AttributedString(token.text)
            run.foregroundColor = color(token.kind)
            result += run
        }
        return result
    }

    private func color(_ kind: CodeToken.Kind) -> Color {
        CodePalette.color(kind, theme: theme)
    }
}

/// Цвета подсветки кода, как в Xcode.
enum CodePalette {
    /// На iPhone и iPad поле цветной текст не показывает, поэтому подсвеченная копия
    /// лежит поверх него и при наборе. Курсор и выделение рисует само поле.
    #if os(iOS)
    static let overlaysWhileEditing = true
    #else
    static let overlaysWhileEditing = false
    #endif

    static func color(_ kind: CodeToken.Kind, theme: Theme) -> Color {
        switch kind {
        case .plain: theme.textPrimary
        case .keyword: Color(red: 0.99, green: 0.37, blue: 0.64)
        case .type: Color(red: 0.36, green: 0.85, blue: 1.0)
        case .function: Color(red: 0.40, green: 0.72, blue: 0.64)
        case .string: Color(red: 0.99, green: 0.42, blue: 0.36)
        case .number: Color(red: 0.82, green: 0.75, blue: 0.41)
        case .comment: Color(red: 0.50, green: 0.55, blue: 0.60)
        case .tag: Color(red: 0.36, green: 0.85, blue: 1.0)
        case .attribute: Color(red: 0.75, green: 0.52, blue: 0.99)
        }
    }
}

#if os(macOS)
/// Подсветка кода прямо в поле, пока его набирают (Mac). Поле SwiftUI правит текст в общем
/// редакторе окна (`NSTextView`); цвета ставятся в его текст как атрибуты и в сам блок не попадают.
@MainActor
enum LiveCodeHighlighter {
    /// Дальше подсветка при наборе выключается, чтобы не тормозить на огромных вставках.
    static let maxLength = 20_000

    static func apply(to textView: NSTextView, theme: Theme) {
        guard let storage = textView.textStorage else { return }
        let code = storage.string
        let full = NSRange(location: 0, length: (code as NSString).length)
        let base = NSColor(theme.textPrimary)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: base, range: full)
        if full.length <= maxLength {
            let language = CodeLanguage.detect(code)
            for (range, kind) in CodeHighlighter.coloredRanges(in: code, language: language) {
                let nsRange = NSRange(location: range.lowerBound, length: range.count)
                guard NSMaxRange(nsRange) <= full.length else { break }
                storage.addAttribute(.foregroundColor, value: NSColor(CodePalette.color(kind, theme: theme)), range: nsRange)
            }
        }
        storage.endEditing()
        // Новые буквы набираются обычным цветом, их тут же перекрасит следующий проход.
        textView.typingAttributes[.foregroundColor] = base
        textView.insertionPointColor = base
    }
}
#endif
