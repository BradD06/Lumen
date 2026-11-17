@testable import LumenUI
import Testing

@MainActor
struct SheetLoaderTests {
    @Test func firstSheetsAreBuiltAtOnce() {
        let loader = SheetLoader()
        #expect(loader.isBuilt(0))
        #expect(loader.isBuilt(SheetLoader.initialSheets - 1))
        #expect(!loader.isBuilt(SheetLoader.initialSheets))
        #expect(!loader.isFinished)
    }

    @Test func revealBuildsOneSheetOutOfTurn() {
        let loader = SheetLoader()
        loader.reveal(9)
        #expect(loader.isBuilt(9))
        #expect(!loader.isBuilt(8))
    }

    @Test func buildRestBuildsEverySheetAndFinishes() async {
        let loader = SheetLoader()
        loader.reveal(3)
        await loader.buildRest(sheetCount: { 6 }, isScrolling: { false }, step: .milliseconds(1))
        #expect(loader.isFinished)
        // Лист, добавленный потом, тоже строится сразу.
        #expect(loader.isBuilt(40))
    }

    @Test func buildRestWaitsWhileScrolling() async {
        let loader = SheetLoader()
        var scrollingSteps = 3
        await loader.buildRest(
            sheetCount: { 4 },
            isScrolling: {
                // Пока листают, очередь не двигается.
                guard scrollingSteps > 0 else { return false }
                scrollingSteps -= 1
                #expect(!loader.isBuilt(SheetLoader.initialSheets))
                return true
            },
            step: .milliseconds(1)
        )
        #expect(scrollingSteps == 0)
        #expect(loader.isFinished)
    }

    @Test func finishBuildsAll() {
        let loader = SheetLoader()
        loader.finish()
        #expect(loader.isBuilt(100))
    }
}
