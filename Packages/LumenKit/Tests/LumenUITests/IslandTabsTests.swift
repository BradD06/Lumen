import Foundation
@testable import LumenUI
import Testing

struct IslandTabsTests {
    private func tabs(_ count: Int) -> [WorkspaceTab] {
        (0..<count).map { _ in WorkspaceTab(.home) }
    }

    @Test func allTabsFitWhenThereIsRoom() {
        let list = tabs(3)
        let shown = IslandTabs.shownTabs(list, selected: list[0].id, capacity: 5)
        #expect(shown.map(\.id) == list.map(\.id))
    }

    @Test func lastPlaceGoesToTheCountCircle() {
        let list = tabs(8)
        let shown = IslandTabs.shownTabs(list, selected: list[1].id, capacity: 5)
        #expect(shown.map(\.id) == list.prefix(4).map(\.id))
    }

    @Test func openTabIsAlwaysShown() {
        let list = tabs(8)
        let shown = IslandTabs.shownTabs(list, selected: list[6].id, capacity: 5)
        #expect(shown.count == 4)
        #expect(shown.last?.id == list[6].id)
    }

    @Test func narrowWindowShowsOnlyTheCount() {
        let list = tabs(4)
        #expect(IslandTabs.shownTabs(list, selected: list[0].id, capacity: 1).isEmpty)
    }

    @Test func capacityGrowsWithSpace() {
        #expect(IslandTabs.capacity(space: 40) == 0)
        #expect(IslandTabs.capacity(space: 200) >= 2)
        #expect(IslandTabs.capacity(space: 2000) == IslandTabs.maxShown)
    }
}
