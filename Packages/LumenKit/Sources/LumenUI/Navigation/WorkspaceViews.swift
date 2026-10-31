import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

/// Название и значок того, что открыто: для вкладок и подсказок у стрелок.
struct ItemTitle: Hashable, Sendable {
    var title: String
    var icon: String?
    var systemImage: String

    /// Название без базы: для разделов, у которых оно постоянное.
    static func fixed(_ item: SidebarItem) -> ItemTitle? {
        if item == .home { return ItemTitle(title: "Главная", systemImage: "sparkles") }
        if item == .inbox { return ItemTitle(title: "Входящие", systemImage: "tray") }
        if item == .trash { return ItemTitle(title: "Корзина", systemImage: "trash") }
        if item == .library(nil) { return ItemTitle(title: "Библиотека", systemImage: "books.vertical") }
        return nil
    }

    init(title: String, icon: String? = nil, systemImage: String) {
        self.title = title
        self.icon = icon
        self.systemImage = systemImage
    }

    static func fetch(_ db: GRDB.Database, item: SidebarItem) throws -> ItemTitle {
        if let fixed = fixed(item) { return fixed }
        switch item {
        case .page(let id):
            let page = try Page.fetchOne(db, key: id)
            return ItemTitle(title: page?.displayTitle ?? "Страница", icon: page?.icon, systemImage: "doc.text")
        case .source(let id, _):
            let source = try Source.fetchOne(db, key: id)
            return ItemTitle(title: source?.displayTitle ?? "Книга", systemImage: "book")
        case .sourceInfo(let id):
            let source = try Source.fetchOne(db, key: id)
            return ItemTitle(title: source.map { "О книге: \($0.displayTitle)" } ?? "О книге", systemImage: "chart.bar")
        case .library(let id?):
            let folder = try Folder.fetchOne(db, key: id)
            return ItemTitle(title: folder?.name ?? "Папка", systemImage: "folder")
        default:
            return ItemTitle(title: "Lumen", systemImage: "square.dashed")
        }
    }
}

/// Название раздела, которое обновляется вместе с базой: переименовал страницу, поменялась вкладка.
struct WorkspaceItemLabel: View {
    let database: AppDatabase
    let item: SidebarItem
    var showsIcon = true

    @State private var title: ItemTitle?

    var body: some View {
        let shown = title ?? ItemTitle.fixed(item) ?? ItemTitle(title: "", systemImage: "doc.text")
        HStack(spacing: 5) {
            if showsIcon {
                if let icon = shown.icon, !icon.isEmpty {
                    Text(icon).font(.caption)
                } else {
                    Image(systemName: shown.systemImage)
                        .font(.caption)
                        .imageScale(.small)
                }
            }
            Text(shown.title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .task(id: item) { await observe() }
    }

    private func observe() async {
        if let fixed = ItemTitle.fixed(item) {
            title = fixed
            return
        }
        let item = item
        let observation = ValueObservation.tracking { db in try ItemTitle.fetch(db, item: item) }
        do {
            for try await value in observation.values(in: database.reader) {
                title = value
            }
        } catch {}
    }
}

/// Полоска вкладок над содержимым: как в браузере, «+» открывает новую,
/// крестик закрывает, вкладки можно перетаскивать.
struct WorkspaceTabStrip: View {
    let database: AppDatabase
    @Bindable var workspace: Workspace

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                            tabButton(tab, number: index + 1)
                                .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: workspace.selectedTabId) { _, id in
                    withAnimation(.snappy) { proxy.scrollTo(id) }
                }
            }

            Button {
                withAnimation(.snappy) { workspace.newTab() }
            } label: {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
            .help("Новая вкладка (⌘T)")
            .accessibilityLabel("Новая вкладка")
            .padding(.trailing, 10)
        }
        .background(.ultraThinMaterial.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.cardStroke).frame(height: 0.5)
        }
    }

    private func tabButton(_ tab: WorkspaceTab, number: Int) -> some View {
        let isSelected = tab.id == workspace.selectedTabId
        return HStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(tab.panes.enumerated()), id: \.offset) { index, pane in
                    if index > 0 {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.caption2)
                            .foregroundStyle(theme.textSecondary)
                    }
                    WorkspaceItemLabel(database: database, item: pane.current, showsIcon: index == 0)
                        .frame(maxWidth: tab.isSplit ? 110 : 180)
                }
            }
            .font(.callout)
            .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)

            if workspace.tabs.count > 1 {
                Button {
                    withAnimation(.snappy) { workspace.closeTab(tab.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .opacity(isSelected ? 1 : 0.6)
                .help("Закрыть вкладку (⌘W)")
                .accessibilityLabel("Закрыть вкладку")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, workspace.tabs.count > 1 ? 8 : 12)
        .frame(height: 30)
        .background {
            Capsule()
                .fill(isSelected ? theme.cardFill : Color.clear)
                .overlay {
                    Capsule().strokeBorder(isSelected ? theme.accent.opacity(0.55) : theme.cardStroke, lineWidth: 1)
                }
        }
        .contentShape(Capsule())
        .onTapGesture { workspace.select(tab: tab.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("tab-\(number)")
        .draggable(tab.id.uuidString) {
            WorkspaceItemLabel(database: database, item: tab.panes[0].current)
                .padding(8)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            withAnimation(.snappy) { workspace.moveTab(id, before: tab.id) }
            return true
        }
        .contextMenu {
            Button("Новая вкладка рядом") { workspace.newTab() }
            Button("Дублировать вкладку") {
                workspace.select(tab: tab.id)
                workspace.newTab(tab.current)
            }
            Divider()
            Button("Закрыть вкладку") { workspace.closeTab(tab.id) }
                .disabled(workspace.tabs.count < 2)
            Button("Закрыть другие вкладки") { workspace.closeOtherTabs(tab.id) }
                .disabled(workspace.tabs.count < 2)
        }
    }
}

/// Шапка панели в разделённом экране: её стрелки, название и кнопка «закрыть панель».
/// Активная панель подсвечена: туда открывается то, что выбрано в сайдбаре.
struct PaneHeader: View {
    let database: AppDatabase
    @Bindable var workspace: Workspace
    let pane: Int

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let tab = workspace.selectedTab
        // Во время анимации закрытия панели её индекса уже может не быть.
        let history = tab.panes.indices.contains(pane) ? tab.panes[pane] : NavigationHistory()
        let isFocused = tab.focusedPane == pane
        HStack(spacing: 4) {
            Button {
                workspace.focus(pane: pane)
                workspace.goBack()
            } label: {
                Image(systemName: "chevron.left").frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .disabled(!history.canGoBack)
            .help("Назад")
            .accessibilityLabel("Назад")
            Button {
                workspace.focus(pane: pane)
                workspace.goForward()
            } label: {
                Image(systemName: "chevron.right").frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .disabled(!history.canGoForward)
            .help("Вперёд")
            .accessibilityLabel("Вперёд")

            WorkspaceItemLabel(database: database, item: history.current)
                .font(.callout.weight(isFocused ? .semibold : .regular))
                .foregroundStyle(isFocused ? theme.textPrimary : theme.textSecondary)
                .frame(maxWidth: .infinity)

            Button {
                workspace.swapPanes()
            } label: {
                Image(systemName: "arrow.left.arrow.right").frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .help("Поменять панели местами")
            .accessibilityLabel("Поменять панели местами")
            Button {
                withAnimation(.snappy) { workspace.closePane(pane) }
            } label: {
                Image(systemName: "xmark").frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .help("Закрыть панель")
            .accessibilityLabel("Закрыть панель")
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(isFocused ? theme.accent.opacity(0.14) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isFocused ? theme.accent : theme.cardStroke)
                .frame(height: isFocused ? 2 : 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { workspace.focus(pane: pane) }
    }
}

/// Активна ли панель, в которой лежит экран. Неактивная панель не выставляет
/// свои кнопки в панель окна, иначе в разделённом экране они бы задвоились.
extension EnvironmentValues {
    @Entry var isActivePane = true
}

/// Каких страниц, книг и папок из вкладок больше нет (удалены или в корзине).
enum MissingItemsQuery {
    static func fetch(_ db: GRDB.Database, items: Set<SidebarItem>) throws -> Set<SidebarItem> {
        var pageIds = Set<UUID>()
        var sourceIds = Set<UUID>()
        var folderIds = Set<UUID>()
        for item in items {
            switch item {
            case .page(let id): pageIds.insert(id)
            case .source(let id, _), .sourceInfo(let id): sourceIds.insert(id)
            case .library(let id?): folderIds.insert(id)
            default: break
            }
        }
        let alive = Column("deletedAt") == nil
        let livePages = try Set(Page.filter(keys: pageIds).filter(alive).fetchAll(db).map(\.id))
        let liveSources = try Set(Source.filter(keys: sourceIds).filter(alive).fetchAll(db).map(\.id))
        let liveFolders = try Set(Folder.filter(keys: folderIds).filter(alive).fetchAll(db).map(\.id))
        return items.filter { item in
            switch item {
            case .page(let id): !livePages.contains(id)
            case .source(let id, _), .sourceInfo(let id): !liveSources.contains(id)
            case .library(let id?): !liveFolders.contains(id)
            default: false
            }
        }
    }
}

/// Открыть не на месте, а в новой вкладке или во второй панели. Экраны берут это из окружения,
/// на iPhone его нет, и пунктов меню там нет.
struct WorkspaceActions: Sendable {
    var openInNewTab: @MainActor @Sendable (SidebarItem) -> Void
    var openBeside: @MainActor @Sendable (SidebarItem) -> Void
}

extension EnvironmentValues {
    @Entry var workspaceActions: WorkspaceActions? = nil
}
