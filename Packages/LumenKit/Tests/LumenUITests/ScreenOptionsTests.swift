@testable import LumenUI
import Testing

struct ScreenOptionsTests {
    @Test func tabStripShowsOnlyWhenAsked() {
        #expect(TabStripMode.always.shows(tabCount: 1))
        #expect(!TabStripMode.multiple.shows(tabCount: 1))
        #expect(TabStripMode.multiple.shows(tabCount: 2))
        #expect(!TabStripMode.never.shows(tabCount: 5))
    }

    @Test func readerProgressHidesOnlyUnderAMouse() {
        #expect(ReaderProgressMode.always.isVisible(isHovered: false, hasPointer: true))
        #expect(!ReaderProgressMode.hover.isVisible(isHovered: false, hasPointer: true))
        #expect(ReaderProgressMode.hover.isVisible(isHovered: true, hasPointer: true))
        // Без мыши навести нечем: полоса остаётся.
        #expect(ReaderProgressMode.hover.isVisible(isHovered: false, hasPointer: false))
    }

    @Test func keysAreDistinct() {
        let keys = [
            ScreenOptions.tabStripKey, ScreenOptions.windowButtonsKey, ScreenOptions.saveStatusKey,
            ScreenOptions.wordCountKey, ScreenOptions.breadcrumbsKey, ScreenOptions.readerProgressKey,
            ScreenOptions.gridKey, ScreenOptions.homeReadingKey, ScreenOptions.homeTasksKey,
            ScreenOptions.homeInboxKey, ScreenOptions.homeRecentKey, ScreenOptions.sidebarRecentKey,
            ScreenOptions.sidebarFavoritesKey, ScreenOptions.sidebarDatabasesKey, ScreenOptions.sidebarFoldersKey,
        ]
        #expect(Set(keys).count == keys.count)
        // Сетка осталась на старом ключе: у кого она была включена, так и останется.
        #expect(ScreenOptions.gridKey == "library.snapToGrid")
    }
}
