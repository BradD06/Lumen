import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Окно «Переместить в…»: дерево папок, куда положить папку, заметку или книгу.
/// Папку нельзя положить в неё саму или во вложенную в неё папку, такие строки выключены.
struct MoveToFolderSheet: View {
    let database: AppDatabase
    let item: LibraryItemID
    /// Где предмет лежит сейчас.
    let currentFolderId: UUID?
    /// Заметка из «Входящих»: её ещё нет ни в одной папке, поэтому подходит любая, включая корень.
    var isFromInbox = false
    var onDone: () -> Void

    @State private var tree: [FolderNode] = []
    @State private var target: UUID??
    @Environment(\.lumenTheme) private var theme

    private struct Row: Identifiable {
        var folder: Folder
        var depth: Int
        var isBlocked: Bool

        var id: UUID { folder.id }
    }

    var body: some View {
        NavigationStack {
            List {
                rowButton(id: nil, title: "Библиотека", depth: 0, isBlocked: false) {
                    Image(systemName: "books.vertical").foregroundStyle(theme.accent)
                }
                ForEach(rows) { row in
                    rowButton(id: row.folder.id, title: row.folder.displayName, depth: row.depth + 1, isBlocked: row.isBlocked) {
                        FolderGlyph(color: row.folder.color)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle("Переместить в…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Переместить сюда", action: move)
                        .disabled(target == nil || (!isFromInbox && target == .some(currentFolderId)))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
        .task { await observe() }
    }

    private var rows: [Row] {
        var result: [Row] = []
        func walk(_ nodes: [FolderNode], depth: Int, blocked: Bool) {
            for node in nodes {
                let isBlocked = blocked || item == .folder(node.id)
                result.append(Row(folder: node.folder, depth: depth, isBlocked: isBlocked))
                walk(node.children, depth: depth + 1, blocked: isBlocked)
            }
        }
        walk(tree, depth: 0, blocked: false)
        return result
    }

    private func rowButton<Icon: View>(
        id: UUID?,
        title: String,
        depth: Int,
        isBlocked: Bool,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            target = .some(id)
        } label: {
            HStack(spacing: 10) {
                icon()
                Text(title)
                Spacer()
                if id == currentFolderId, !isFromInbox {
                    Text("сейчас здесь")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                } else if isBlocked {
                    Text(id.map { item == .folder($0) } == true ? "сама папка" : "внутри неё")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
        .opacity(isBlocked ? 0.45 : 1)
        .listRowBackground(target == .some(id) ? theme.accent.opacity(0.28) : Color.clear)
    }

    private func move() {
        guard case .some(let folderId) = target else { return }
        Task {
            let moved = await NoticeCenter.shared.attempt("Не удалось переместить") {
                switch item {
                case .folder(let id): try await database.moveFolder(id, toParent: folderId)
                case .page(let id): try await database.movePage(id, toFolder: folderId)
                case .source(let id): try await database.moveSource(id, toFolder: folderId)
                }
            }
            if moved { LumenSounds.play(.dropIntoFolder) }
            onDone()
        }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try FolderTreeQuery.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                tree = value
            }
        } catch {
            lumenLog.error("Folder tree observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}
