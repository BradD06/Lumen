import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

/// «Данные и копии»: синхронизация, резервная копия в файл и восстановление из неё.
/// Пока синхронизации нет, копия единственная защита заметок от потери телефона или ноутбука.
struct DataSafetyView: View {
    let database: AppDatabase

    @AppStorage("backup.includeFiles") private var includeFiles = true
    @AppStorage("backup.lastDate") private var lastBackupDate: Double = 0
    @State private var isWorking = false
    @State private var workTitle = ""
    /// Готовая копия во временной папке, ждёт, куда её перенесут.
    @State private var savedBackup: URL?
    @State private var isMovingBackup = false
    @State private var isPickingBackup = false
    /// Копия, которую выбрали для восстановления: перед заменой всех данных переспрашиваем.
    @State private var pendingRestore: PendingRestore?
    @State private var automaticBackups: [AutomaticBackup] = []
    @State private var message: Message?
    @Environment(\.lumenTheme) private var theme

    struct PendingRestore: Identifiable {
        var url: URL
        var title: String
        /// Файл выбран через системное окно: доступ к нему нужно открыть и потом закрыть.
        var isSecurityScoped: Bool
        var id: URL { url }
    }

    struct Message: Identifiable {
        var title: String
        var text: String
        var id: String { title + text }
    }

    var body: some View {
        List {
            Section("Синхронизация") {
                SyncStatusRow()
            }

            Section {
                Toggle("Вместе с книгами и картинками", isOn: $includeFiles)
                Button(action: saveBackup) {
                    Label("Сохранить копию…", systemImage: "externaldrive.badge.plus")
                }
                .disabled(isWorking)
                Button {
                    isPickingBackup = true
                } label: {
                    Label("Восстановить из копии…", systemImage: "clock.arrow.circlepath")
                }
                .disabled(isWorking)
                if isWorking {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(workTitle)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            } header: {
                Text("Резервная копия")
            } footer: {
                Text(backupFooter)
            }

            if !automaticBackups.isEmpty {
                Section {
                    ForEach(automaticBackups) { backup in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.kind.title)
                                Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Button("Вернуть") {
                                pendingRestore = PendingRestore(
                                    url: backup.url,
                                    title: "\(backup.kind.title.lowercased()) от \(backup.date.formatted(date: .abbreviated, time: .shortened))",
                                    isSecurityScoped: false
                                )
                            }
                            .disabled(isWorking)
                        }
                    }
                } header: {
                    Text("Автоматические копии")
                } footer: {
                    Text("Lumen сам сохраняет базу перед обновлением приложения и перед восстановлением копии. Книги и картинки в них не входят, они остаются на месте.")
                }
            }
        }
        .task { refreshAutomaticBackups() }
        .fileMover(isPresented: $isMovingBackup, file: savedBackup) { result in
            switch result {
            case .success:
                lastBackupDate = Date().timeIntervalSince1970
                message = Message(title: "Копия сохранена", text: "Храните её не на этом устройстве: в Файлах, на флешке или в облаке.")
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    message = Message(title: "Не удалось сохранить копию", text: error.localizedDescription)
                }
            }
            if let savedBackup {
                try? FileManager.default.removeItem(at: savedBackup.deletingLastPathComponent())
            }
            savedBackup = nil
        }
        .fileImporter(isPresented: $isPickingBackup, allowedContentTypes: [.zip, .data]) { result in
            if case .success(let url) = result {
                pendingRestore = PendingRestore(url: url, title: "«\(url.lastPathComponent)»", isSecurityScoped: true)
            }
        }
        .confirmationDialog(
            "Заменить все заметки содержимым копии?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { restore in
            Button("Восстановить", role: .destructive) { self.restore(restore) }
            Button("Отмена", role: .cancel) { pendingRestore = nil }
        } message: { restore in
            Text("Страницы, папки и книги станут такими, как в копии \(restore.title). То, что есть сейчас, Lumen сначала сохранит в автоматическую копию, её можно будет вернуть.")
        }
        .alert(
            message?.title ?? "",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
            presenting: message
        ) { _ in
            Button("OK", role: .cancel) { message = nil }
        } message: { message in
            Text(message.text)
        }
    }

    private var backupFooter: String {
        var text = "Копия это один zip-файл со всеми страницами, папками, книгами, выделениями и временем чтения. Сохраните его в Файлы, на флешку или в облако."
        if lastBackupDate > 0 {
            let date = Date(timeIntervalSince1970: lastBackupDate)
            text += " Последняя копия: \(date.formatted(date: .abbreviated, time: .shortened))."
        }
        return text
    }

    private func saveBackup() {
        isWorking = true
        workTitle = "Собираю копию…"
        Task {
            defer { isWorking = false }
            do {
                let backup = try await database.writeBackupToTemporaryFile(includeFiles: includeFiles)
                savedBackup = backup.url
                isMovingBackup = true
            } catch {
                message = Message(title: "Не удалось сохранить копию", text: error.localizedDescription)
            }
        }
    }

    private func restore(_ restore: PendingRestore) {
        pendingRestore = nil
        isWorking = true
        workTitle = "Восстанавливаю…"
        Task {
            defer { isWorking = false }
            let isAccessing = restore.isSecurityScoped && restore.url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { restore.url.stopAccessingSecurityScopedResource() }
            }
            do {
                let summary = try await database.restoreBackup(from: restore.url)
                LumenSounds.play(.create)
                message = Message(title: "Готово", text: Self.describe(summary))
            } catch {
                message = Message(title: "Не удалось восстановить", text: error.localizedDescription)
            }
            refreshAutomaticBackups()
        }
    }

    private func refreshAutomaticBackups() {
        automaticBackups = AppDatabase.automaticBackups(in: database.backupsFolder)
    }

    static func describe(_ summary: BackupSummary) -> String {
        "Восстановлено страниц: \(summary.pageCount), книг и файлов: \(summary.sourceCount)."
    }
}

/// Окно «Данные и копии» с кнопкой «Готово».
struct DataSafetySheet: View {
    let database: AppDatabase
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            DataSafetyView(database: database)
                .navigationTitle("Данные и копии")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово", action: onDone)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}
