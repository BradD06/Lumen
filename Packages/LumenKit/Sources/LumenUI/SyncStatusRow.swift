import LumenSync
import LumenThemes
import SwiftUI

/// Строка о синхронизации с iCloud. Состояние кладёт в окружение приложение, см. `SyncStatus`.
/// Если его нет (превью, тесты), синхронизация считается ненастроенной.
struct SyncStatusRow: View {
    @Environment(SyncStatus.self) private var status: SyncStatus?
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let state = status?.state ?? .notConfigured
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(state))
                .font(.title3)
                .foregroundStyle(color(state))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(state))
                    .foregroundStyle(theme.textPrimary)
                Text(details(state))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ state: SyncStatus.State) -> String {
        switch state {
        case .notConfigured: "icloud.slash"
        case .noAccount: "person.crop.circle.badge.exclamationmark"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        }
    }

    private func color(_ state: SyncStatus.State) -> Color {
        switch state {
        case .upToDate, .syncing: theme.accent
        case .failed: .orange
        case .notConfigured, .noAccount: theme.textSecondary
        }
    }

    private func title(_ state: SyncStatus.State) -> String {
        switch state {
        case .notConfigured: "Синхронизация выключена"
        case .noAccount: "Нет входа в iCloud"
        case .syncing: "Синхронизация…"
        case .upToDate: "Всё синхронизировано"
        case .failed: "Не удалось синхронизировать"
        }
    }

    private func details(_ state: SyncStatus.State) -> String {
        switch state {
        case .notConfigured:
            "Заметки и книги хранятся только на этом устройстве. iCloud включится в версии с аккаунтом разработчика Apple."
        case .noAccount:
            "Войдите в iCloud в Настройках, и заметки появятся на всех ваших устройствах."
        case .syncing:
            "Заметки и книги отправляются в iCloud и приходят с других устройств."
        case .upToDate(let date):
            "Последний раз \(date.formatted(.relative(presentation: .named)))"
        case .failed(let message):
            message
        }
    }
}
