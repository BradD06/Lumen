import AppIntents
import LumenStorage

/// Быстрая заметка из Shortcuts, Siri и Spotlight: текст сразу попадает во «Входящие».
struct QuickNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Быстрая заметка"
    static let description = IntentDescription("Сохраняет текст во «Входящие» Lumen. Первая строка станет названием.")

    @Parameter(title: "Текст")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Записать \(\.$text) во «Входящие»")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppEnvironment.database().createQuickNote(text)
        return .result(dialog: "Заметка сохранена во «Входящие»")
    }
}

struct LumenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickNoteIntent(),
            phrases: [
                "Заметка в \(.applicationName)",
                "Новая заметка в \(.applicationName)",
            ],
            shortTitle: "Быстрая заметка",
            systemImageName: "square.and.pencil"
        )
    }
}
