import Testing
@testable import LumenCore

struct LibraryLayoutTests {
    @Test func cellsGoRowByRow() {
        #expect(LibraryLayout.cell(0, columns: 3) == LibraryLayout.origin)
        let fourth = LibraryLayout.cell(3, columns: 3)
        #expect(fourth.x == LibraryLayout.origin.x)
        #expect(fourth.y == LibraryLayout.origin.y + LibraryLayout.cellHeight)
    }

    @Test func snapsToNearestCellAndNeverBeforeFirst() {
        let near = LibraryPoint(x: LibraryLayout.origin.x + LibraryLayout.cellWidth * 0.6, y: -50)
        #expect(LibraryLayout.snapped(near) == LibraryLayout.cell(1, columns: 10))
    }

    @Test func freeCellsSkipOccupiedPlaces() {
        // Предмет лежит чуть сдвинутым от первой ячейки: она занята, следующая свободна.
        let placed = [LibraryPoint(x: LibraryLayout.origin.x + 20, y: LibraryLayout.origin.y + 10)]
        let free = LibraryLayout.freeCells(count: 2, avoiding: placed, columns: 4)
        #expect(free == [LibraryLayout.cell(1, columns: 4), LibraryLayout.cell(2, columns: 4)])
    }

    @Test func freeCellsDoNotOverlapEachOther() {
        let free = LibraryLayout.freeCells(count: 5, avoiding: [], columns: 2)
        for (i, a) in free.enumerated() {
            for b in free[(i + 1)...] {
                #expect(!LibraryLayout.overlaps(a, b))
            }
        }
    }

    @Test func spotBesideGoesRightThenBelow() {
        let book = LibraryPoint(x: 200, y: 100)
        let right = LibraryPoint(x: book.x + LibraryLayout.cellWidth, y: book.y)
        #expect(LibraryLayout.spot(beside: book, avoiding: []) == right)

        let below = LibraryPoint(x: book.x, y: book.y + LibraryLayout.cellHeight)
        #expect(LibraryLayout.spot(beside: book, avoiding: [right]) == below)
    }

    @Test func spotBesideNeverLeavesTheCanvasOrOverlaps() throws {
        let book = LibraryLayout.origin
        let placed = [
            LibraryPoint(x: book.x + LibraryLayout.cellWidth, y: book.y),
            LibraryPoint(x: book.x, y: book.y + LibraryLayout.cellHeight),
        ]
        let spot = try #require(LibraryLayout.spot(beside: book, avoiding: placed))
        #expect(spot.x >= 0 && spot.y >= 0)
        for other in placed + [book] {
            #expect(!LibraryLayout.overlaps(spot, other))
        }
    }
}
