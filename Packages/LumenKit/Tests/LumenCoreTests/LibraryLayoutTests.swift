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
}
