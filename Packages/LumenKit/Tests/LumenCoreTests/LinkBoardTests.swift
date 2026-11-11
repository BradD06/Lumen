import Foundation
import Testing
@testable import LumenCore

struct LinkBoardTests {
    let book = LibraryItemID.source(UUID())
    let essay = LibraryItemID.page(UUID())
    let note = LibraryItemID.page(UUID())
    let folder = LibraryItemID.folder(UUID())
    let inner = LibraryItemID.page(UUID())

    @Test func threadsJoinPinnedItemsAndMergePairs() {
        let relations = [
            BoardRelation(essay, book, kind: .excerpt),
            BoardRelation(essay, book, kind: .link),
            BoardRelation(essay, note, kind: .link),
        ]
        let threads = LinkBoard.threads(relations: relations, pinned: [essay, book], container: [:])
        #expect(threads.count == 1)
        let thread = threads.first
        #expect(thread?.touches(essay) == true && thread?.touches(book) == true)
        #expect(thread?.count == 2)
        #expect(thread?.kinds == [.excerpt, .link])
    }

    @Test func pinnedFolderStandsInForWhatLiesInside() {
        // Конспект в папке ссылается на книгу. Конспект не приколот, папка приколота.
        let relations = [BoardRelation(inner, book, kind: .excerpt)]
        let container = [inner: folder]
        let threads = LinkBoard.threads(relations: relations, pinned: [folder, book], container: container)
        #expect(threads.count == 1)
        #expect(threads.first?.touches(folder) == true)
        #expect(threads.first?.touches(book) == true)

        // Приколол и сам конспект: нитка к книге от него, а к папке нитка «лежит в папке».
        let both = LinkBoard.threads(relations: relations, pinned: [folder, book, inner], container: container)
        #expect(both.count == 2)
        #expect(both.contains { $0.touches(inner) && $0.touches(book) })
        #expect(both.contains { $0.touches(inner) && $0.touches(folder) && $0.isContainmentOnly })
    }

    @Test func linksInsideOneFolderMakeNoThread() {
        let other = LibraryItemID.page(UUID())
        let relations = [BoardRelation(inner, other, kind: .link)]
        let threads = LinkBoard.threads(relations: relations, pinned: [folder], container: [inner: folder, other: folder])
        #expect(threads.isEmpty)
    }

    @Test func brokenFolderLoopDoesNotHang() {
        let a = LibraryItemID.folder(UUID())
        let b = LibraryItemID.folder(UUID())
        let threads = LinkBoard.threads(
            relations: [BoardRelation(inner, book, kind: .link)],
            pinned: [book],
            container: [inner: a, a: b, b: a]
        )
        #expect(threads.isEmpty)
    }

    @Test func clusterFollowsThreads() {
        let lonely = LibraryItemID.page(UUID())
        let relations = [
            BoardRelation(essay, book, kind: .excerpt),
            BoardRelation(note, essay, kind: .link),
        ]
        let threads = LinkBoard.threads(relations: relations, pinned: [essay, book, note, lonely], container: [:])
        #expect(LinkBoard.cluster(of: book, threads: threads) == [book, essay, note])
        #expect(LinkBoard.cluster(of: lonely, threads: threads) == [lonely])
        #expect(LinkBoard.neighbors(of: essay, threads: threads) == [book, note])
    }

    @Test func relatedOfFolderLooksInside() {
        let relations = [
            BoardRelation(inner, book, kind: .excerpt),
            BoardRelation(essay, inner, kind: .link),
            BoardRelation(inner, folder, kind: .contains),
        ]
        #expect(LinkBoard.related(to: folder, relations: relations, container: [inner: folder]) == [book, essay])
        #expect(LinkBoard.related(to: book, relations: relations, container: [inner: folder]) == [inner])
        #expect(LinkBoard.linkedItems(relations) == [inner, book, essay])
    }

    @Test func newCardsLieBesideTheirLinksAndNeverOnTopOfOthers() {
        let occupied = [book: LibraryPoint(x: 600, y: 400)]
        let relations = [BoardRelation(essay, book, kind: .excerpt)]
        let threads = LinkBoard.threads(relations: relations, pinned: [book, essay, note], container: [:])
        let placed = BoardLayout.place([essay, note], occupied: occupied, threadsAfter: threads)
        let essayPoint = placed[essay]
        let notePoint = placed[note]
        #expect(essayPoint != nil && notePoint != nil)
        if let essayPoint {
            // Рядом с книгой: в соседней клетке.
            #expect(abs(essayPoint.x - 600) <= BoardLayout.cellWidth + 1)
            #expect(abs(essayPoint.y - 400) <= BoardLayout.cellHeight + 1)
        }
        let all = Array(occupied.values) + Array(placed.values)
        for (index, point) in all.enumerated() {
            let others = all.enumerated().filter { $0.offset != index }.map(\.element)
            #expect(BoardLayout.isFree(point, taken: others))
        }
    }

    @Test func pinKeepsItemIdentity() {
        let pin = BoardPin(item: folder, at: LibraryPoint(x: 10, y: 20))
        #expect(pin.item == folder)
        #expect(pin.kind == .folder)
        #expect(pin.point == LibraryPoint(x: 10, y: 20))
    }
}
