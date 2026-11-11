import Foundation
import GRDB
import LumenCore
import LumenStorage
import Observation
import SwiftUI

/// Доска связей: что приколото, что выбрано, что тащат. Связи и нитки приходят из базы
/// (`BoardSnapshot`), пока доска открыта.
@MainActor
@Observable
final class LinkBoardModel {
    let database: AppDatabase
    private(set) var snapshot = BoardSnapshot.empty
    private(set) var isLoaded = false
    /// Карточка, на которую нажали: её нитки горят, остальные гаснут.
    var selection: LibraryItemID?
    /// «Только эта тема»: видно только то, до чего дотягиваются нитки выбранной карточки.
    var onlyTheme = false
    /// Карточку тащат по доске: где она сейчас, пока её не отпустили.
    private(set) var moving: Moving?
    /// Нитку тянут от кнопки: откуда и где сейчас палец или курсор.
    private(set) var draft: ThreadDraft?

    struct Moving: Equatable {
        var item: LibraryItemID
        var start: CGPoint
        var point: CGPoint
    }

    struct ThreadDraft: Equatable {
        var from: LibraryItemID
        var point: CGPoint
        /// Карточка под концом нитки.
        var target: LibraryItemID?
    }

    init(database: AppDatabase) {
        self.database = database
    }

    func observe() async {
        let observation = ValueObservation.tracking { db in try BoardSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                // Пока карточку держат, её место на доске не прыгает назад.
                snapshot = value
                isLoaded = true
                if let selection, !value.pinnedItems.contains(selection) {
                    self.selection = nil
                }
            }
        } catch {
            lumenLog.error("Link board observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Что видно

    func point(of pin: BoardPin) -> CGPoint {
        if let moving, moving.item == pin.item { return moving.point }
        return CGPoint(x: pin.x, y: pin.y)
    }

    func point(of item: LibraryItemID) -> CGPoint? {
        snapshot.pins.first { $0.item == item }.map(point(of:))
    }

    /// Что показано в режиме «Только эта тема». `nil`, когда видно всё.
    var visibleItems: Set<LibraryItemID>? {
        guard onlyTheme, let selection else { return nil }
        return LinkBoard.cluster(of: selection, threads: snapshot.threads)
    }

    func isVisible(_ item: LibraryItemID) -> Bool {
        visibleItems?.contains(item) ?? true
    }

    /// Карточка не связана с выбранной: она приглушена.
    func isDimmed(_ item: LibraryItemID) -> Bool {
        guard let selection, item != selection else { return false }
        return !neighbors(of: selection).contains(item)
    }

    func neighbors(of item: LibraryItemID) -> Set<LibraryItemID> {
        LinkBoard.neighbors(of: item, threads: snapshot.threads)
    }

    func threadCount(of item: LibraryItemID) -> Int {
        snapshot.threads.filter { $0.touches(item) }.count
    }

    /// Сколько места нужно доске: все карточки и запас вокруг.
    func canvasSize(minimum: CGSize) -> CGSize {
        let points = snapshot.pins.map(point(of:))
        let maxX = points.map(\.x).max() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return CGSize(
            width: max(minimum.width, maxX + BoardLayout.cellWidth),
            height: max(minimum.height, maxY + BoardLayout.cellHeight)
        )
    }

    func title(of item: LibraryItemID) -> String {
        switch item {
        case .page(let id): snapshot.pages[id]?.displayTitle ?? "Заметка"
        case .source(let id): snapshot.sources[id]?.displayTitle ?? "Книга"
        case .folder(let id): snapshot.folders[id]?.displayName ?? "Папка"
        }
    }

    /// Карточка под точкой доски (верхняя, если они лежат друг на друге).
    func item(at point: CGPoint, excluding excluded: LibraryItemID? = nil) -> LibraryItemID? {
        for pin in snapshot.pins.reversed() where pin.item != excluded && isVisible(pin.item) {
            let center = self.point(of: pin)
            let size = BoardCardMetrics.size(of: pin.kind)
            let frame = CGRect(
                x: center.x - size.width / 2, y: center.y - size.height / 2,
                width: size.width, height: size.height
            ).insetBy(dx: -8, dy: -8)
            if frame.contains(point) { return pin.item }
        }
        return nil
    }

    // MARK: Выбор

    func toggleSelection(_ item: LibraryItemID) {
        withAnimation(.snappy) {
            selection = selection == item ? nil : item
            if selection == nil { onlyTheme = false }
        }
        LumenSounds.play(.tap)
    }

    func clearSelection() {
        guard selection != nil else { return }
        withAnimation(.snappy) {
            selection = nil
            onlyTheme = false
        }
    }

    // MARK: Перенос карточек

    func drag(_ item: LibraryItemID, by translation: CGSize) {
        if moving?.item != item {
            guard let start = point(of: item) else { return }
            moving = Moving(item: item, start: start, point: start)
            LumenSounds.play(.pickUp)
        }
        guard var moving else { return }
        moving.point = CGPoint(
            x: max(BoardCardMetrics.margin, moving.start.x + translation.width),
            y: max(BoardCardMetrics.margin, moving.start.y + translation.height)
        )
        self.moving = moving
    }

    func endDrag(_ item: LibraryItemID) {
        guard let moving, moving.item == item else { return }
        let point = LibraryPoint(x: Double(moving.point.x), y: Double(moving.point.y))
        // Место сразу в снимке, чтобы карточка не прыгнула назад до ответа базы.
        if let index = snapshot.pins.firstIndex(where: { $0.item == item }) {
            snapshot.pins[index].point = point
        }
        self.moving = nil
        LumenSounds.play(.drop)
        let database = database
        Task {
            await NoticeCenter.shared.attempt("Не удалось передвинуть карточку") {
                try await database.moveBoardPin(item, to: point)
            }
        }
    }

    // MARK: Приколоть и снять

    /// Прикалывает вещи. Связанные с уже приколотым ложатся рядом с ним, остальные в свободные места.
    func pin(_ items: [LibraryItemID]) {
        let fresh = items.filter { !snapshot.pinnedItems.contains($0) && snapshot.isAlive($0) }
        guard !fresh.isEmpty else { return }
        let occupied = Dictionary(
            snapshot.pins.map { ($0.item, $0.point) },
            uniquingKeysWith: { first, _ in first }
        )
        let threads = LinkBoard.threads(
            relations: snapshot.relations,
            pinned: snapshot.pinnedItems.union(fresh),
            container: snapshot.container
        )
        let placements = BoardLayout.place(fresh, occupied: occupied, threadsAfter: threads)
        let database = database
        Task {
            let done = await NoticeCenter.shared.attempt("Не удалось приколоть") {
                try await database.pinToBoard(placements)
            }
            if done { LumenSounds.play(.pin) }
        }
    }

    func pinAllLinked() {
        pin(snapshot.unpinnedLinkedItems.sorted { $0.boardKey < $1.boardKey })
    }

    /// Прикалывает всё, с чем вещь связана сама (у папки: то, что лежит в ней).
    func pinRelated(of item: LibraryItemID) {
        let related = LinkBoard.related(to: item, relations: snapshot.relations, container: snapshot.container)
            .subtracting(snapshot.pinnedItems)
        guard !related.isEmpty else {
            NoticeCenter.shared.show("Всё, что связано с «\(title(of: item))», уже на доске")
            return
        }
        pin(related.sorted { $0.boardKey < $1.boardKey })
    }

    func relatedToPinCount(of item: LibraryItemID) -> Int {
        LinkBoard.related(to: item, relations: snapshot.relations, container: snapshot.container)
            .subtracting(snapshot.pinnedItems)
            .count
    }

    func unpin(_ item: LibraryItemID) {
        if selection == item { clearSelection() }
        let database = database
        Task {
            let done = await NoticeCenter.shared.attempt("Не удалось снять с доски") {
                try await database.unpinFromBoard([item])
            }
            if done { LumenSounds.play(.tap) }
        }
    }

    // MARK: Новая нитка

    func drawThread(from item: LibraryItemID, to point: CGPoint) {
        if draft == nil { LumenSounds.play(.pickUp) }
        draft = ThreadDraft(from: item, point: point, target: self.item(at: point, excluding: item))
    }

    func finishThread() {
        guard let draft else { return }
        self.draft = nil
        guard let target = draft.target else { return }
        Task { await connect(draft.from, target) }
    }

    func cancelThread() {
        draft = nil
    }

    /// Натянули нитку: в заметку на одном из концов записывается ссылка на другой конец.
    /// В тетрадь от руки текст не вписать, в книгу и папку тоже: тогда пишем в другую заметку.
    func connect(_ from: LibraryItemID, _ to: LibraryItemID) async {
        guard from != to else { return }
        let writer: UUID
        let target: LibraryItemID
        if case .page(let id) = from, canHoldLink(id), to.isLinkTarget {
            writer = id
            target = to
        } else if case .page(let id) = to, canHoldLink(id), from.isLinkTarget {
            writer = id
            target = from
        } else {
            NoticeCenter.shared.show("Нитку натягивают от заметки к заметке или к книге: ссылка записывается в текст заметки")
            return
        }
        if isLinked(page: writer, to: target) {
            NoticeCenter.shared.show("«\(title(of: .page(writer)))» уже ссылается на «\(title(of: target))»")
            return
        }
        let editor: PageEditorModel
        if let open = OpenPageEditors.shared.model(for: writer), open.isLoaded {
            editor = open
        } else {
            editor = PageEditorModel(database: database, pageId: writer)
            await editor.load()
            guard editor.isLoaded else { return }
        }
        editor.appendBoardLink(to: target, title: title(of: target))
        await editor.flush()
        LumenSounds.play(.create)
        NoticeCenter.shared.show("Ссылка на «\(title(of: target))» записана в «\(title(of: .page(writer)))»")
    }

    private func canHoldLink(_ pageId: UUID) -> Bool {
        guard let page = snapshot.pages[pageId] else { return false }
        return !page.isNotebook
    }

    private func isLinked(page: UUID, to target: LibraryItemID) -> Bool {
        snapshot.relations.contains { relation in
            relation.kind != .contains && relation.from == .page(page) && relation.to == target
        }
    }
}

private extension LibraryItemID {
    /// На что можно сослаться из текста заметки.
    var isLinkTarget: Bool {
        switch self {
        case .page, .source: true
        case .folder: false
        }
    }
}

extension PageEditorModel {
    /// Ссылка с доски связей в конец страницы: блок «Страница» или строчка со ссылкой на книгу.
    /// Пустой абзац в конце остаётся последним, чтобы сразу дописать мысль.
    func appendBoardLink(to target: LibraryItemID, title: String) {
        recordUndo()
        let topLevel = children(of: nil)
        var after = topLevel.last?.id
        if let last = topLevel.last, last.type == .paragraph, last.text.isEmpty, children(of: last.id).isEmpty {
            after = topLevel.dropLast().last?.id
        }
        switch target {
        case .page(let id):
            insertBlock(in: nil, after: after, type: .page, content: BlockContent(pageId: id))
        case .source(let id):
            let runs = [
                TextRun("Книга: "),
                TextRun(title, link: LumenLink.source(id).url.absoluteString),
            ]
            insertBlock(in: nil, after: after, type: .paragraph, content: BlockContent(runs: runs))
        case .folder:
            return
        }
    }
}
