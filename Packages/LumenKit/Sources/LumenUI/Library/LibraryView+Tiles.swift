import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

/// Плитки библиотеки и перетаскивание их по холсту.
extension LibraryView {
    // MARK: Плитки

    @ViewBuilder
    func tile(for item: PlacedItem) -> some View {
        switch item.content {
        case .folder(let entry):
            LibraryTile(
                title: entry.folder.displayName,
                caption: entry.itemCount.objectCountText,
                isSelected: selection == item.id,
                isTargeted: dropTarget == entry.id,
                isDragging: drag?.item == item.id,
                renameText: $renameText,
                isRenaming: renaming == item.id,
                onCommitRename: commitRename
            ) {
                FolderArt(color: entry.folder.color, count: entry.itemCount, isTargeted: dropTarget == entry.id)
            }
            .modifier(TileInteraction(
                onSelect: { select(item.id) },
                onOpen: {
                    LumenSounds.play(.navigate)
                    onOpenFolder(entry.id)
                },
                drag: dragGesture(for: item)
            ))
            .modifier(LibraryTileMenu(onSecondaryClick: { openContextMenu(for: item, at: $0) }) {
                folderMenu(entry.folder)
            })
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Папка \(entry.folder.displayName), \(entry.itemCount.objectCountText)")
            .accessibilityAction(named: "Открыть") { onOpenFolder(entry.id) }

        case .page(let entry):
            LibraryTile(
                title: entry.page.displayTitle,
                caption: caption(for: entry),
                isSelected: selection == item.id,
                isDragging: drag?.item == item.id,
                renameText: $renameText,
                isRenaming: renaming == item.id,
                onCommitRename: commitRename
            ) {
                PageCoverArt(preview: entry.preview, attachments: database.attachments, subpageCount: entry.subpages.count)
            }
            .modifier(TileInteraction(
                onSelect: { select(item.id) },
                onOpen: {
                    LumenSounds.play(.navigate)
                    onOpenPage(entry.id)
                },
                drag: dragGesture(for: item)
            ))
            .modifier(LibraryTileMenu(onSecondaryClick: { openContextMenu(for: item, at: $0) }) {
                pageMenu(entry)
            })
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Заметка \(entry.page.displayTitle)")
            .accessibilityAction(named: "Открыть") { onOpenPage(entry.id) }

        case .source(let entry):
            LibraryTile(
                title: entry.source.displayTitle,
                caption: caption(for: entry),
                isSelected: selection == item.id,
                isDragging: drag?.item == item.id,
                renameText: $renameText,
                isRenaming: renaming == item.id,
                onCommitRename: commitRename
            ) {
                // Полоска прогресса под обложкой, а не поверх неё: так её видно на любой картинке.
                VStack(spacing: 6) {
                    SourceCoverArt(source: entry.source, attachments: database.attachments, width: 88, height: 122)
                    ReadingProgressBar(progress: entry.source.progress)
                        .frame(width: 88)
                        .opacity(entry.source.progress > 0.005 ? 1 : 0)
                }
            }
            .modifier(TileInteraction(
                onSelect: { select(item.id) },
                onOpen: { openSource(entry.id) },
                drag: dragGesture(for: item)
            ))
            .modifier(LibraryTileMenu(onSecondaryClick: { openContextMenu(for: item, at: $0) }) {
                sourceMenu(entry.source)
            })
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.source.format.isBook ? "Книга" : "Файл") \(entry.source.displayTitle)")
            .accessibilityAction(named: "Открыть") { openSource(entry.id) }
        }
    }

    func caption(for entry: LibrarySource) -> String {
        let source = entry.source
        var parts: [String] = []
        if source.progress > 0.005 {
            parts.append("\(Int((source.progress * 100).rounded()))%")
        }
        if let author = source.author, parts.isEmpty {
            parts.append(author)
        } else {
            parts.append(source.format.label)
        }
        if entry.highlightCount > 0 {
            parts.append("выделений: \(entry.highlightCount)")
        }
        return parts.joined(separator: " · ")
    }

    func openSource(_ id: UUID) {
        LumenSounds.play(.navigate)
        onOpenSource(id)
    }

    func caption(for entry: LibraryPage) -> String {
        if !entry.subpages.isEmpty {
            return "Подстраниц: \(entry.subpages.count)"
        }
        return entry.page.updatedAt.lumenRelative
    }

    private func select(_ item: LibraryItemID) {
        if renaming != item { commitRename() }
        selection = item
    }

    // MARK: Перетаскивание

    private func dragGesture(for item: PlacedItem) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if drag?.item != item.id {
                    commitRename()
                    selection = item.id
                    drag = DragState(item: item.id, origin: item.position)
                    LumenSounds.play(.pickUp)
                }
                drag?.translation = value.translation
                if let drag {
                    dropTarget = folder(under: drag.position, excluding: item.id)
                }
            }
            .onEnded { _ in
                finishDrag()
            }
    }

    /// Папка, на которую сейчас наведён перетаскиваемый предмет (по его центру).
    private func folder(under position: LibraryPoint, excluding item: LibraryItemID) -> UUID? {
        let center = CGPoint(
            x: position.x + LibraryLayout.tileWidth / 2,
            y: position.y + LibraryLayout.tileHeight / 2
        )
        for candidate in placedItems where candidate.id != item {
            guard case .folder(let entry) = candidate.content else { continue }
            let frame = CGRect(
                x: candidate.position.x,
                y: candidate.position.y,
                width: LibraryLayout.tileWidth,
                height: LibraryLayout.tileHeight
            )
            if frame.contains(center) { return entry.id }
        }
        return nil
    }

    private func finishDrag() {
        guard let drag else { return }
        let target = dropTarget
        self.drag = nil
        dropTarget = nil
        LumenSounds.play(target == nil ? .drop : .dropIntoFolder)

        var position = LibraryPoint(x: max(0, drag.position.x), y: max(0, drag.position.y))
        if snapToGrid, target == nil {
            position = LibraryLayout.snapped(position)
        }
        withAnimation(.spring(duration: 0.3)) {
            pendingPositions[drag.item] = position
        }

        Task {
            if let target {
                switch drag.item {
                case .folder(let id): try? await database.moveFolder(id, toParent: target)
                case .page(let id): try? await database.movePage(id, toFolder: target)
                case .source(let id): try? await database.moveSource(id, toFolder: target)
                }
                selection = nil
            } else {
                try? await database.setPosition(drag.item, position)
            }
        }
    }
}
