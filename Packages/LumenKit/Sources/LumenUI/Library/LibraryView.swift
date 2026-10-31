import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

/// Библиотека: папки, страницы и книги лежат на свободном холсте, как бумаги на столе.
/// Предмет можно положить куда угодно, бросить на папку, чтобы убрать внутрь,
/// а кнопка «Сетка» выравнивает всё по ячейкам и дальше примагничивает к ним.
struct LibraryView: View {
    let database: AppDatabase
    /// Открытая папка, `nil` это корень библиотеки.
    let folderId: UUID?
    var onOpenFolder: (UUID?) -> Void
    var onOpenPage: (UUID) -> Void
    var onOpenSource: (UUID) -> Void
    var onShowSourceInfo: (UUID) -> Void = { _ in }
    /// iPhone: корзина открывается из меню библиотеки, отдельной вкладки для неё нет.
    var onOpenTrash: (() -> Void)?

    @State private var snapshot = LibrarySnapshot.empty
    @State private var hasLoaded = false
    @State private var selection: LibraryItemID?
    @State private var drag: DragState?
    @State private var dropTarget: UUID?
    /// Куда предмет положили, пока база не вернула новое место: без этого он на миг прыгает назад.
    @State private var pendingPositions: [LibraryItemID: LibraryPoint] = [:]
    @State private var renaming: LibraryItemID?
    @State private var renameText = ""
    @State private var moving: LibraryItemID?
    /// Открытое стеклянное меню: у какого предмета и где на холсте.
    @State private var contextMenu: ContextMenuState?
    @State private var contextMenuHeight: CGFloat = 0
    /// Открыть в новой вкладке или рядом: есть только там, где есть вкладки (Mac и iPad).
    @Environment(\.workspaceActions) private var workspaceActions
    @State private var canvasWidth: CGFloat = 900
    @State private var isImporting = false
    /// Файлы добавляются: на холсте крутится индикатор.
    @State private var importingCount = 0
    /// Над холстом держат файлы из Finder.
    @State private var isDropTargeted = false
    /// iPhone: избранное в начале корня библиотеки, сайдбара с ним на телефоне нет.
    @State private var favorites: [Page] = []
    @State private var trashCount = 0
    @State private var isSyncInfoPresented = false
    @AppStorage("library.snapToGrid") private var snapToGrid = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme

    private static let canvasSpace = "libraryCanvas"

    private struct DragState: Equatable {
        var item: LibraryItemID
        var origin: LibraryPoint
        var translation: CGSize = .zero

        var position: LibraryPoint {
            LibraryPoint(x: origin.x + translation.width, y: origin.y + translation.height)
        }
    }

    private enum Content: Hashable {
        case folder(LibraryFolder)
        case page(LibraryPage)
        case source(LibrarySource)
    }

    private struct ContextMenuState: Equatable {
        var item: LibraryItemID
        var point: CGPoint
    }

    private struct PlacedItem: Identifiable, Hashable {
        var id: LibraryItemID
        var position: LibraryPoint
        var content: Content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !usesList {
                header
            }
            if snapshot.isMissing {
                ContentUnavailableView {
                    Label("Папки больше нет", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Её удалили. Она лежит в корзине, пока корзину не очистят.")
                } actions: {
                    Button("В библиотеку") { onOpenFolder(nil) }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if usesList {
                compactList
            } else {
                canvas
            }
        }
        .background(ThemedBackground())
        .navigationTitle(snapshot.folder?.displayName ?? "Библиотека")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: SourceImporter.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importFiles(urls, at: nil)
            }
        }
        .toolbar {
            if usesList {
                ToolbarItem(placement: .primaryAction) {
                    compactAddMenu
                }
                if folderId == nil {
                    ToolbarItem(placement: .navigation) {
                        compactMoreMenu
                    }
                }
            }
        }
        .alert("Название", isPresented: isRenamingInList) {
            TextField("Название", text: $renameText)
            Button("Готово") { commitRename() }
            Button("Отмена", role: .cancel) { renaming = nil }
        }
        .sheet(item: $moving) { item in
            MoveToFolderSheet(database: database, item: item, currentFolderId: folderId) {
                moving = nil
            }
        }
        .task { await observe() }
        .task(id: usesList && folderId == nil) {
            if usesList && folderId == nil { await observeFavorites() }
        }
        .sheet(isPresented: $isSyncInfoPresented) {
            NavigationStack {
                List { SyncStatusRow() }
                    .navigationTitle("iCloud")
                    .toolbar {
                        Button("Готово") { isSyncInfoPresented = false }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                breadcrumbs
                HStack(spacing: 10) {
                    if folderId != nil {
                        Button {
                            onOpenFolder(snapshot.path.last?.id)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Назад")
                    }
                    Text(snapshot.folder?.displayName ?? "Библиотека")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(action: toggleGrid) {
                    Label(snapToGrid ? "Сетка: вкл" : "Сетка: выкл", systemImage: "square.grid.2x2")
                }
                .buttonStyle(LibraryButtonStyle(isOn: snapToGrid))
                .help("Выровнять всё по ячейкам и примагничивать к ним")

                Button(action: newPage) {
                    Label("Заметка", systemImage: "plus")
                }
                .buttonStyle(LibraryButtonStyle())

                Button {
                    isImporting = true
                } label: {
                    Label("Книга", systemImage: "book.closed")
                }
                .buttonStyle(LibraryButtonStyle())
                .help("Добавить книгу или файл: EPUB, PDF, FB2, Word, PowerPoint, текст и другие")

                Button(action: newFolder) {
                    Label("Папка", systemImage: "folder.badge.plus")
                }
                .buttonStyle(LibraryButtonStyle(isProminent: true))
            }
            .disabled(snapshot.isMissing)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            if folderId == nil {
                Text("Все папки и заметки")
            } else {
                Button("Библиотека") { onOpenFolder(nil) }
                    .buttonStyle(.plain)
                ForEach(snapshot.path) { folder in
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    Button(folder.displayName) { onOpenFolder(folder.id) }
                        .buttonStyle(.plain)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(theme.textSecondary)
    }

    // MARK: Холст

    private var canvas: some View {
        GeometryReader { geometry in
            let items = placedItems
            ScrollView([.vertical, .horizontal]) {
                ZStack(alignment: .topLeading) {
                    // Пустое место холста: щелчок снимает выделение.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = nil
                            commitRename()
                        }
                    ForEach(items) { item in
                        tile(for: item)
                            .offset(x: item.position.x, y: item.position.y)
                            .zIndex(drag?.item == item.id ? 1 : 0)
                    }
                    if let contextMenu {
                        // Щелчок мимо меню закрывает его.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { closeContextMenu() }
                            .zIndex(2)
                        GlassMenu(entries: menuEntries(for: contextMenu.item), onDismiss: closeContextMenu)
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contextMenuHeight = $0 }
                            .offset(menuOrigin(
                                contextMenu.point,
                                in: CGSize(
                                    width: max(geometry.size.width, contentExtent(items).width),
                                    height: max(geometry.size.height, contentExtent(items).height)
                                )
                            ))
                            .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
                            .zIndex(3)
                    }
                }
                .frame(
                    width: max(geometry.size.width, contentExtent(items).width),
                    height: max(geometry.size.height, contentExtent(items).height),
                    alignment: .topLeading
                )
                .background(dotGrid)
                .coordinateSpace(name: Self.canvasSpace)
                // Файлы из Finder или «Файлов» можно бросить прямо на холст, туда, куда отпустили.
                .dropDestination(for: URL.self) { urls, location in
                    let files = urls.filter(\.isFileURL)
                    guard !files.isEmpty else { return false }
                    importFiles(files, at: LibraryPoint(
                        x: max(0, location.x - LibraryLayout.tileWidth / 2),
                        y: max(0, location.y - LibraryLayout.tileHeight / 2)
                    ))
                    return true
                } isTargeted: { isDropTargeted = $0 }
            }
            .scrollIndicators(.automatic)
            .overlay {
                if hasLoaded && items.isEmpty && importingCount == 0 {
                    ContentUnavailableView {
                        Label("Пока пусто", systemImage: "folder")
                    } description: {
                        Text("Создайте папку или заметку, добавьте книгу или перетащите сюда файл.")
                    } actions: {
                        Button("Новая папка", action: newFolder)
                            .buttonStyle(.borderedProminent)
                        Button("Добавить книгу") { isImporting = true }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            Label("Отпустите, чтобы добавить в библиотеку", systemImage: "tray.and.arrow.down")
                                .font(.headline)
                                .foregroundStyle(theme.textPrimary)
                        }
                        .allowsHitTesting(false)
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
            .onAppear { canvasWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, width in canvasWidth = width }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var dotGrid: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 2, height: 2))
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(theme.textPrimary.opacity(0.07)))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }

    private func contentExtent(_ items: [PlacedItem]) -> CGSize {
        let maxX = items.map { $0.position.x + LibraryLayout.tileWidth }.max() ?? 0
        let maxY = items.map { $0.position.y + LibraryLayout.tileHeight }.max() ?? 0
        return CGSize(width: maxX + 40, height: maxY + 40)
    }

    /// Сколько ячеек сетки помещается в ширину холста.
    private var columns: Int {
        max(1, Int((canvasWidth - LibraryLayout.origin.x) / LibraryLayout.cellWidth))
    }

    /// Все предметы папки на своих местах. Тем, кого ещё не двигали, достаются свободные ячейки.
    private var placedItems: [PlacedItem] {
        let contents: [(LibraryItemID, LibraryPoint?, Content)] =
            snapshot.folders.map { (.folder($0.id), $0.folder.position, .folder($0)) }
            + snapshot.pages.map { (.page($0.id), $0.page.position, .page($0)) }
            + snapshot.sources.map { (.source($0.id), $0.source.position, .source($0)) }

        var placed: [PlacedItem] = []
        var unplaced: [(LibraryItemID, Content)] = []
        for (id, stored, content) in contents {
            if let drag, drag.item == id {
                placed.append(PlacedItem(id: id, position: drag.position, content: content))
            } else if let position = pendingPositions[id] ?? stored {
                placed.append(PlacedItem(id: id, position: position, content: content))
            } else {
                unplaced.append((id, content))
            }
        }
        let free = LibraryLayout.freeCells(count: unplaced.count, avoiding: placed.map(\.position), columns: columns)
        for ((id, content), position) in zip(unplaced, free) {
            placed.append(PlacedItem(id: id, position: position, content: content))
        }
        return placed
    }

    // MARK: Плитки

    @ViewBuilder
    private func tile(for item: PlacedItem) -> some View {
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

    private func caption(for entry: LibrarySource) -> String {
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

    private func openSource(_ id: UUID) {
        LumenSounds.play(.navigate)
        onOpenSource(id)
    }

    private func caption(for entry: LibraryPage) -> String {
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

    // MARK: Действия

    private func toggleGrid() {
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

    private func newFolder() {
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

    private func newPage() {
        let position = freePosition()
        Task {
            if let page = try? await database.createPage(folderId: folderId, position: position) {
                LumenSounds.play(.create)
                onOpenPage(page.id)
            }
        }
    }

    private func startRename(_ item: LibraryItemID, current: String) {
        commitRename()
        selection = item
        renameText = current
        renaming = item
    }

    private func commitRename() {
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
    private func importFiles(_ urls: [URL], at point: LibraryPoint?) {
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

    // MARK: Стеклянное меню

    private func openContextMenu(for item: PlacedItem, at local: CGPoint) {
        commitRename()
        selection = item.id
        LumenSounds.play(.tap)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            contextMenu = ContextMenuState(
                item: item.id,
                point: CGPoint(x: item.position.x + local.x, y: item.position.y + local.y)
            )
        }
    }

    private func closeContextMenu() {
        withAnimation(.easeOut(duration: 0.12)) { contextMenu = nil }
    }

    /// Меню встаёт правее и ниже точки щелчка, но не вылезает за край холста.
    private func menuOrigin(_ point: CGPoint, in size: CGSize) -> CGSize {
        let x = min(point.x + 4, size.width - GlassMenu.width - 8)
        let y = min(point.y + 4, size.height - contextMenuHeight - 8)
        return CGSize(width: max(8, x), height: max(8, y))
    }

    private func menuEntries(for item: LibraryItemID) -> [GlassMenuEntry] {
        switch item {
        case .folder(let id):
            guard let folder = snapshot.folders.first(where: { $0.id == id })?.folder else { return [] }
            var entries: [GlassMenuEntry] = [
                .action(GlassMenuAction(title: "Открыть", systemImage: "folder", shortcut: "⏎") {
                    LumenSounds.play(.navigate)
                    onOpenFolder(folder.id)
                }),
            ]
            entries += openElsewhereEntries(.library(folder.id))
            entries += [
                .action(GlassMenuAction(title: "Переименовать", systemImage: "pencil") {
                    startRename(.folder(folder.id), current: folder.name)
                }),
                .action(GlassMenuAction(title: "Переместить в…", systemImage: "arrow.right") {
                    moving = .folder(folder.id)
                }),
                .divider,
                .label("Цвет папки"),
                .swatches(selected: folder.color) { color in
                    Task { try? await database.setFolderColor(folder.id, color: color) }
                },
                .divider,
                .action(GlassMenuAction(title: "В корзину", systemImage: "trash", shortcut: "⌫", isDestructive: true) {
                    selection = nil
                    LumenSounds.play(.trash)
                    Task { try? await database.trashFolder(folder.id) }
                }),
            ]
            return entries
        case .page(let id):
            guard let entry = snapshot.pages.first(where: { $0.id == id }) else { return [] }
            let page = entry.page
            var entries: [GlassMenuEntry] = [
                .action(GlassMenuAction(title: "Открыть", systemImage: "doc.text", shortcut: "⏎") {
                    LumenSounds.play(.navigate)
                    onOpenPage(page.id)
                }),
            ]
            entries += openElsewhereEntries(.page(page.id))
            entries += [
                .action(GlassMenuAction(title: "Переименовать", systemImage: "pencil") {
                    startRename(.page(page.id), current: page.title)
                }),
            ]
            if !entry.subpages.isEmpty {
                entries.append(.divider)
                entries.append(.label("Подстраницы"))
                for subpage in entry.subpages {
                    entries.append(.action(GlassMenuAction(title: subpage.displayTitle, systemImage: "doc") {
                        LumenSounds.play(.navigate)
                        onOpenPage(subpage.id)
                    }))
                }
            }
            entries += [
                .action(GlassMenuAction(title: "Новая подстраница", systemImage: "doc.badge.plus") {
                    Task {
                        if let subpage = try? await database.createPage(parentId: page.id) {
                            LumenSounds.play(.create)
                            onOpenPage(subpage.id)
                        }
                    }
                }),
                .divider,
                .action(GlassMenuAction(
                    title: page.isFavorite ? "Убрать из избранного" : "В избранное",
                    systemImage: page.isFavorite ? "star.slash" : "star"
                ) {
                    Task { try? await database.setFavorite(page.id, !page.isFavorite) }
                }),
                .action(GlassMenuAction(title: "Переместить в…", systemImage: "arrow.right") {
                    moving = .page(page.id)
                }),
                .divider,
                .action(GlassMenuAction(title: "В корзину", systemImage: "trash", shortcut: "⌫", isDestructive: true) {
                    selection = nil
                    LumenSounds.play(.trash)
                    Task { try? await database.trashPage(page.id) }
                }),
            ]
            return entries
        case .source(let id):
            guard let source = snapshot.sources.first(where: { $0.id == id })?.source else { return [] }
            var entries: [GlassMenuEntry] = [
                .action(GlassMenuAction(title: "Читать", systemImage: "book", shortcut: "⏎") {
                    openSource(source.id)
                }),
            ]
            entries += openElsewhereEntries(.source(source.id, highlight: nil))
            entries += [
                .action(GlassMenuAction(title: "Заметки к книге", systemImage: "note.text") {
                    openNotes(of: source.id)
                }),
                .action(GlassMenuAction(title: "О книге", systemImage: "chart.bar") {
                    onShowSourceInfo(source.id)
                }),
                .action(GlassMenuAction(title: "Переименовать", systemImage: "pencil") {
                    startRename(.source(source.id), current: source.displayTitle)
                }),
                .action(GlassMenuAction(title: "Переместить в…", systemImage: "arrow.right") {
                    moving = .source(source.id)
                }),
                .divider,
                .action(GlassMenuAction(title: "В корзину", systemImage: "trash", shortcut: "⌫", isDestructive: true) {
                    selection = nil
                    LumenSounds.play(.trash)
                    Task { try? await database.trashSource(source.id) }
                }),
            ]
            return entries
        }
    }

    /// «В новой вкладке» и «Рядом» для предмета: книгу рядом с конспектом, папку в отдельной вкладке.
    private func openElsewhereEntries(_ item: SidebarItem) -> [GlassMenuEntry] {
        guard let workspaceActions else { return [] }
        return [
            .action(GlassMenuAction(title: "Открыть в новой вкладке", systemImage: "plus.square.on.square") {
                LumenSounds.play(.navigate)
                workspaceActions.openInNewTab(item)
            }),
            .action(GlassMenuAction(title: "Открыть рядом", systemImage: "rectangle.split.2x1") {
                LumenSounds.play(.navigate)
                workspaceActions.openBeside(item)
            }),
        ]
    }

    private func openNotes(of sourceId: UUID) {
        Task {
            if let page = try? await database.notesPage(for: sourceId) {
                LumenSounds.play(.navigate)
                onOpenPage(page.id)
            }
        }
    }

    // MARK: Системное меню (iPhone и iPad)

    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
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
            set: { color in Task { try? await database.setFolderColor(folder.id, color: color) } }
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
            LumenSounds.play(.trash)
            Task { try? await database.trashFolder(folder.id) }
        } label: {
            Label("В корзину", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func pageMenu(_ entry: LibraryPage) -> some View {
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
                if let subpage = try? await database.createPage(parentId: page.id) {
                    LumenSounds.play(.create)
                    onOpenPage(subpage.id)
                }
            }
        } label: {
            Label("Новая подстраница", systemImage: "doc.badge.plus")
        }
        Button {
            Task { try? await database.setFavorite(page.id, !page.isFavorite) }
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
            LumenSounds.play(.trash)
            Task { try? await database.trashPage(page.id) }
        } label: {
            Label("В корзину", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func sourceMenu(_ source: Source) -> some View {
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
            LumenSounds.play(.trash)
            Task { try? await database.trashSource(source.id) }
        } label: {
            Label("В корзину", systemImage: "trash")
        }
    }

    private func observe() async {
        let folderId = folderId
        let observation = ValueObservation.tracking { db in try LibrarySnapshot.fetch(db, folderId: folderId) }
        do {
            for try await value in observation.values(in: database.reader) {
                snapshot = value
                hasLoaded = true
                pendingPositions = [:]
            }
        } catch {
            print("Library observation failed: \(error)")
        }
    }
}

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

    /// Корзина и iCloud: на Mac они в сайдбаре, на iPhone в меню корня библиотеки.
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
                Label("iCloud", systemImage: "icloud")
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
            print("Favorites observation failed: \(error)")
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
                                Task { try? await database.setFavorite(page.id, false) }
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
                                LumenSounds.play(.trash)
                                Task { try? await database.trashFolder(entry.id) }
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
                                LumenSounds.play(.trash)
                                Task { try? await database.trashSource(entry.id) }
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
                                LumenSounds.play(.trash)
                                Task { try? await database.trashPage(entry.id) }
                            } label: {
                                Label("В корзину", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { try? await database.setFavorite(entry.id, !entry.page.isFavorite) }
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

/// Меню плитки. На Mac правый щелчок открывает стеклянное меню библиотеки,
/// на iPhone и iPad долгое нажатие показывает системное: оно там родное и с превью.
private struct LibraryTileMenu<MenuItems: View>: ViewModifier {
    var onSecondaryClick: (CGPoint) -> Void
    @ViewBuilder var menuItems: () -> MenuItems

    func body(content: Content) -> some View {
        #if os(macOS)
        content.overlay(SecondaryClickCatcher(onSecondaryClick: onSecondaryClick))
        #else
        content.contextMenu { menuItems() }
        #endif
    }
}

/// Щелчок выделяет, двойной открывает (на Mac). На iPhone и iPad касание сразу открывает.
private struct TileInteraction<DragGestureType: Gesture>: ViewModifier {
    var onSelect: () -> Void
    var onOpen: () -> Void
    var drag: DragGestureType

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .gesture(drag)
            .onTapGesture(count: 2, perform: onOpen)
            .onTapGesture(perform: onSelect)
        #else
        content
            .gesture(drag)
            .onTapGesture(perform: onOpen)
        #endif
    }
}

/// Кнопки шапки библиотеки: стеклянные, главная закатная.
struct LibraryButtonStyle: ButtonStyle {
    var isOn = false
    var isProminent = false
    @Environment(\.lumenTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isProminent ? theme.vividCard(0).foreground : theme.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background {
                if isProminent {
                    shape.fill(LinearGradient(colors: theme.vividCard(0).colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: (theme.vividCard(0).colors.last ?? .clear).opacity(0.6), radius: 9, y: 6)
                } else {
                    shape.fill(isOn ? theme.accent.opacity(0.3) : theme.cardFill)
                }
            }
            .overlay(shape.strokeBorder(isOn ? theme.accent.opacity(0.6) : theme.cardStroke, lineWidth: 1))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(isProminent ? 0.5 : 0.12), .clear], startPoint: .top, endPoint: .center),
                lineWidth: 1
            ))
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.5))
    }
}

#Preview {
    NavigationStack {
        LibraryView(database: .preview(), folderId: nil, onOpenFolder: { _ in }, onOpenPage: { _ in }, onOpenSource: { _ in })
    }
    .preferredColorScheme(.dark)
}
