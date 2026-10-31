import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Экран вместо приложения, когда база не открылась (файл повреждён или миграция упала).
/// Ничего не удаляется: старые файлы базы откладываются в папку `Backups`, а на их месте
/// появляется база из резервной копии, из автоматической копии или пустая.
public struct DatabaseRecoveryView: View {
    let error: any Error
    let onRecovered: (AppDatabase) -> Void

    @State private var automaticBackups: [AutomaticBackup] = []
    @State private var isPickingBackup = false
    @State private var isConfirmingEmpty = false
    @State private var isWorking = false
    @State private var failure: String?
    @Environment(\.lumenTheme) private var theme

    public init(error: any Error, onRecovered: @escaping (AppDatabase) -> Void) {
        self.error = error
        self.onRecovered = onRecovered
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.accent)
                Text("Не удалось открыть заметки")
                    .font(.title.bold())
                    .foregroundStyle(theme.textPrimary)
                Text("Файл с заметками не открылся. Его можно восстановить из резервной копии. Старый файл никуда не денется: Lumen отложит его в папку Backups.")
                    .foregroundStyle(theme.textSecondary)

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isPickingBackup = true
                    } label: {
                        Label("Восстановить из резервной копии…", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)

                    ForEach(automaticBackups.prefix(3)) { backup in
                        Button {
                            recover(from: backup.url, isSecurityScoped: false)
                        } label: {
                            Label(
                                "Вернуть копию: \(backup.kind.title.lowercased()), \(backup.date.formatted(date: .abbreviated, time: .shortened))",
                                systemImage: "arrow.uturn.backward"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        isConfirmingEmpty = true
                    } label: {
                        Label("Начать с пустой базы", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    #if os(macOS)
                    Button {
                        if let folder = try? AppDatabase.defaultFolder() {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                    } label: {
                        Label("Показать файлы в Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    #endif
                }
                .disabled(isWorking)

                if isWorking {
                    ProgressView("Восстанавливаю…")
                }
                if let failure {
                    Text(failure)
                        .foregroundStyle(.orange)
                }

                DisclosureGroup("Подробности ошибки") {
                    Text(String(describing: error))
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: 520)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(ThemedBackground())
        .tint(theme.accent)
        .preferredColorScheme(.dark)
        .task { automaticBackups = AppDatabase.defaultAutomaticBackups() }
        .fileImporter(isPresented: $isPickingBackup, allowedContentTypes: [.zip, .data]) { result in
            if case .success(let url) = result {
                recover(from: url, isSecurityScoped: true)
            }
        }
        .confirmationDialog("Начать с пустой базы?", isPresented: $isConfirmingEmpty, titleVisibility: .visible) {
            Button("Начать заново", role: .destructive) { recover(from: nil, isSecurityScoped: false) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Старый файл останется в папке Backups, книги и картинки останутся на месте.")
        }
    }

    private func recover(from url: URL?, isSecurityScoped: Bool) {
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            let isAccessing = isSecurityScoped && (url?.startAccessingSecurityScopedResource() ?? false)
            defer {
                if isAccessing { url?.stopAccessingSecurityScopedResource() }
            }
            do {
                let database = try await AppDatabase.recoverDefault(from: url)
                onRecovered(database)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
