import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let database: AppDatabase
    @Binding var selection: SidebarItem?
    var onNewPage: (UUID?) -> Void
    var onNewFolder: (UUID?) -> Void
    var onNewDataTable: () -> Void
    /// Поиск и действия (⌘K).
    var onSearch: () -> Void = {}
    /// Кнопка «Создать».
    var onCreate: (CreateKind) -> Void = { _ in }
    var onSettings: () -> Void = {}

    @State private var snapshot = SidebarSnapshot.empty
    @State private var renaming: Page?
    @State private var renamingFolder: Folder?
    @State private var newTitle = ""
    @Environment(\.workspaceActions) private var workspaceActions
    // Какие разделы видны, выбирают в настройках.
    @AppStorage(ScreenOptions.sidebarRecentKey) private var showsRecent = true
    @AppStorage(ScreenOptions.sidebarFavoritesKey) private var showsFavorites = true
    @AppStorage(ScreenOptions.sidebarDatabasesKey) private var showsDatabases = true
    @AppStorage(ScreenOptions.sidebarFoldersKey) private var showsFolders = true

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Сегодня", systemImage: "sun.max")
                    .tag(SidebarItem.home)
                Label("Входящие", systemImage: "tray")
                    .badge(snapshot.inboxCount)
                    .tag(SidebarItem.inbox)
                Label("Задачи", systemImage: "checklist")
                    .tag(SidebarItem.tasks)
                Label("Библиотека", systemImage: "books.vertical")
                    .tag(SidebarItem.library(nil))
                    .dropDestination(for: PageDragItem.self) { items, _ in
                        move(items, toFolder: nil)
                    }
            }

            if showsRecent, !snapshot.recent.isEmpty {
                Section("Недавние") {
                    ForEach(snapshot.recent) { item in
                        recentRow(item)
                    }
                }
            }

            if showsFavorites, !snapshot.favorites.isEmpty {
                Section("Избранное") {
                    ForEach(snapshot.favorites) { page in
                        PageLabel(page: page)
                            .tag(SidebarItem.page(page.id))
                            .contextMenu { menu(for: page) }
                            .draggable(PageDragItem(pageId: page.id)) {
                                PageLabel(page: page).padding(6)
                            }
                    }
                }
            }

            if showsDatabases {
                Section {
                    ForEach(snapshot.databases) { page in
                        PageLabel(page: page)
                            .tag(SidebarItem.page(page.id))
                            .contextMenu { menu(for: page) }
                    }
                    Button(action: onNewDataTable) {
                        Label("Новая база данных", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Базы данных")
                }
            }

            if showsFolders {
                Section {
                    OutlineGroup(snapshot.folders, children: \.childrenOrNil) { node in
                        FolderLabel(folder: node.folder)
                            .tag(SidebarItem.library(node.id))
                            .contextMenu { folderMenu(for: node.folder) }
                            // Перетащите страницу из избранного на папку, чтобы положить её туда.
                            .dropDestination(for: PageDragItem.self) { items, _ in
                                move(items, toFolder: node.id)
                            }
                    }
                    Button {
                        onNewFolder(nil)
                    } label: {
                        Label("Новая папка", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Папки")
                }
            }

        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle("Lumen")
        .task { await observe() }
        .alert("Переименовать страницу", isPresented: isRenaming) {
            TextField("Название", text: $newTitle)
            Button("Готово") {
                if let page = renaming {
                    let title = newTitle
                    Task {
                        await NoticeCenter.shared.attempt("Не удалось переименовать страницу") {
                            try await database.renamePage(page.id, title: title)
                        }
                    }
                }
                renaming = nil
            }
            Button("Отмена", role: .cancel) { renaming = nil }
        }
        .alert("Переименовать папку", isPresented: isRenamingFolder) {
            TextField("Название", text: $newTitle)
            Button("Готово") {
                if let folder = renamingFolder {
                    let name = newTitle
                    Task {
                        await NoticeCenter.shared.attempt("Не удалось переименовать папку") {
                            try await database.renameFolder(folder.id, name: name)
                        }
                    }
                }
                renamingFolder = nil
            }
            Button("Отмена", role: .cancel) { renamingFolder = nil }
        }
    }

    /// Поиск и «Создать» над разделами: всегда на виду.
    private var topBar: some View {
        VStack(spacing: 10) {
            Button(action: onSearch) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Найти или сделать…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ShortcutHint(text: "⌘K")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.1)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Поиск по страницам, книгам и цитатам, а ещё быстрые действия (⌘K)")
            .accessibilityIdentifier("sidebar-search")

            CreateButton(onSelect: onCreate)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// Корзина и настройки внизу, отдельно от разделов.
    /// В узкой боковой панели надписи не влезают и рвались по слогам («Кор з…»), тогда остаются только значки.
    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            bottomButtons(compact: false)
            bottomButtons(compact: true)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }

    private var trashTitle: String {
        snapshot.trashCount > 0 ? "Корзина · \(snapshot.trashCount)" : "Корзина"
    }

    private func bottomButtons(compact: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                selection = .trash
            } label: {
                bottomLabel(compact ? (snapshot.trashCount > 0 ? "\(snapshot.trashCount)" : nil) : trashTitle, icon: "trash", compact: compact)
                    .background(selection == .trash ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityLabel(trashTitle)
            .help(trashTitle)
            .accessibilityIdentifier("sidebar-trash")
            Button(action: onSettings) {
                bottomLabel(compact ? nil : "Настройки", icon: "gearshape", compact: compact)
            }
            .accessibilityLabel("Настройки")
            .help("Настройки: тема, звук, данные, копии и синхронизация")
        }
    }

    /// Значок и надпись в одну строку. В узком виде вместо надписи только число в корзине.
    private func bottomLabel(_ title: String?, icon: String, compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            if let title {
                Text(title)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func recentRow(_ item: RecentItem) -> some View {
        switch item {
        case .page(let page):
            PageLabel(page: page)
                .tag(SidebarItem.page(page.id))
                .contextMenu { menu(for: page) }
        case .source(let source):
            Label {
                Text(source.displayTitle).lineLimit(1)
            } icon: {
                Image(systemName: source.format.symbolName)
            }
            .tag(SidebarItem.source(source.id, highlight: nil))
            .contextMenu { openElsewhereButtons(.source(source.id, highlight: nil)) }
        }
    }

    private var isRenamingFolder: Binding<Bool> {
        Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func move(_ items: [PageDragItem], toFolder folderId: UUID?) -> Bool {
        let ids = items.map(\.pageId)
        guard !ids.isEmpty else { return false }
        LumenSounds.play(.dropIntoFolder)
        Task {
            await NoticeCenter.shared.attempt("Не удалось переместить страницу") {
                for id in ids {
                    try await database.movePage(id, toFolder: folderId)
                }
            }
        }
        return true
    }

    /// «В новой вкладке» и «Рядом», как ссылка в браузере.
    @ViewBuilder
    private func openElsewhereButtons(_ item: SidebarItem) -> some View {
        if let workspaceActions {
            Button {
                workspaceActions.openInNewTab(item)
            } label: {
                Label("Открыть в новой вкладке", systemImage: "plus.square.on.square")
            }
            Button {
                workspaceActions.openBeside(item)
            } label: {
                Label("Открыть рядом", systemImage: "rectangle.split.2x1")
            }
            Divider()
        }
    }

    @ViewBuilder
    private func folderMenu(for folder: Folder) -> some View {
        openElsewhereButtons(.library(folder.id))
        Button {
            newTitle = folder.name
            renamingFolder = folder
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Button {
            onNewFolder(folder.id)
        } label: {
            Label("Новая папка внутри", systemImage: "folder.badge.plus")
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
        if folder.parentId != nil {
            Button {
                Task {
                    await NoticeCenter.shared.attempt("Не удалось переместить") {
                        try await database.moveFolder(folder.id, toParent: nil)
                    }
                }
            } label: {
                Label("В корень библиотеки", systemImage: "arrow.up.to.line")
            }
        }
        Divider()
        Button(role: .destructive) {
            if selection == .library(folder.id) { selection = .library(nil) }
            NoticeCenter.shared.moveToTrash(.folder(folder.id), in: database)
        } label: {
            Label("В корзину", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func menu(for page: Page) -> some View {
        openElsewhereButtons(.page(page.id))
        Button {
            newTitle = page.title
            renaming = page
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Button {
            onNewPage(page.id)
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
        if page.parentId != nil {
            Button {
                Task {
                    await NoticeCenter.shared.attempt("Не удалось переместить") {
                        try await database.movePage(page.id, toParent: nil)
                    }
                }
            } label: {
                Label("На верхний уровень", systemImage: "arrow.up.to.line")
            }
        }
        Divider()
        Button(role: .destructive) {
            if selection == .page(page.id) { selection = .home }
            NoticeCenter.shared.moveToTrash(.page(page.id), in: database)
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                snapshot = value
            }
        } catch {
            lumenLog.error("Sidebar observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Значок и название папки.
struct FolderLabel: View {
    let folder: Folder

    var body: some View {
        Label {
            Text(folder.displayName)
                .lineLimit(1)
        } icon: {
            FolderGlyph(color: folder.color)
        }
    }
}

/// Что переносится при перетаскивании страницы в сайдбаре.
struct PageDragItem: Codable, Transferable {
    let pageId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .lumenPage)
    }
}

extension UTType {
    static let lumenPage = UTType(exportedAs: "app.lumen.page")
}

/// Иконка и название страницы.
struct PageLabel: View {
    let page: Page

    var body: some View {
        Label {
            Text(page.displayTitle)
                .lineLimit(1)
        } icon: {
            if let icon = page.icon, !icon.isEmpty {
                Text(icon)
            } else {
                Image(systemName: "doc.text")
            }
        }
    }
}
