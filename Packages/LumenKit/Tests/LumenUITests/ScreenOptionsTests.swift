#if os(macOS)
import AppKit
#endif
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

    @Test func windowButtonsShownByDefault() {
        // Кнопки «Назад / Вперёд» видны сразу, на Mac тоже.
        #expect(ScreenOptions.windowButtonsDefault)
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

#if os(macOS)
struct ReaderKeysTests {
    @Test func arrowsTurnPagesOnlyWithoutModifiers() {
        #expect(ReaderKeys.action(keyCode: 124, flags: [.numericPad, .function]) == .turn(forward: true))
        #expect(ReaderKeys.action(keyCode: 125, flags: []) == .turn(forward: true))
        #expect(ReaderKeys.action(keyCode: 123, flags: [.function]) == .turn(forward: false))
        #expect(ReaderKeys.action(keyCode: 126, flags: []) == .turn(forward: false))
        // ⇧ со стрелкой расширяет выделение, ⌘ со стрелкой ходит по строке: их не трогаем.
        #expect(ReaderKeys.action(keyCode: 124, flags: [.shift]) == nil)
        #expect(ReaderKeys.action(keyCode: 124, flags: [.command]) == nil)
        #expect(ReaderKeys.action(keyCode: 0, flags: []) == nil)
    }

    @Test func optionCommandArrowsMoveBetweenBookAndNotes() {
        #expect(ReaderKeys.action(keyCode: 124, flags: [.command, .option, .function]) == .focusNotes)
        #expect(ReaderKeys.action(keyCode: 123, flags: [.command, .option]) == .focusBook)
        #expect(ReaderKeys.action(keyCode: 125, flags: [.command, .option]) == nil)
    }
}
#endif
