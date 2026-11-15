import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Под заголовком пустой страницы: начать со встроенного или своего шаблона.
/// Свой шаблон удаляется из меню по правой кнопке.
struct TemplateSuggestions: View {
    let model: PageEditorModel

    @State private var own: [PageTemplate] = []
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Начать с шаблона")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PageTemplate.builtIn) { template in
                        chip(template)
                    }
                    ForEach(own) { template in
                        chip(template)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await delete(template) }
                                } label: {
                                    Label("Удалить шаблон", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.vertical, 2)
            }
            .keyHintClip()
        }
        .padding(.top, 4)
        .task { await load() }
    }

    private func chip(_ template: PageTemplate) -> some View {
        Button {
            LumenSounds.play(.create)
            model.applyTemplate(template)
        } label: {
            HStack(spacing: 6) {
                Text(template.icon ?? "📄")
                Text(template.title)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.contrast.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(theme.contrast.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(template.isBuiltIn ? "Шаблон «\(template.title)»" : "Свой шаблон «\(template.title)»")
        .keyHint(template.title) { model.applyTemplate(template) }
    }

    private func load() async {
        own = (try? await model.database.pageTemplates()) ?? []
    }

    private func delete(_ template: PageTemplate) async {
        await NoticeCenter.shared.attempt("Не удалось удалить шаблон") {
            try await model.database.deletePageTemplate(template.id)
        }
        await load()
    }
}
