import LumenCore
import LumenStorage
import LumenSync
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

// Синхронизация через iCloud Drive для обычного человека: одна кнопка «Включить» на виду,
// на Mac без окна выбора папки, и понятный итог, нашлись ли другие устройства.

/// Включить синхронизацию: на Mac сразу в iCloud Drive, на iPhone и iPad через окно выбора папки.
@MainActor
func turnOnSync(_ folderSync: FolderSyncController, pickFolder: () -> Void) {
    if folderSync.turnsOnInOneStep {
        Task { await folderSync.turnOnInICloudDrive() }
    } else {
        pickFolder()
    }
}

extension View {
    /// Системное окно выбора папки синхронизации. Одно на экран: два `fileImporter` рядом мешают друг другу.
    func syncFolderPicker(isPresented: Binding<Bool>, folderSync: FolderSyncController?) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            Task { await folderSync?.choose(url) }
        }
    }
}

/// Раздел «Синхронизация» в настройках и в «Данные и копии». Окно выбора папки показывает экран, на котором раздел стоит.
struct SyncSection: View {
    var pickFolder: () -> Void

    @Environment(FolderSyncController.self) private var folderSync: FolderSyncController?

    var body: some View {
        Section {
            SyncStatusRow()
            if let folderSync {
                if folderSync.isOn {
                    if let advice = folderSync.advice, !advice.isConnected {
                        SyncAdviceRow(advice: advice)
                    }
                    if let folderName = folderSync.folderName {
                        LabeledContent("Папка", value: folderName)
                    }
                    LabeledContent("Другие устройства", value: Self.devicesText(folderSync.otherDevices))
                    Button {
                        folderSync.syncNow()
                    } label: {
                        Label("Синхронизировать сейчас", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .keyHint("Синхронизировать сейчас") { folderSync.syncNow() }
                    Button(action: pickFolder) {
                        Label("Выбрать другую папку…", systemImage: "folder")
                    }
                    Button(role: .destructive) {
                        folderSync.turnOff()
                    } label: {
                        Label("Выключить синхронизацию", systemImage: "icloud.slash")
                    }
                } else {
                    Button {
                        turnOnSync(folderSync, pickFolder: pickFolder)
                    } label: {
                        Label(folderSync.turnsOnInOneStep ? "Включить синхронизацию" : "Включить синхронизацию…", systemImage: "icloud.and.arrow.up")
                    }
                    .keyHint("Включить синхронизацию") { turnOnSync(folderSync, pickFolder: pickFolder) }
                    .accessibilityIdentifier("sync-turn-on")
                    if folderSync.turnsOnInOneStep {
                        Button(action: pickFolder) {
                            Label("Выбрать другую папку…", systemImage: "folder")
                        }
                    }
                }
            }
        } header: {
            Text("Синхронизация")
        } footer: {
            if let folderSync {
                Text(Self.footer(isOn: folderSync.isOn, oneStep: folderSync.turnsOnInOneStep))
            }
        }
    }

    static func devicesText(_ devices: [FolderSyncDevice]) -> String {
        guard !devices.isEmpty else { return "пока нет" }
        return devices.map(\.name).joined(separator: ", ")
    }

    static func footer(isOn: Bool, oneStep: Bool) -> String {
        let free = "Платный аккаунт не нужен, место берётся из вашего iCloud."
        if isOn {
            return "Правки уходят через несколько секунд и приходят с других устройств каждые полминуты, пока Lumen открыт. \(free)"
        }
        if oneStep {
            return "Lumen положит правки, книги и картинки в папку «Lumen Sync» в вашем iCloud Drive. На iPhone и iPad нажмите то же самое и выберите iCloud Drive. \(free)"
        }
        return "В окне выбора откройте «iCloud Drive» и нажмите «Открыть». Lumen создаст там папку «Lumen Sync» для правок, книг и картинок. На других устройствах сделайте то же самое. \(free)"
    }
}

/// Подсказка после включения: нашлись ли другие устройства и что сделать дальше.
struct SyncAdviceRow: View {
    let advice: FolderSyncAdvice
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: advice.symbol)
                .font(.title3)
                .foregroundStyle(advice == .notInCloud ? Color.orange : theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(advice.title)
                    .foregroundStyle(theme.textPrimary)
                Text(advice.text)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension FolderSyncAdvice {
    var symbol: String {
        switch self {
        case .checking: "magnifyingglass"
        case .connected: "checkmark.icloud"
        case .waitingForOthers: "laptopcomputer.and.iphone"
        case .notInCloud: "exclamationmark.triangle"
        }
    }
}

/// Карточка на «Сегодня»: пока синхронизация выключена, предлагает включить её одной кнопкой,
/// а сразу после включения говорит, нашлись ли другие устройства. «Не сейчас» прячет её насовсем,
/// включить можно и в настройках.
struct SyncSetupCard: View {
    static let hiddenKey = "sync.setupCardHidden"

    @Environment(FolderSyncController.self) private var folderSync: FolderSyncController?
    @Environment(\.lumenTheme) private var theme
    @AppStorage(Self.hiddenKey) private var isHidden = false
    @State private var isPicking = false
    /// Включили с этой карточки: показываем итог, даже когда всё связалось.
    @State private var justTurnedOn = false

    var body: some View {
        if let folderSync, isVisible(folderSync) {
            content(folderSync)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lumenCard()
                .syncFolderPicker(isPresented: $isPicking, folderSync: folderSync)
                .accessibilityIdentifier("home-sync")
        }
    }

    private func isVisible(_ folderSync: FolderSyncController) -> Bool {
        guard folderSync.isOn, let advice = folderSync.advice else { return !isHidden }
        if justTurnedOn { return true }
        // Синхронизацию включили раньше: карточка нужна, только если она не связала устройства.
        return !isHidden && folderSync.hasSynced && !advice.isConnected
    }

    @ViewBuilder
    private func content(_ folderSync: FolderSyncController) -> some View {
        if folderSync.isOn, let advice = folderSync.advice {
            VStack(alignment: .leading, spacing: 12) {
                row(symbol: advice.symbol, title: advice.title, text: advice.text, tint: advice == .notInCloud ? .orange : theme.accent)
                HStack(spacing: 10) {
                    switch advice {
                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                    case .connected:
                        primary("Готово") { justTurnedOn = false }
                    case .waitingForOthers:
                        primary("Понятно") { finish() }
                    case .notInCloud:
                        primary("Выбрать iCloud Drive…") { isPicking = true }
                        secondary("Оставить так") { finish() }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                row(
                    symbol: "laptopcomputer.and.iphone",
                    title: "Заметки на всех ваших устройствах",
                    text: Self.offText(oneStep: folderSync.turnsOnInOneStep),
                    tint: theme.accent
                )
                HStack(spacing: 10) {
                    primary(folderSync.turnsOnInOneStep ? "Включить синхронизацию" : "Включить синхронизацию…") {
                        // Флаг ставится до включения: иначе карточка спряталась бы, не дождавшись итога.
                        justTurnedOn = true
                        turnOnSync(folderSync) { isPicking = true }
                    }
                    secondary("Не сейчас") { isHidden = true }
                }
            }
        }
    }

    private func finish() {
        justTurnedOn = false
        isHidden = true
    }

    static func offText(oneStep: Bool) -> String {
        let device = oneStep ? "этом Mac" : "этом устройстве"
        let how = oneStep
            ? "Это бесплатно и работает через ваш iCloud Drive. На iPhone и iPad потом нажмите то же самое."
            : "Это бесплатно: в окне выбора откройте «iCloud Drive» и нажмите «Открыть». На других устройствах сделайте то же самое."
        return "Сейчас заметки и книги хранятся только на \(device). Включите синхронизацию, и они появятся на iPhone, iPad и Mac. \(how)"
    }

    private func row(symbol: String, title: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(theme.contrast.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .keyHint(title, perform: action)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .keyHint(title, perform: action)
    }
}

/// Строчка под приветствием на «Сегодня»: идёт ли синхронизация и с кем. Нажатие синхронизирует сейчас.
struct SyncBadge: View {
    @Environment(SyncStatus.self) private var status: SyncStatus?
    @Environment(FolderSyncController.self) private var folderSync: FolderSyncController?
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if let folderSync, folderSync.isOn, let state = status?.state {
            Button {
                folderSync.syncNow()
            } label: {
                Label(Self.text(state, advice: folderSync.advice), systemImage: Self.symbol(state))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Self.isFailed(state) ? Color.orange : theme.textSecondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(Self.help(state))
            .accessibilityHint("Синхронизировать сейчас")
        }
    }

    static func text(_ state: SyncStatus.State, advice: FolderSyncAdvice?) -> String {
        switch state {
        case .syncing:
            return "Синхронизация…"
        case .upToDate:
            if case .connected(let devices) = advice {
                return "Синхронизировано с \(devices.joined(separator: ", "))"
            }
            return "Синхронизация включена"
        case .failed:
            return "Синхронизация не удалась, нажмите, чтобы повторить"
        case .notConfigured, .noAccount:
            return "Синхронизация выключена"
        }
    }

    static func symbol(_ state: SyncStatus.State) -> String {
        switch state {
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        case .notConfigured, .noAccount: "icloud.slash"
        }
    }

    static func isFailed(_ state: SyncStatus.State) -> Bool {
        if case .failed = state { true } else { false }
    }

    static func help(_ state: SyncStatus.State) -> String {
        if case .failed(let message) = state { return message }
        if case .upToDate(let date) = state { return "Последний раз \(date.lumenRelative). Нажмите, чтобы синхронизировать сейчас." }
        return "Нажмите, чтобы синхронизировать сейчас."
    }
}
