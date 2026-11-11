import LumenCore
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Выписка, которую тянут из книги в заметку. Свой тип, чтобы текстовые поля
    /// не вставили её простым текстом: её ловит сама заметка и вставляет выпиской со ссылкой.
    static let lumenExcerpt = UTType(exportedAs: "app.lumen.excerpt")
}

/// Выписку тянут из книги (кнопка «В заметки» под выделением) и отпускают на заметке:
/// там она встаёт выпиской со ссылкой на это место в книге.
enum ExcerptDrag {
    struct Payload: Codable, Hashable, Sendable {
        var sourceId: UUID
        /// Уже сохранённое выделение. Если его нет, выписка делается из выделенного сейчас текста.
        var highlightId: UUID?
    }

    static func itemProvider(for payload: Payload) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.lumenExcerpt.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func decode(_ data: Data?) -> Payload? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Достаёт выписку из брошенного и отдаёт её открытой книге: та сохраняет выделение
    /// и вставляет выписку в заметку `notes`. Возвращает, взялась ли заметка за бросок.
    @MainActor
    static func accept(_ providers: [NSItemProvider], into notes: PageEditorModel) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.lumenExcerpt.identifier) }) else {
            return false
        }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.lumenExcerpt.identifier) { data, _ in
            guard let payload = decode(data) else { return }
            Task { @MainActor in
                guard let reader = OpenReaders.shared.model(for: payload.sourceId) else { return }
                await reader.dropExcerpt(highlightId: payload.highlightId, into: notes)
            }
        }
        return true
    }
}

/// Так выписка выглядит, пока её тянут: вырезка из книги с цитатой и местом.
struct ExcerptDragPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("«\(text)»")
                .font(.system(size: 16, design: .serif).italic())
                .lineLimit(4)
            Label("в заметку", systemImage: "quote.opening")
                .font(.caption2.weight(.bold))
                .opacity(0.7)
        }
        .foregroundStyle(Color(hex: 0x2A2118))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Color(hex: 0xEFE4CC), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .rotationEffect(.degrees(-2))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
        .padding(12)
    }
}

/// Пока выписку держат над заметкой, заметка обведена и подсказывает, что её можно отпустить.
struct ExcerptDropHighlight: View {
    let isTargeted: Bool

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if isTargeted {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape
                .fill(theme.accent.opacity(0.10))
                .overlay(shape.strokeBorder(theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [7, 6])))
                .overlay(alignment: .bottom) {
                    Label("Отпустите, чтобы вставить выписку", systemImage: "quote.opening")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 18)
                }
                .padding(8)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
