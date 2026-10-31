import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Действия библиотеки: сетка, новые предметы, переименование, добавление файлов.
extension LibraryView {
    // MARK: Действия

    func toggleGrid() {
        if snapToGrid {
            snapToGrid = false
            LumenSounds.play(.tap)
            return
        }
        snapToGrid = true
        LumenSounds.play(.arrange)
        // Включили сетку: раскладываем всё по ячейкам, сначала папки, потом заметки.
        var positions: [LibraryItemID: LibraryPoint?] = [:]
        for (index, item) in placedItems.enumerated() {
            positions[item.id] = LibraryLayout.cell(index, columns: columns)
        }
        withAnimation(.spring(duration: 0.4)) {
            for (id, position) in positions {
                pendingPositions[id] = position
            }
        }
        Task { try? await database.setPositions(positions) }
    }

    /// Новый предмет встаёт в первую свободную ячейку, чтобы его сразу было видно.
    private func freePosition() -> LibraryPoint {
        LibraryLayout.freeCells(count: 1, avoiding: placedItems.map(\.position), columns: columns)[0]
    }

    func newFolder() {
        let position = freePosition()
        Task {
            guard let folder = try? await database.createFolder(
                name: "Новая папка",
                parentId: folderId,
                color: (snapshot.folders.count + 1) % Folder.colorCount,
                position: position
            ) else { return }
            LumenSounds.play(.create)
            selection = .folder(folder.id)
            renameText = folder.name
            renaming = .folder(folder.id)
        }
    }

    func newPage() {
        let position = freePosition()
        Task {
            if let page = try? await database.createPage(folderId: folderId, position: position) {
                LumenSounds.play(.create)
                onOpenPage(page.id)
            }
        }
    }

    func startRename(_ item: LibraryItemID, current: String) {
        commitRename()
        selection = item
        renameText = current
        renaming = item
    }

    func commitRename() {
        guard let item = renaming else { return }
        renaming = nil
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            switch item {
            case .folder(let id): try? await database.renameFolder(id, name: name)
            case .page(let id): try? await database.renamePage(id, title: name)
            case .source(let id): try? await database.renameSource(id, title: name)
            }
        }
    }

    /// Добавляет файлы: в точку, куда их бросили, или в свободные ячейки.
    func importFiles(_ urls: [URL], at point: LibraryPoint?) {
        guard !urls.isEmpty else { return }
        var positions = LibraryLayout.freeCells(count: urls.count, avoiding: placedItems.map(\.position), columns: columns)
        if let point {
            let first = snapToGrid ? LibraryLayout.snapped(point) : point
            positions = [first] + LibraryLayout.freeCells(
                count: urls.count - 1,
                avoiding: placedItems.map(\.position) + [first],
                columns: columns
            )
        }
        importingCount += urls.count
        let folderId = folderId
        Task {
            let sources = await SourceImporter.importFiles(urls, into: database, folderId: folderId, positions: positions)
            importingCount -= urls.count
            if !sources.isEmpty {
                LumenSounds.play(.dropIntoFolder)
            }
            if sources.count == 1, let source = sources.first {
                selection = .source(source.id)
            }
        }
    }
}
