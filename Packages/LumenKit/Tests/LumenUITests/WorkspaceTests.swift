import Foundation
import Testing
@testable import LumenUI

@MainActor
struct WorkspaceTests {
    let a = SidebarItem.page(UUID())
    let b = SidebarItem.page(UUID())
    let c = SidebarItem.page(UUID())

    @Test func backAndForwardWalkTheHistoryLikeABrowser() {
        var history = NavigationHistory(.library(nil))
        history.open(a)
        history.open(b)
        #expect(history.current == b)
        #expect(!history.canGoForward)

        history.goBack()
        #expect(history.current == a)
        history.goBack()
        #expect(history.current == .library(nil))
        #expect(!history.canGoBack)

        history.goForward()
        #expect(history.current == a)
        #expect(history.canGoForward)

        // Новый переход после «Назад» стирает путь вперёд.
        history.open(c)
        #expect(!history.canGoForward)
        history.goBack()
        #expect(history.current == a)
    }

    @Test func openingTheSameScreenAgainDoesNotAddAStep() {
        var history = NavigationHistory(a)
        history.open(a)
        #expect(!history.canGoBack)
    }

    @Test func removedPageDisappearsFromHistory() {
        var history = NavigationHistory(.home)
        history.open(a)
        history.open(b)
        history.open(a)
        history.open(c)
        history.goBack()
        // Сейчас открыта a, позади home, a, b, впереди c.
        history.remove { $0 == a }
        #expect(history.current == b)
        history.goBack()
        #expect(history.current == .home)
        #expect(!history.canGoBack)
        history.goForward()
        history.goForward()
        #expect(history.current == c)
    }

    @Test func historyIsLimited() {
        var history = NavigationHistory(.home)
        for _ in 0..<(NavigationHistory.limit + 20) {
            history.open(.page(UUID()))
        }
        #expect(history.back.count == NavigationHistory.limit)
    }

    @Test func tabsKeepTheirOwnHistory() {
        let workspace = Workspace()
        workspace.open(a)
        workspace.newTab(b)
        #expect(workspace.tabs.count == 2)
        #expect(workspace.current == b)
        #expect(!workspace.canGoBack)

        workspace.select(number: 1)
        #expect(workspace.current == a)
        workspace.goBack()
        #expect(workspace.current == .home)

        workspace.closeTab(workspace.selectedTabId)
        #expect(workspace.tabs.count == 1)
        #expect(workspace.current == b)
        // Последнюю вкладку не закрываем: без неё окну нечего показать.
        workspace.closeTab(workspace.selectedTabId)
        #expect(workspace.tabs.count == 1)
    }

    @Test func splitScreenOpensBesideAndNeverOpensOnePageTwice() {
        let workspace = Workspace()
        workspace.open(a)
        workspace.openBeside(b)
        #expect(workspace.isSplit)
        #expect(workspace.selectedTab.panes.map(\.current) == [a, b])
        #expect(workspace.selectedTab.focusedPane == 1)

        // Ссылка на страницу, открытую слева: переходим в левую панель, второй редактор не открываем.
        workspace.open(a)
        #expect(workspace.selectedTab.panes.map(\.current) == [a, b])
        #expect(workspace.selectedTab.focusedPane == 0)

        // «Назад» работает в активной панели.
        workspace.focus(pane: 1)
        workspace.open(c)
        workspace.goBack()
        #expect(workspace.selectedTab.panes.map(\.current) == [a, b])

        workspace.swapPanes()
        #expect(workspace.selectedTab.panes.map(\.current) == [b, a])
        #expect(workspace.selectedTab.focusedPane == 0)

        workspace.closePane(1)
        #expect(!workspace.isSplit)
        #expect(workspace.current == b)
    }

    @Test func tabsSurviveRelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "WorkspaceTests-\(UUID().uuidString)"))
        let first = Workspace(storageKey: "workspace", defaults: defaults)
        first.open(a)
        first.newTab(b)
        first.openBeside(c)

        let second = Workspace(storageKey: "workspace", defaults: defaults)
        #expect(second.tabs == first.tabs)
        #expect(second.current == c)
        second.select(number: 1)
        second.goBack()
        #expect(second.current == .home)
    }

    @Test func trashedItemsLeaveEveryTab() {
        let workspace = Workspace()
        workspace.open(a)
        workspace.newTab(a)
        workspace.openBeside(b)
        workspace.remove { $0 == a }
        #expect(workspace.tabs.allSatisfy { tab in tab.panes.allSatisfy { $0.current != a } })
        #expect(!workspace.referencedItems.contains(a))
        #expect(workspace.referencedItems.contains(b))
    }
}

@MainActor
struct TabDropTests {
    let a = SidebarItem.page(UUID())
    let b = SidebarItem.page(UUID())
    let c = SidebarItem.page(UUID())

    @Test func tabDroppedOnRightEdgeOpensBesideTheCurrentOne() {
        let workspace = Workspace()
        workspace.open(a)
        workspace.newTab(b)
        let dragged = workspace.selectedTabId
        workspace.select(number: 1)

        workspace.dropTab(dragged, toTrailing: true)
        #expect(workspace.tabs.count == 1)
        #expect(workspace.selectedTab.panes.map(\.current) == [a, b])
        #expect(workspace.selectedTab.focusedPane == 1)
    }

    @Test func tabDroppedOnLeftEdgeGoesLeftAndKeepsItsHistory() {
        let workspace = Workspace()
        workspace.open(a)
        workspace.newTab(b)
        workspace.open(c)
        let dragged = workspace.selectedTabId
        workspace.select(number: 1)

        workspace.dropTab(dragged, toTrailing: false)
        #expect(workspace.selectedTab.panes.map(\.current) == [c, a])
        workspace.goBack()
        #expect(workspace.selectedTab.panes.map(\.current) == [b, a])
    }

    @Test func draggingTheOpenTabPairsItWithItsNeighbour() {
        let workspace = Workspace()
        workspace.open(a)
        workspace.newTab(b)
        workspace.dropTab(workspace.selectedTabId, toTrailing: true)
        #expect(workspace.tabs.count == 1)
        #expect(workspace.selectedTab.panes.map(\.current) == [a, b])
    }

    @Test func droppingOnASplitTabReplacesThePaneOnThatSide() {
        let workspace = Workspace()
        workspace.open(a)
        workspace.openBeside(b)
        workspace.newTab(c)
        let dragged = workspace.selectedTabId
        workspace.select(number: 1)

        workspace.dropTab(dragged, toTrailing: true)
        #expect(workspace.selectedTab.panes.map(\.current) == [a, c])
    }

    @Test func samePageIsNotOpenedTwice() {
        let workspace = Workspace()
        workspace.open(a)
        workspace.newTab(a)
        let dragged = workspace.selectedTabId
        workspace.select(number: 1)
        workspace.dropTab(dragged, toTrailing: true)
        #expect(workspace.tabs.count == 1)
        #expect(!workspace.isSplit)
    }

    @Test func edgesAreTheOuterThirds() {
        #expect(TabDropSide(x: 50, width: 900) == .leading)
        #expect(TabDropSide(x: 450, width: 900) == nil)
        #expect(TabDropSide(x: 850, width: 900) == .trailing)
    }
}
