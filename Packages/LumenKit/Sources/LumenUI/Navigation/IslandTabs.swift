import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Вкладки кружками слева от острова (Mac и iPad). Кружок = вкладка: книга видна обложкой,
/// страница своим значком, вкладка с двумя панелями разрезана пополам. Открытая с ободком акцентом.
/// Навёл: название и крестик. Не влезают: последний кружок «+N» открывает список всех.
/// Круглая «+» перед кружками видна всегда, даже пока вкладка одна (тогда только она).
/// Кружок тянут вдоль ряда (порядок) или к краю окна (разделить экран, `TabEdgeDropDelegate`).
struct IslandTabs: View {
    let database: AppDatabase
    @Bindable var workspace: Workspace
    /// Сколько кружков влезает слева от острова (`capacity`). Меньше двух: один кружок с числом.
    let capacity: Int

    @Environment(\.lumenTheme) private var theme
    @State private var isPlusHovered = false
    @State private var showsAll = false

    nonisolated static let size: CGFloat = 46
    nonisolated static let spacing: CGFloat = 8
    nonisolated static let maxShown = 5
    /// Отступ от острова.
    nonisolated static let gap: CGFloat = 14

    /// Сколько кружков влезает, если до края окна `space` точек.
    nonisolated static func capacity(space: CGFloat) -> Int {
        let room = space - gap - size - spacing - 16
        return max(0, min(maxShown, Int((room + spacing) / (size + spacing))))
    }

    var body: some View {
        let tabs = workspace.tabs
        // Одна вкладка: кружок ей не нужен, остаётся только «+».
        let shown = tabs.count > 1 ? Self.shownTabs(tabs, selected: workspace.selectedTabId, capacity: capacity) : []
        let hidden = tabs.count > 1 ? tabs.count - shown.count : 0
        HStack(spacing: Self.spacing) {
            newTabButton
            ForEach(shown) { tab in
                TabCircle(
                    database: database,
                    workspace: workspace,
                    tab: tab,
                    number: (tabs.firstIndex(of: tab) ?? 0) + 1
                )
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if hidden > 0 {
                moreButton(hidden: hidden, compact: shown.isEmpty)
            }
        }
        .animation(LumenMotion.standard, value: tabs.map(\.id))
        .animation(LumenMotion.quick, value: workspace.selectedTabId)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Вкладки")
    }

    /// Какие вкладки видны кружками: первые по порядку, но открытая видна всегда.
    nonisolated static func shownTabs(_ tabs: [WorkspaceTab], selected: UUID, capacity: Int) -> [WorkspaceTab] {
        guard tabs.count > capacity else { return tabs }
        // Последнее место занимает «+N».
        let slots = capacity >= 2 ? capacity - 1 : 0
        guard slots > 0 else { return [] }
        var shown = Array(tabs.prefix(slots))
        if !shown.contains(where: { $0.id == selected }), let tab = tabs.first(where: { $0.id == selected }) {
            shown[slots - 1] = tab
        }
        return shown
    }

    /// «+» новая вкладка: такой же стеклянный кружок, как вкладки, виден всегда.
    private var newTabButton: some View {
        Button {
            withAnimation(LumenMotion.standard) { workspace.newTab() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isPlusHovered ? theme.accent : theme.textSecondary)
                .frame(width: Self.size, height: Self.size)
                .lumenGlass(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isPlusHovered = $0 }
        .animation(LumenMotion.quick, value: isPlusHovered)
        .help("Новая вкладка (⌘T)")
        .accessibilityLabel("Новая вкладка")
        .accessibilityIdentifier("island.newTab")
        .keyHint("Новая вкладка") { withAnimation(LumenMotion.standard) { workspace.newTab() } }
    }

    /// «+N»: вкладки, которым не хватило места. В узком окне это единственный кружок, с числом всех вкладок.
    private func moreButton(hidden: Int, compact: Bool) -> some View {
        Button {
            showsAll = true
        } label: {
            Text(compact ? "\(workspace.tabs.count)" : "+\(hidden)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .frame(width: Self.size - 8, height: Self.size - 8)
                .background(theme.sheet, in: Circle())
                .frame(width: Self.size, height: Self.size)
                .lumenGlass(Circle())
                .overlay {
                    if compact {
                        Circle().strokeBorder(theme.accent, lineWidth: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Все вкладки")
        .accessibilityLabel(compact ? "Вкладки: \(workspace.tabs.count)" : "Ещё вкладки: \(hidden)")
        .accessibilityIdentifier("island.tabs.more")
        .keyHint("Все вкладки") { showsAll = true }
        .popover(isPresented: $showsAll, arrowEdge: .bottom) {
            TabListPopover(database: database, workspace: workspace) { showsAll = false }
                .keyHintHost()
        }
    }
}

/// Один кружок вкладки.
private struct TabCircle: View {
    let database: AppDatabase
    @Bindable var workspace: Workspace
    let tab: WorkspaceTab
    let number: Int

    @Environment(\.lumenTheme) private var theme
    @State private var isHovered = false
    @State private var glyphs: [TabGlyph] = []

    private var isSelected: Bool { tab.id == workspace.selectedTabId }
    private var items: [SidebarItem] { tab.panes.map(\.current) }
    private var title: String {
        glyphs.isEmpty ? "Вкладка \(number)" : glyphs.map(\.title).joined(separator: " · ")
    }

    var body: some View {
        content
            .frame(width: IslandTabs.size - 8, height: IslandTabs.size - 8)
            .background(theme.sheet, in: Circle())
            .clipShape(Circle())
            .frame(width: IslandTabs.size, height: IslandTabs.size)
            .lumenGlass(Circle())
            // Круг, а не квадрат: щелчок по углу мимо кружка не считается. Крестик в углу ловит сам.
            .contentShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(theme.accent, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                // Точка под открытой вкладкой, как у окон в Доке.
                Circle()
                    .fill(theme.accent)
                    .frame(width: 4, height: 4)
                    .offset(y: 9)
                    .opacity(isSelected ? 1 : 0)
            }
            .overlay(alignment: .topTrailing) { closeButton }
            .overlay(alignment: .top) { tooltip }
            .scaleEffect(isHovered && !isSelected ? 1.06 : 1)
            .onHover { hovering in
                withAnimation(LumenMotion.quick) { isHovered = hovering }
            }
            .onTapGesture { workspace.select(tab: tab.id) }
            .keyHint("Вкладка \(number)") { workspace.select(tab: tab.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { workspace.select(tab: tab.id) }
            .accessibilityAction(named: "Закрыть вкладку") { workspace.closeTab(tab.id) }
            .accessibilityIdentifier("tab-\(number)")
            .onDrag {
                workspace.draggingTabId = tab.id
                return TabDrag.itemProvider(for: tab.id)
            } preview: {
                content
                    .frame(width: IslandTabs.size - 8, height: IslandTabs.size - 8)
                    .background(theme.sheet, in: Circle())
                    .clipShape(Circle())
            }
            .onDrop(of: [.lumenTab], isTargeted: nil) { _ in
                guard let id = workspace.draggingTabId else { return false }
                workspace.draggingTabId = nil
                withAnimation(LumenMotion.standard) { workspace.moveTab(id, before: tab.id) }
                return true
            }
            .contextMenu { TabContextMenu(workspace: workspace, tab: tab) }
            .task(id: items) { await observe() }
    }

    /// Что внутри: одна панель целиком, две панели пополам.
    @ViewBuilder
    private var content: some View {
        if glyphs.count > 1 {
            HStack(spacing: 0) {
                ForEach(Array(glyphs.prefix(2).enumerated()), id: \.offset) { _, glyph in
                    TabGlyphView(glyph: glyph, attachments: database.attachments, half: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay { Rectangle().fill(theme.line).frame(width: 1.5) }
        } else if let glyph = glyphs.first {
            TabGlyphView(glyph: glyph, attachments: database.attachments, half: false)
        } else {
            Color.clear
        }
    }

    /// Крестик в углу: виден при наведении, если вкладка не последняя.
    @ViewBuilder
    private var closeButton: some View {
        if isHovered, workspace.tabs.count > 1 {
            Button {
                withAnimation(LumenMotion.standard) { workspace.closeTab(tab.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.background)
                    .frame(width: 17, height: 17)
                    .background(theme.textPrimary, in: Circle())
                    .overlay(Circle().strokeBorder(theme.background, lineWidth: 2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 3, y: -3)
            .help("Закрыть вкладку (⌘W)")
            .accessibilityHidden(true)
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Название над кружком, пока на него наведена мышь.
    @ViewBuilder
    private var tooltip: some View {
        if isHovered, !glyphs.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let kind = glyphs.count > 1 ? "Две панели" : glyphs.first?.kind {
                    Text(kind)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: 260, alignment: .leading)
            .lumenGlass(RoundedRectangle(cornerRadius: 12, style: .continuous), prominent: true)
            .fixedSize()
            .alignmentGuide(.top) { $0[.bottom] + 12 }
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .offset(y: 4)))
        }
    }

    private func observe() async {
        let items = items
        let observation = ValueObservation.tracking { db in try items.map { try TabGlyph.fetch(db, item: $0) } }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) {
                glyphs = value
            }
        } catch {}
    }
}

/// Меню вкладки: и у кружка, и у полоски сверху.
struct TabContextMenu: View {
    @Bindable var workspace: Workspace
    let tab: WorkspaceTab

    var body: some View {
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

/// Список всех вкладок из «+N»: значок, название, крестик.
private struct TabListPopover: View {
    let database: AppDatabase
    @Bindable var workspace: Workspace
    var onDone: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                row(tab, number: index + 1)
            }
            Divider().padding(.vertical, 4)
            Button {
                withAnimation(LumenMotion.standard) { workspace.newTab() }
                onDone()
            } label: {
                Label("Новая вкладка", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
            .keyHint("Новая вкладка") {
                workspace.newTab()
                onDone()
            }
        }
        .font(.callout)
        .padding(8)
        .frame(width: 300)
    }

    private func row(_ tab: WorkspaceTab, number: Int) -> some View {
        let isSelected = tab.id == workspace.selectedTabId
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(tab.panes.enumerated()), id: \.offset) { index, pane in
                    if index > 0 {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.caption2)
                            .foregroundStyle(theme.textSecondary)
                    }
                    WorkspaceItemLabel(database: database, item: pane.current)
                }
            }
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if workspace.tabs.count > 1 {
                Button {
                    withAnimation(LumenMotion.standard) { workspace.closeTab(tab.id) }
                    if workspace.tabs.count < 2 { onDone() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textTertiary)
                .help("Закрыть вкладку")
                .accessibilityLabel("Закрыть вкладку")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.accentSoft)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.select(tab: tab.id)
            onDone()
        }
        .keyHint("Вкладка \(number)") {
            workspace.select(tab: tab.id)
            onDone()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Что нарисовать в кружке вкладки.
struct TabGlyph: Hashable, Sendable {
    var title: String
    /// «Книга», «Заметка», «Папка»… под названием в подсказке.
    var kind: String?
    var icon: String?
    var systemImage: String
    /// Книга: картинка обложки из вложений.
    var cover: String?
    /// Книга без картинки: цвет нарисованной обложки, постоянный для книги.
    var coverSeed: Int?

    static func fetch(_ db: GRDB.Database, item: SidebarItem) throws -> TabGlyph {
        let title = try ItemTitle.fetch(db, item: item)
        var glyph = TabGlyph(title: title.title, icon: title.icon, systemImage: title.systemImage)
        switch item {
        case .source(let id, _), .sourceInfo(let id):
            let source = try Source.fetchOne(db, key: id)
            glyph.kind = source?.format.isBook == false ? "Файл" : "Книга"
            glyph.cover = source?.shownCover
            glyph.coverSeed = Int(id.uuid.1)
            if let source { glyph.systemImage = source.format.symbolName }
        case .page:
            glyph.kind = "Страница"
        case .library(.some):
            glyph.kind = "Папка"
        default:
            glyph.kind = nil
        }
        return glyph
    }
}

/// Значок вкладки: маленькая обложка книги, эмодзи страницы или значок раздела.
private struct TabGlyphView: View {
    let glyph: TabGlyph
    let attachments: AttachmentStore
    /// Половина кружка (вкладка с двумя панелями): всё мельче.
    let half: Bool

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if glyph.cover != nil || glyph.coverSeed != nil {
            cover
        } else if let icon = glyph.icon, !icon.isEmpty {
            Text(icon).font(.system(size: half ? 13 : 18))
        } else {
            Image(systemName: glyph.systemImage)
                .font(.system(size: half ? 11 : 15, weight: .medium))
                .foregroundStyle(theme.textSecondary)
        }
    }

    /// Книжка с корешком, как на полке, только крошечная.
    private var cover: some View {
        let width: CGFloat = half ? 12 : 22
        let height: CGFloat = half ? 18 : 30
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 1.5, bottomLeadingRadius: 1.5, bottomTrailingRadius: 3.5, topTrailingRadius: 3.5,
            style: .continuous
        )
        return ZStack {
            if let name = glyph.cover {
                AttachmentImage(name: name, attachments: attachments, contentMode: .fill, maxPixelSize: 120)
            } else {
                let card = theme.vividCard(glyph.coverSeed ?? 0)
                LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.2)).frame(width: half ? 1.5 : 2.5)
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
