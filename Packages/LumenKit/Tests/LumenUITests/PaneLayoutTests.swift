import Foundation
import Testing
import LumenCore
import LumenStorage
@testable import LumenUI

@MainActor
struct PaneLayoutTests {
    @Test func secondPaneTakesItsShareButNeverSqueezesTheFirst() {
        let half = TwoPaneLayout.lengths(total: 1014, fraction: 0.5, gap: 14, minLength: 300)
        #expect(half.first == 500)
        #expect(half.second == 500)
        // Доля слишком большая: первое окно всё равно не меньше минимума.
        let wide = TwoPaneLayout.lengths(total: 1014, fraction: 0.9, gap: 14, minLength: 300)
        #expect(wide.first == 300)
        #expect(wide.second == 700)
        // Окно меньше двух минимумов: делится пополам.
        let tiny = TwoPaneLayout.lengths(total: 414, fraction: 0.8, gap: 14, minLength: 300)
        #expect(tiny.first == 200)
        #expect(tiny.second == 200)
    }

    @Test func tabsSavedBeforeArrangementStillOpen() throws {
        let tab = WorkspaceTab(.home)
        // Вкладка из прежней версии: в ней ещё нет расположения панелей.
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(tab)) as? [String: Any]
        )
        object.removeValue(forKey: "arrangement")
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkspaceTab.self, from: old)
        #expect(decoded.id == tab.id)
        #expect(decoded.panes == tab.panes)
        #expect(decoded.arrangement == PaneArrangement())
    }

    @Test func splitScreenCanBeStackedAndRemembersIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "PaneLayoutTests-\(UUID().uuidString)"))
        let workspace = Workspace(storageKey: "workspace", defaults: defaults)
        workspace.openBeside(.page(UUID()))
        #expect(workspace.selectedTab.arrangement.axis(isTall: false) == .sideBySide)
        workspace.setPaneAxis(.stacked, isTall: false)
        #expect(workspace.selectedTab.arrangement.axis(isTall: false) == .stacked)

        let reopened = Workspace(storageKey: "workspace", defaults: defaults)
        #expect(reopened.selectedTab.arrangement.axis(isTall: false) == .stacked)
    }

    @Test func readerLayoutIsRememberedPerBook() throws {
        let defaults = try #require(UserDefaults(suiteName: "PaneLayoutTests-\(UUID().uuidString)"))
        let first = UUID()
        let second = UUID()
        defaults.set(0.3, forKey: ReaderLayoutStore.legacyFractionKey)
        // Пока ничего не меняли, ширина заметок берётся из прежней настройки.
        #expect(ReaderLayoutStore.load(first, defaults: defaults).sideFraction == 0.3)

        var stacked = PaneArrangement()
        stacked.setAxis(.stacked, isTall: false)
        stacked.swap()
        ReaderLayoutStore.save(stacked, for: first, defaults: defaults)
        #expect(ReaderLayoutStore.load(first, defaults: defaults) == stacked)
        // Новая книга начинает с последней раскладки.
        #expect(ReaderLayoutStore.load(second, defaults: defaults) == stacked)

        var sideBySide = stacked
        sideBySide.setAxis(.sideBySide, isTall: false)
        ReaderLayoutStore.save(sideBySide, for: second, defaults: defaults)
        #expect(ReaderLayoutStore.load(first, defaults: defaults) == stacked)
        #expect(ReaderLayoutStore.load(second, defaults: defaults) == sideBySide)
    }

    @Test func droppedExcerptGoesIntoTheNoteItWasDroppedOn() async throws {
        let db = try AppDatabase.inMemory()
        let source = try await db.addSource(
            title: "Книга", format: .epub, file: "missing.epub", originalName: "Книга.epub"
        )
        let target = try await db.createPage(title: "Куда бросили")
        let editor = PageEditorModel(database: db, pageId: target.id)
        await editor.load()

        let model = ReaderModel(database: db, sourceId: source.id, highlightId: nil)
        await model.load()
        let highlight = Highlight(
            sourceId: source.id, locator: SourceLocator(section: 0, progression: 0), text: "Рукописи не горят", label: "стр. 289"
        )
        await model.addExcerpt(highlight, into: editor)
        await editor.flush()

        let excerpts = editor.blocks.filter { $0.type == .excerpt }
        #expect(excerpts.map(\.text) == ["Рукописи не горят"])
        #expect(excerpts.first?.content.excerpt?.sourceId == source.id)
        // Заметки к книге ради этого не заводятся.
        #expect(try await db.bookNotesPage(for: source.id) == nil)
    }

    @Test func excerptDragPayloadSurvivesTheTrip() throws {
        let payload = ExcerptDrag.Payload(sourceId: UUID(), highlightId: UUID())
        let data = try JSONEncoder().encode(payload)
        #expect(ExcerptDrag.decode(data) == payload)
        #expect(ExcerptDrag.decode(Data("мусор".utf8)) == nil)
        #expect(ExcerptDrag.decode(nil) == nil)
    }
}
