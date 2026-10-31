import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

// MARK: - Список на iPhone

extension LibraryView {
    /// На узком экране iPhone свободный холст неудобен: его не прокрутить, не задев плитки,
    /// и в ширину помещаются две-три плитки. Там библиотека это обычный список: папки, книги, заметки.
    /// Места на холсте при этом не меняются, на Mac и iPad всё лежит, где лежало.
    var usesList: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// Переименование в списке идёт через окно с полем: поля прямо в строке на телефоне мелкие.
    var isRenamingInList: Binding<Bool> {
        Binding(
            get: { usesList && renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    var compactAddMenu: some View {
        Menu {
            Button(action: newPage) {
                Label("Заметка", systemImage: "doc.badge.plus")
            }
            Button {
                isImporting = true
            } label: {
                Label("Книга или файл", systemImage: "book.closed")
            }
            Button(action: newFolder) {
                Label("Папка", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Добавить", systemImage: "plus")
        }
        .disabled(snapshot.isMissing)
    }

    /// Корзина и «Данные и копии»: на Mac они в сайдбаре, на iPhone в меню корня библиотеки.
    var compactMoreMenu: some View {
        Menu {
            if let onOpenTrash {
                Button(action: onOpenTrash) {
                    Label(trashCount > 0 ? "Корзина (\(trashCount))" : "Корзина", systemImage: "trash")
                }
            }
            Button {
                isSyncInfoPresented = true
            } label: {
                Label("Данные и копии", systemImage: "externaldrive")
            }
        } label: {
            Label("Ещё", systemImage: "ellipsis.circle")
        }
    }

    func observeFavorites() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                favorites = value.favorites
                trashCount = value.trashCount
            }
        } catch {
            lumenLog.error("Favorites observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    var compactList: some View {
        List {
            if folderId == nil && !favorites.isEmpty {
                Section("Избранное") {
                    ForEach(favorites) { page in
                        Button {
                            LumenSounds.play(.navigate)
                            onOpenPage(page.id)
                        } label: {
                            CompactLibraryRow(title: page.displayTitle, caption: "") {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        .swipeActions {
                            Button {
                                Task {
                                    await NoticeCenter.shared.attempt("Не удалось изменить избранное") {
                                        try await database.setFavorite(page.id, false)
                                    }
                                }
                            } label: {
                                Label("Убрать из избранного", systemImage: "star.slash")
                            }
                        }
                    }
                }
            }
            if !snapshot.folders.isEmpty {
                Section("Папки") {
                    ForEach(snapshot.folders) { entry in
                        Button {
                            LumenSounds.play(.navigate)
                            onOpenFolder(entry.id)
                        } label: {
                            CompactLibraryRow(title: entry.folder.displayName, caption: entry.itemCount.objectCountText) {
                                FolderGlyph(color: entry.folder.color)
                                    .scaleEffect(1.8)
                            }
                        }
                        .contextMenu { folderMenu(entry.folder) }
                        .swipeActions {
                            Button(role: .destructive) {
                                NoticeCenter.shared.moveToTrash(.folder(entry.id), in: database)
                            } label: {
                                Label("В корзину", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            if !snapshot.sources.isEmpty {
                Section("Книги и файлы") {
                    ForEach(snapshot.sources) { entry in
                        Button {
                            openSource(entry.id)
                        } label: {
                            CompactLibraryRow(title: entry.source.displayTitle, caption: caption(for: entry)) {
                                SourceCoverArt(source: entry.source, attachments: database.attachments, width: 40, height: 56)
                            }
                        }
                        .contextMenu { sourceMenu(entry.source) }
                        .swipeActions {
                            Button(role: .destructive) {
                                NoticeCenter.shared.moveToTrash(.source(entry.id), in: database)
                            } label: {
                                Label("В корзину", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            if !snapshot.pages.isEmpty {
                Section("Заметки") {
                    ForEach(snapshot.pages) { entry in
                        Button {
                            LumenSounds.play(.navigate)
                            onOpenPage(entry.id)
                        } label: {
                            CompactLibraryRow(title: entry.page.displayTitle, caption: caption(for: entry)) {
                                if let icon = entry.page.icon, !icon.isEmpty {
                                    Text(icon).font(.title3)
                                } else {
                                    Image(systemName: "doc.text")
                                        .font(.title3)
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                        }
                        .contextMenu { pageMenu(entry) }
                        .swipeActions {
                            Button(role: .destructive) {
                                NoticeCenter.shared.moveToTrash(.page(entry.id), in: database)
                            } label: {
                                Label("В корзину", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task {
                                    await NoticeCenter.shared.attempt("Не удалось изменить избранное") {
                                        try await database.setFavorite(entry.id, !entry.page.isFavorite)
                                    }
                                }
                            } label: {
                                Label(entry.page.isFavorite ? "Убрать из избранного" : "В избранное", systemImage: "star")
                            }
                            .tint(theme.accent)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if hasLoaded && snapshot.folders.isEmpty && snapshot.pages.isEmpty && snapshot.sources.isEmpty && importingCount == 0 {
                ContentUnavailableView {
                    Label("Пока пусто", systemImage: "folder")
                } description: {
                    Text("Создайте папку или заметку, или добавьте книгу из «Файлов».")
                } actions: {
                    Button("Новая папка", action: newFolder)
                        .buttonStyle(.borderedProminent)
                    Button("Добавить книгу") { isImporting = true }
                        .buttonStyle(.bordered)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if importingCount > 0 {
                Label {
                    Text(importingCount == 1 ? "Добавляю книгу…" : "Добавляю файлы: \(importingCount)…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 16)
            }
        }
    }
}

/// Строка списка библиотеки на iPhone: значок, название и подпись.
private struct CompactLibraryRow<Icon: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var icon: () -> Icon
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 42)
                .frame(minHeight: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
