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

    @State var snapshot = LibrarySnapshot.empty
    @State var hasLoaded = false
    @State var selection: LibraryItemID?
    @State var drag: DragState?
    @State var dropTarget: UUID?
    /// Куда предмет положили, пока база не вернула новое место: без этого он на миг прыгает назад.
    @State var pendingPositions: [LibraryItemID: LibraryPoint] = [:]
    @State var renaming: LibraryItemID?
    @State var renameText = ""
    @State var moving: LibraryItemID?
    /// Открытое стеклянное меню: у какого предмета и где на холсте.
    @State var contextMenu: ContextMenuState?
    @State private var contextMenuHeight: CGFloat = 0
    @State private var canvasWidth: CGFloat = 900
    @State var isImporting = false
    /// Файлы добавляются: на холсте крутится индикатор.
    @State var importingCount = 0
    /// Над холстом держат файлы из Finder.
    @State private var isDropTargeted = false
    /// iPhone: избранное в начале корня библиотеки, сайдбара с ним на телефоне нет.
    @State var favorites: [Page] = []
    @State var trashCount = 0
    @State var isSyncInfoPresented = false
    @AppStorage("library.snapToGrid") var snapToGrid = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) var theme

    static let canvasSpace = "libraryCanvas"

    struct DragState: Equatable {
        var item: LibraryItemID
        var origin: LibraryPoint
        var translation: CGSize = .zero

        var position: LibraryPoint {
            LibraryPoint(x: origin.x + translation.width, y: origin.y + translation.height)
        }
    }

    enum Content: Hashable {
        case folder(LibraryFolder)
        case page(LibraryPage)
        case source(LibrarySource)
    }

    struct ContextMenuState: Equatable {
        var item: LibraryItemID
        var point: CGPoint
    }

    struct PlacedItem: Identifiable, Hashable {
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
    var columns: Int {
        max(1, Int((canvasWidth - LibraryLayout.origin.x) / LibraryLayout.cellWidth))
    }

    /// Все предметы папки на своих местах. Тем, кого ещё не двигали, достаются свободные ячейки.
    var placedItems: [PlacedItem] {
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

    // MARK: Стеклянное меню

    func openContextMenu(for item: PlacedItem, at local: CGPoint) {
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
            return [
                .action(GlassMenuAction(title: "Открыть", systemImage: "folder", shortcut: "⏎") {
                    LumenSounds.play(.navigate)
                    onOpenFolder(folder.id)
                }),
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
        case .page(let id):
            guard let entry = snapshot.pages.first(where: { $0.id == id }) else { return [] }
            let page = entry.page
            var entries: [GlassMenuEntry] = [
                .action(GlassMenuAction(title: "Открыть", systemImage: "doc.text", shortcut: "⏎") {
                    LumenSounds.play(.navigate)
                    onOpenPage(page.id)
                }),
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
            return [
                .action(GlassMenuAction(title: "Читать", systemImage: "book", shortcut: "⏎") {
                    openSource(source.id)
                }),
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
        }
    }

    func openNotes(of sourceId: UUID) {
        Task {
            if let page = try? await database.notesPage(for: sourceId) {
                LumenSounds.play(.navigate)
                onOpenPage(page.id)
            }
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

#Preview {
    NavigationStack {
        LibraryView(database: .preview(), folderId: nil, onOpenFolder: { _ in }, onOpenPage: { _ in }, onOpenSource: { _ in })
    }
    .preferredColorScheme(.dark)
}
