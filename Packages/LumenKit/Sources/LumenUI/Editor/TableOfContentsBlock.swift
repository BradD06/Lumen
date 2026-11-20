import LumenCore
import LumenThemes
import SwiftUI

/// Блок «Оглавление», как в Notion: заголовки страницы по порядку, с отступом по уровню.
/// Щелчок прокручивает заметку к заголовку. Список строится из блоков на лету,
/// поэтому сам меняется, когда заголовки дописывают, переносят или удаляют.
struct TableOfContentsBlock: View {
    let model: PageEditorModel

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let items = model.outline
        let top = items.map(\.level).min() ?? 1
        VStack(alignment: .leading, spacing: 1) {
            if items.isEmpty {
                Label("Оглавление появится, когда на странице будут заголовки", systemImage: BlockType.tableOfContents.symbolName)
                    .font(.callout)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(items) { item in
                    TableOfContentsRow(
                        title: item.title,
                        level: item.level,
                        indent: PageContents.indent(level: item.level, topLevel: top),
                        model: model
                    ) {
                        LumenSounds.play(.navigate)
                        model.headingScrollRequest = item.anchorId
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Оглавление")
    }
}

/// Строка оглавления. Наведение хранится здесь же: загорается только эта строка.
private struct TableOfContentsRow: View {
    let title: String
    let level: Int
    let indent: Int
    let model: PageEditorModel
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(level == 1 && indent == 0 ? Font.body.weight(.medium) : Font.body)
                .foregroundStyle(isHovered ? theme.textPrimary : theme.textSecondary)
                .underline(true, color: isHovered ? theme.accent : theme.line)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.leading, CGFloat(indent) * 20)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? theme.surface2 : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // Пока страница едет, строки под неподвижным курсором не загораются.
            if hovering, model.isScrolling { return }
            withAnimation(LumenMotion.quick) { isHovered = hovering }
        }
        .keyHint("К заголовку «\(title)»", perform: action)
        .help("Перейти к заголовку")
        .accessibilityLabel(title)
        .accessibilityHint("Прокрутить к заголовку")
    }
}
