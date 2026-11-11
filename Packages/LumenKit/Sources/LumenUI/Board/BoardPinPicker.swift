import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Окно «Приколоть…»: книги, папки и заметки, которые можно приколоть к доске.
/// Отмечаете несколько и прикалываете разом. Уже приколотое отмечено и выключено.
struct BoardPinPicker: View {
    let snapshot: BoardSnapshot
    var onPin: ([LibraryItemID]) -> Void
    var onCancel: () -> Void

    @State private var query = ""
    @State private var chosen: [LibraryItemID] = []
    @Environment(\.lumenTheme) private var theme

    private struct Entry: Identifiable {
        var item: LibraryItemID
        var title: String
        var subtitle: String?
        var systemImage: String
        var icon: String?

        var id: LibraryItemID { item }
    }

    var body: some View {
        NavigationStack {
            List {
                section("Книги", entries: books)
                section("Папки", entries: folders)
                section("Заметки и листы", entries: pages)
            }
            .keyHintClip()
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .searchable(text: $query, prompt: "Найти книгу, папку или заметку")
            .navigationTitle("Приколоть к доске")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Приколоть" : "Приколоть (\(chosen.count))") {
                        onPin(chosen)
                    }
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("board.picker.pin")
                }
            }
            .overlay {
                if books.isEmpty, folders.isEmpty, pages.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "Нечего прикалывать" : "Ничего не нашлось",
                        systemImage: "pin.slash",
                        description: Text(query.isEmpty ? "Добавьте книги или напишите заметку, и их можно будет приколоть." : "Попробуйте другое слово.")
                    )
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        .keyHintHost()
    }

    @ViewBuilder
    private func section(_ title: String, entries: [Entry]) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        let isPinned = snapshot.pinnedItems.contains(entry.item)
        let isChosen = chosen.contains(entry.item)
        return Button {
            toggle(entry.item)
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let icon = entry.icon, !icon.isEmpty {
                        Text(icon)
                    } else {
                        Image(systemName: entry.systemImage)
                            .foregroundStyle(theme.accent)
                    }
                }
                .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if isPinned {
                    Label("На доске", systemImage: "pin.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(theme.textSecondary)
                        .accessibilityLabel("Уже на доске")
                } else {
                    Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isChosen ? theme.accent : theme.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPinned)
        .opacity(isPinned ? 0.55 : 1)
        .keyHint(entry.title) { toggle(entry.item) }
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func toggle(_ item: LibraryItemID) {
        if let index = chosen.firstIndex(of: item) {
            chosen.remove(at: index)
        } else {
            chosen.append(item)
        }
        LumenSounds.play(.toggle)
    }

    private func matches(_ text: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || text.localizedCaseInsensitiveContains(needle)
    }

    private var books: [Entry] {
        snapshot.sources.values
            .filter { matches($0.displayTitle) || matches($0.author ?? "") && !query.isEmpty }
            .sorted { ($0.lastOpenedAt ?? $0.createdAt) > ($1.lastOpenedAt ?? $1.createdAt) }
            .map { Entry(item: .source($0.id), title: $0.displayTitle, subtitle: $0.author, systemImage: $0.format.symbolName) }
    }

    private var folders: [Entry] {
        snapshot.folders.values
            .filter { matches($0.displayName) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map { Entry(item: .folder($0.id), title: $0.displayName, subtitle: nil, systemImage: "folder", icon: $0.icon) }
    }

    /// Заметки без строк баз данных (задач): их слишком много, и они живут в своей таблице.
    private var pages: [Entry] {
        snapshot.pages.values
            .filter { !$0.isDatabaseRow && matches($0.displayTitle) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(300)
            .map { page in
                Entry(
                    item: .page(page.id),
                    title: page.displayTitle,
                    subtitle: page.sourceId.flatMap { snapshot.sources[$0]?.displayTitle }.map { "Заметки к книге «\($0)»" },
                    systemImage: page.isNotebook ? "pencil.and.scribble" : "doc.text",
                    icon: page.icon
                )
            }
    }
}
