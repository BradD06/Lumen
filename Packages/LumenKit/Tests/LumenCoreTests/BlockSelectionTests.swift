import Foundation
import Testing
@testable import LumenCore

struct BlockSelectionTests {
    private let pageId = UUID()

    private func block(_ text: String, parent: UUID? = nil, key: String, type: BlockType = .paragraph) -> Block {
        Block(pageId: pageId, parentBlockId: parent, type: type, content: BlockContent(text: text), sortKey: key)
    }

    @Test func rootsSkipBlocksWhoseAncestorIsSelected() {
        let a = block("а", key: "a")
        let child = block("ребёнок", parent: a.id, key: "a")
        let grandchild = block("внук", parent: child.id, key: "a")
        let b = block("б", key: "b")
        let blocks = [a, child, grandchild, b]

        #expect(BlockSelection.roots([grandchild.id, a.id, b.id], in: blocks) == [a.id, b.id])
        #expect(BlockSelection.roots([grandchild.id, b.id], in: blocks) == [grandchild.id, b.id])
        #expect(BlockSelection.roots([], in: blocks).isEmpty)
    }

    @Test func rangeGoesBothWays() {
        let ids = (0..<5).map { _ in UUID() }
        #expect(BlockSelection.range(from: ids[1], to: ids[3], in: ids) == Array(ids[1...3]))
        #expect(BlockSelection.range(from: ids[3], to: ids[1], in: ids) == Array(ids[1...3]))
        #expect(BlockSelection.range(from: UUID(), to: ids[2], in: ids) == [ids[2]])
    }

    @Test(arguments: [(1, "1 блок"), (3, "3 блока"), (5, "5 блоков"), (11, "11 блоков"), (21, "21 блок"), (14, "14 блоков")])
    func caption(count: Int, text: String) {
        #expect(BlockSelection.blocksCaption(count) == text)
    }

    @Test func clipboardCopiesSubtreesWithNewIds() throws {
        let toggle = block("тоггл", key: "a", type: .toggle)
        let inside = block("внутри", parent: toggle.id, key: "a")
        let other = block("другой", key: "b")
        let pageBreak = block("", key: "c", type: .sheetBreak)
        let clipboard = BlockClipboard.make(roots: [toggle.id, other.id, pageBreak.id], from: [toggle, inside, other, pageBreak])
        #expect(clipboard.blocks.map(\.text) == ["тоггл", "внутри", "другой"], "Граница листа не копируется")
        #expect(clipboard.rootIds == [toggle.id, other.id])

        let data = try JSONEncoder().encode(clipboard)
        let decoded = try JSONDecoder().decode(BlockClipboard.self, from: data)
        #expect(decoded == clipboard)

        let target = UUID()
        let parent = UUID()
        let copies = decoded.copies(pageId: target, parentId: parent, rootKeys: ["m", "n"])
        #expect(copies.roots.count == 2)
        #expect(Set(copies.blocks.map(\.id)).isDisjoint(with: clipboard.blocks.map(\.id)))
        #expect(copies.blocks.allSatisfy { $0.pageId == target })
        let copiedToggle = try #require(copies.blocks.first { $0.text == "тоггл" })
        let copiedInside = try #require(copies.blocks.first { $0.text == "внутри" })
        #expect(copiedToggle.parentBlockId == parent)
        #expect(copiedToggle.sortKey == "m")
        #expect(copiedInside.parentBlockId == copiedToggle.id)
        #expect(copiedInside.sortKey == "a")
    }
}

struct ImageSizingTests {
    @Test func defaultSizeIsFullWidthButNotTooTall() {
        let wide = ImageSizing.size(widthShare: nil, aspect: nil, natural: 0.5, available: 600)
        #expect(wide.width == 600)
        #expect(wide.height == 300)
        let tall = ImageSizing.size(widthShare: nil, aspect: nil, natural: 2, available: 600)
        #expect(tall.height == ImageSizing.defaultMaxHeight)
        #expect(tall.width == ImageSizing.defaultMaxHeight / 2)
    }

    @Test func storedShareAndShapeKeepTheLookOnAnotherWidth() {
        let custom = ImageSizing.size(widthShare: 0.5, aspect: 1, natural: 0.5, available: 800)
        #expect(custom.width == 400)
        #expect(custom.height == 400)
        let phone = ImageSizing.size(widthShare: 0.5, aspect: 1, natural: 0.5, available: 300)
        #expect(phone.width == 150)
        #expect(phone.height == 150)
    }

    @Test func storedSnapsToFullWidthAndNaturalShape() {
        let full = ImageSizing.stored(width: 595, height: 297, available: 600, natural: 0.5, keepsShape: false, currentAspect: nil)
        #expect(full.widthShare == 1)
        #expect(full.aspect == nil, "Почти как у снимка: исходная форма")
        let square = ImageSizing.stored(width: 300, height: 300, available: 600, natural: 0.5, keepsShape: false, currentAspect: nil)
        #expect(square.widthShare == 0.5)
        #expect(square.aspect == 1)
        let widthOnly = ImageSizing.stored(width: 300, height: 999, available: 600, natural: 0.5, keepsShape: true, currentAspect: 0.8)
        #expect(widthOnly.aspect == 0.8)
    }

    @Test func oldContentWithoutSizeStillDecodes() throws {
        let data = Data(#"{"runs":[],"isChecked":false,"attachment":"a.png","isCollapsed":false}"#.utf8)
        let content = try JSONDecoder().decode(BlockContent.self, from: data)
        #expect(content.imageWidth == nil)
        #expect(content.imageAspect == nil)
        var sized = content
        sized.imageWidth = 0.4
        sized.imageAspect = 1.5
        let round = try JSONDecoder().decode(BlockContent.self, from: JSONEncoder().encode(sized))
        #expect(round.imageWidth == 0.4)
        #expect(round.imageAspect == 1.5)
    }
}
