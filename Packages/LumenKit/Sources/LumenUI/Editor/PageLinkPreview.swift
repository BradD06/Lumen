import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Карточка-подсказка у ссылки на страницу: название, когда меняли и начало текста.
/// На Mac и iPad с курсором всплывает при наведении, на iPhone видна по долгому нажатию.
struct PageLinkPreview: View {
    let page: Page
    let database: AppDatabase
    /// Кнопки «Открыть» и «Открыть рядом». В превью долгого нажатия их нет:
    /// там касание карточки само открывает страницу, а действия стоят в меню под ней.
    var onOpen: (() -> Void)?
    var onOpenBeside: (() -> Void)?

    @State private var excerpt: String?
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PageLabel(page: page)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Text("изменено \(page.updatedAt.lumenRelative)")
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Group {
                if let excerpt {
                    Text(excerpt.isEmpty ? "Страница пока пустая" : excerpt)
                        .foregroundStyle(excerpt.isEmpty ? theme.textSecondary : theme.textPrimary.opacity(0.85))
                } else {
                    Text("Загружаю…")
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .font(.callout)
            .lineLimit(6)
            .fixedSize(horizontal: false, vertical: true)
            if onOpen != nil || onOpenBeside != nil {
                HStack(spacing: 8) {
                    if let onOpen {
                        chip("Открыть", systemImage: "arrow.up.right", isPrimary: true, action: onOpen)
                    }
                    if let onOpenBeside {
                        chip("Открыть рядом", systemImage: "rectangle.split.2x1", isPrimary: false, action: onOpenBeside)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(theme.menuFill)
        .task(id: page.id) { await load() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page-preview")
    }

    private func chip(_ title: String, systemImage: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(isPrimary ? theme.accent.opacity(0.3) : theme.textPrimary.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textPrimary)
    }

    private func load() async {
        let pageId = page.id
        let preview = try? await database.reader.read { db in
            try PagePreviewQuery.fetch(db, pageId: pageId)
        }
        excerpt = (preview?.excerpt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
