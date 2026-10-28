import LumenCore
import LumenThemes
import SwiftUI

/// Блок кода: тёмная подложка, язык в углу и подсветка синтаксиса как в Xcode.
/// Поле ввода цветной текст не показывает, поэтому вне редактирования поверх него
/// лежит подсвеченная копия того же текста тем же шрифтом. Нажатие проходит к полю.
struct CodeBlockBody<Field: View>: View {
    let code: String
    let isEditing: Bool
    let font: Font
    @ViewBuilder let field: () -> Field

    @Environment(\.lumenTheme) private var theme

    private var language: CodeLanguage { CodeLanguage.detect(code) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if language != .plain {
                Text(language.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("code-language")
            }
            field()
                .overlay(alignment: .topLeading) {
                    if !isEditing {
                        Text(highlighted)
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

    private var highlighted: AttributedString {
        var result = AttributedString()
        for token in CodeHighlighter.tokens(in: code, language: language) {
            var run = AttributedString(token.text)
            run.foregroundColor = color(token.kind)
            result += run
        }
        return result
    }

    private func color(_ kind: CodeToken.Kind) -> Color {
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
