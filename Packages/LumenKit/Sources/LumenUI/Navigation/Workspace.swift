import Foundation
import Observation
import SwiftUI

/// История переходов одной панели, как в браузере: «Назад» возвращает на шаг,
/// «Вперёд» повторяет шаг, а новый переход после «Назад» стирает путь вперёд.
struct NavigationHistory: Hashable, Codable, Sendable {
    private(set) var back: [SidebarItem] = []
    private(set) var current: SidebarItem
    private(set) var forward: [SidebarItem] = []

    /// Сколько шагов назад помним, чтобы история не росла бесконечно.
    static let limit = 100

    init(_ item: SidebarItem = .home) {
        current = item
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    mutating func open(_ item: SidebarItem) {
        guard item != current else { return }
        back.append(current)
        if back.count > Self.limit {
            back.removeFirst(back.count - Self.limit)
        }
        current = item
        forward.removeAll()
    }

    mutating func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        current = previous
    }

    mutating func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        current = next
    }

    /// Убирает из истории то, чего больше нет (например, страницу в корзине).
    /// Если убрали открытое, панель возвращается на ближайший шаг назад.
    mutating func remove(where shouldRemove: (SidebarItem) -> Bool) {
        back.removeAll(where: shouldRemove)
        forward.removeAll(where: shouldRemove)
        if shouldRemove(current) {
            current = back.popLast() ?? forward.popLast() ?? .home
        }
        // Соседние одинаковые шаги после удаления не нужны: «Назад» должен что-то менять.
        back = Self.collapsed(back)
        while back.last == current { back.removeLast() }
        forward = Self.collapsed(forward)
        while forward.last == current { forward.removeLast() }
    }

    private static func collapsed(_ items: [SidebarItem]) -> [SidebarItem] {
        var result: [SidebarItem] = []
        for item in items where result.last != item {
            result.append(item)
        }
        return result
    }
}

/// Вкладка: одна панель или две рядом (разделённый экран), у каждой своя история.
struct WorkspaceTab: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var panes: [NavigationHistory]
    var focusedPane = 0

    init(_ item: SidebarItem = .home) {
        panes = [NavigationHistory(item)]
    }

    var isSplit: Bool { panes.count > 1 }
    var current: SidebarItem { panes[focusedPane].current }
}

/// Все вкладки окна: что открыто, в какой панели, куда ведут «Назад» и «Вперёд».
/// Сохраняется между запусками, чтобы приложение открывалось там, где закрыли.
@MainActor
@Observable
final class Workspace {
    // Каждое изменение ниже сохраняется сразу (`defer { save() }`).
    private(set) var tabs: [WorkspaceTab]
    private(set) var selectedTabId: UUID

    /// Какую вкладку сейчас тянут мышью или пальцем: её ловят края экрана и другие вкладки.
    /// Наблюдаемое: пока вкладку не тянут, подсветка краёв не показывается.
    var draggingTabId: UUID?
    @ObservationIgnored private let storageKey: String?
    @ObservationIgnored private let defaults: UserDefaults

    static let maxTabs = 20

    init(storageKey: String? = nil, defaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.defaults = defaults
        if let storageKey,
           let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data),
           !saved.tabs.isEmpty {
            tabs = saved.tabs.map(Self.sanitized)
            selectedTabId = saved.tabs.contains { $0.id == saved.selectedTabId } ? saved.selectedTabId : saved.tabs[0].id
        } else {
            let tab = WorkspaceTab()
            tabs = [tab]
            selectedTabId = tab.id
        }
    }

    // MARK: Текущая вкладка и панель

    var selectedIndex: Int {
        tabs.firstIndex { $0.id == selectedTabId } ?? 0
    }

    var selectedTab: WorkspaceTab { tabs[selectedIndex] }

    /// Что открыто в активной панели активной вкладки: это подсвечивает сайдбар.
    var current: SidebarItem { selectedTab.current }

    var canGoBack: Bool { selectedTab.panes[selectedTab.focusedPane].canGoBack }
    var canGoForward: Bool { selectedTab.panes[selectedTab.focusedPane].canGoForward }

    var isSplit: Bool { selectedTab.isSplit }

    // MARK: Переходы

    /// Открывает в панели (по умолчанию в активной). Страницу, которая уже открыта
    /// в соседней панели, второй раз не открываем: два редактора одной страницы
    /// перетирали бы правки друг друга, поэтому просто переходим в ту панель.
    func open(_ item: SidebarItem, inPane pane: Int? = nil) {
        defer { save() }
        let index = selectedIndex
        let pane = pane ?? tabs[index].focusedPane
        guard tabs[index].panes.indices.contains(pane) else { return }
        if let other = tabs[index].panes.indices.first(where: { $0 != pane && tabs[index].panes[$0].current == item }),
           item.isEditable {
            tabs[index].focusedPane = other
            return
        }
        tabs[index].panes[pane].open(item)
        tabs[index].focusedPane = pane
    }

    /// Ссылка из экрана в панели `pane`. В разделённом экране она открывается во второй
    /// половине, а экран со ссылкой остаётся на месте. Если там уже открыта та же книга,
    /// панель только становится активной и ответ `true`: книгу прокручивают, а не открывают заново.
    @discardableResult
    func openLink(_ item: SidebarItem, from pane: Int) -> Bool {
        let tab = tabs[selectedIndex]
        guard tab.isSplit, tab.panes.indices.contains(pane) else {
            open(item, inPane: pane)
            return false
        }
        let target = pane == 0 ? 1 : 0
        if case .source(let id, _) = item, case .source(let openId, _) = tab.panes[target].current, openId == id {
            focus(pane: target)
            return true
        }
        open(item, inPane: target)
        return false
    }

    func goBack() {
        defer { save() }
        let index = selectedIndex
        tabs[index].panes[tabs[index].focusedPane].goBack()
    }

    func goForward() {
        defer { save() }
        let index = selectedIndex
        tabs[index].panes[tabs[index].focusedPane].goForward()
    }

    func focus(pane: Int) {
        defer { save() }
        let index = selectedIndex
        guard tabs[index].panes.indices.contains(pane), tabs[index].focusedPane != pane else { return }
        tabs[index].focusedPane = pane
    }

    // MARK: Вкладки

    func newTab(_ item: SidebarItem = .home) {
        defer { save() }
        guard tabs.count < Self.maxTabs else {
            open(item)
            return
        }
        let tab = WorkspaceTab(item)
        tabs.insert(tab, at: selectedIndex + 1)
        selectedTabId = tab.id
    }

    func select(tab id: UUID) {
        defer { save() }
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabId = id
    }

    /// ⌘1…⌘9: номер вкладки слева направо, ⌘9 всегда последняя, как в браузере.
    func select(number: Int) {
        defer { save() }
        guard !tabs.isEmpty else { return }
        let index = number >= 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        selectedTabId = tabs[index].id
    }

    func selectNextTab() {
        defer { save() }
        selectedTabId = tabs[(selectedIndex + 1) % tabs.count].id
    }

    func selectPreviousTab() {
        defer { save() }
        selectedTabId = tabs[(selectedIndex - 1 + tabs.count) % tabs.count].id
    }

    func closeTab(_ id: UUID) {
        defer { save() }
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = id == selectedTabId
        tabs.remove(at: index)
        if wasSelected {
            selectedTabId = tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeOtherTabs(_ id: UUID) {
        defer { save() }
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tabs = [tab]
        selectedTabId = tab.id
    }

    func moveTab(_ id: UUID, before target: UUID) {
        defer { save() }
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: from)
        let to = tabs.firstIndex(where: { $0.id == target }) ?? tabs.count
        tabs.insert(tab, at: to)
    }

    // MARK: Разделённый экран

    /// Открывает рядом, во второй панели активной вкладки. Если экран ещё не разделён, делит его.
    func openBeside(_ item: SidebarItem) {
        defer { save() }
        let index = selectedIndex
        if !tabs[index].isSplit {
            tabs[index].panes.append(NavigationHistory(.home))
        }
        let target = tabs[index].focusedPane == 0 ? 1 : 0
        open(item, inPane: target)
    }

    /// Делит экран пополам или убирает вторую панель.
    /// Новая панель открывается на главной: оттуда удобно выбрать, что положить рядом.
    func toggleSplit() {
        defer { save() }
        let index = selectedIndex
        if tabs[index].isSplit {
            closePane(tabs[index].panes.count - 1)
        } else {
            tabs[index].panes.append(NavigationHistory(.home))
            tabs[index].focusedPane = 1
        }
    }

    func closePane(_ pane: Int) {
        defer { save() }
        let index = selectedIndex
        guard tabs[index].isSplit, tabs[index].panes.indices.contains(pane) else { return }
        tabs[index].panes.remove(at: pane)
        tabs[index].focusedPane = 0
    }

    /// Вкладку перетащили к краю: она встаёт рядом с открытой вкладкой, слева или справа.
    /// Перетащенная вкладка при этом исчезает из полоски (если в ней были две панели,
    /// уходит только активная). Если тянут саму открытую вкладку, она встаёт рядом с соседней.
    func dropTab(_ id: UUID, toTrailing: Bool) {
        defer { save() }
        guard let draggedIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let dragged = tabs[draggedIndex]
        let moving = dragged.panes[dragged.focusedPane]
        let side = toTrailing ? 1 : 0

        var targetId = selectedTabId
        if id == selectedTabId {
            if dragged.isSplit {
                // Своя вкладка уже разделена: активная панель просто переезжает на нужную сторону.
                if dragged.focusedPane != side {
                    tabs[draggedIndex].panes.swapAt(0, 1)
                    tabs[draggedIndex].focusedPane = side
                }
                return
            }
            guard tabs.count > 1 else { return }
            targetId = tabs[draggedIndex > 0 ? draggedIndex - 1 : draggedIndex + 1].id
        }
        guard let targetIndex = tabs.firstIndex(where: { $0.id == targetId }) else { return }

        var target = tabs[targetIndex]
        // В разделённой вкладке остаётся панель с противоположной стороны, на её место встаёт новая.
        let kept = target.isSplit ? target.panes[1 - side] : target.panes[target.focusedPane]
        if kept.current == moving.current && moving.current.isEditable {
            // Одна и та же страница в двух панелях перетирала бы правки: оставляем одну.
            target.panes = [kept]
            target.focusedPane = 0
        } else {
            target.panes = toTrailing ? [kept, moving] : [moving, kept]
            target.focusedPane = side
        }
        tabs[targetIndex] = target

        if dragged.isSplit {
            tabs[draggedIndex].panes.remove(at: dragged.focusedPane)
            tabs[draggedIndex].focusedPane = 0
        } else {
            tabs.removeAll { $0.id == id }
        }
        selectedTabId = target.id
    }

    /// Меняет панели местами.
    func swapPanes() {
        defer { save() }
        let index = selectedIndex
        guard tabs[index].isSplit else { return }
        tabs[index].panes.swapAt(0, 1)
        tabs[index].focusedPane = 1 - tabs[index].focusedPane
    }

    // MARK: Удалённое

    /// Убирает отовсюду то, чего больше нет: удалённую страницу, книгу или папку.
    func remove(where shouldRemove: (SidebarItem) -> Bool) {
        defer { save() }
        var updated = tabs
        for t in updated.indices {
            for p in updated[t].panes.indices {
                updated[t].panes[p].remove(where: shouldRemove)
            }
        }
        if updated != tabs { tabs = updated }
    }

    /// Все страницы, книги и папки, на которые ссылаются вкладки: их проверяют после запуска.
    var referencedItems: Set<SidebarItem> {
        var items = Set<SidebarItem>()
        for tab in tabs {
            for pane in tab.panes {
                items.insert(pane.current)
                items.formUnion(pane.back)
                items.formUnion(pane.forward)
            }
        }
        return items
    }

    // MARK: Сохранение

    private struct Saved: Codable {
        var tabs: [WorkspaceTab]
        var selectedTabId: UUID
    }

    private func save() {
        guard let storageKey, let data = try? JSONEncoder().encode(Saved(tabs: tabs, selectedTabId: selectedTabId)) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    /// Сохранённая вкладка могла прийти от старой версии: чиним панели и активную панель.
    private static func sanitized(_ tab: WorkspaceTab) -> WorkspaceTab {
        var tab = tab
        if tab.panes.isEmpty { tab.panes = [NavigationHistory()] }
        if tab.panes.count > 2 { tab.panes = Array(tab.panes.prefix(2)) }
        if !tab.panes.indices.contains(tab.focusedPane) { tab.focusedPane = 0 }
        return tab
    }
}

extension SidebarItem {
    /// Экран со своим редактором текста: такой не открываем в двух панелях сразу.
    var isEditable: Bool {
        switch self {
        case .page, .source: true
        default: false
        }
    }
}
