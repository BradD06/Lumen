import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Системное меню плиток на iPhone и iPad (долгое нажатие).
extension LibraryView {
    // MARK: Системное меню (iPhone и iPad)

    @ViewBuilder
    func folderMenu(_ folder: Folder) -> some View {
        Button {
            onOpenFolder(folder.id)
        } label: {
            Label("Открыть", systemImage: "folder")
        }
        Button {
            startRename(.folder(folder.id), current: folder.name)
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Picker(selection: Binding(
            get: { folder.color },
            set: { color in
                Task {
                    await NoticeCenter.shared.attempt("Не удалось поменять цвет") {
                        try await database.setFolderColor(folder.id, color: color)
                    }
                }
            }
        )) {
            ForEach(FolderPalette.names.indices, id: \.self) { index in
                Text(FolderPalette.names[index]).tag(index)
            }
        } label: {
            Label("Цвет", systemImage: "paintpalette")
        }
        Button {
            moving = .folder(folder.id)
        } label: {
            Label("Переместить в…", systemImage: "arrow.right.doc.on.clipboard")
        }
        Divider()
        Button(role: .destructive) {
            selection = nil
            NoticeCenter.shared.moveToTrash(.folder(folder.id), in: database)
        } label: {
            Label("В корзину", systemImage: "trash")
        }
    }

    @ViewBuilder
    func pageMenu(_ entry: LibraryPage) -> some View {
        let page = entry.page
        Button {
            onOpenPage(page.id)
        } label: {
            Label("Открыть", systemImage: "doc.text")
        }
        Button {
            startRename(.page(page.id), current: page.title)
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        if !entry.subpages.isEmpty {
            Menu {
                ForEach(entry.subpages) { subpage in
                    Button(subpage.displayTitle) { onOpenPage(subpage.id) }
                }
            } label: {
                Label("Подстраницы", systemImage: "doc.on.doc")
            }
        }
        Button {
            Task {
                if let subpage = await NoticeCenter.shared.perform("Не удалось создать страницу", { try await database.createPage(parentId: page.id) }) {
                    LumenSounds.play(.create)
                    onOpenPage(subpage.id)
                }
            }
        } label: {
            Label("Новая подстраница", systemImage: "doc.badge.plus")
        }
        Button {
            Task {
                await NoticeCenter.shared.attempt("Не удалось изменить избранное") {
                    try await database.setFavorite(page.id, !page.isFavorite)
                }
            }
        } label: {
            if page.isFavorite {
                Label("Убрать из избранного", systemImage: "star.slash")
            } else {
                Label("В избранное", systemImage: "star")
            }
        }
        Button {
            moving = .page(page.id)
        } label: {
            Label("Переместить в…", systemImage: "arrow.right.doc.on.clipboard")
        }
        Divider()
        Button(role: .destructive) {
            selection = nil
            NoticeCenter.shared.moveToTrash(.page(page.id), in: database)
        } label: {
            Label("В корзину", systemImage: "trash")
        }
    }

    @ViewBuilder
    func sourceMenu(_ source: Source) -> some View {
        Button {
            openSource(source.id)
        } label: {
            Label("Читать", systemImage: "book")
        }
        Button {
            openNotes(of: source.id)
        } label: {
            Label("Заметки к книге", systemImage: "note.text")
        }
        Button {
            onShowSourceInfo(source.id)
        } label: {
            Label("О книге", systemImage: "chart.bar")
        }
        Button {
            startRename(.source(source.id), current: source.displayTitle)
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Button {
            moving = .source(source.id)
        } label: {
            Label("Переместить в…", systemImage: "arrow.right.doc.on.clipboard")
        }
        Divider()
        Button(role: .destructive) {
            selection = nil
            NoticeCenter.shared.moveToTrash(.source(source.id), in: database)
        } label: {
            Label("В корзину", systemImage: "trash")
        }
    }
}
