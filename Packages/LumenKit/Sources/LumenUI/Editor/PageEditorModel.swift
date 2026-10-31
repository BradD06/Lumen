import Foundation
import GRDB
import LumenCore
import LumenStorage
import Observation

/// Состояние открытой страницы. Пока страница открыта, источник правды здесь:
/// правки сразу видны в интерфейсе и с небольшой задержкой пачкой пишутся в базу.
@MainActor
@Observable
final class PageEditorModel {
    let database: AppDatabase
    let pageId: UUID

    private(set) var page: Page?
    private(set) var title = ""
    /// Все блоки страницы в порядке документа (родитель, затем его дети).
    private(set) var blocks: [Block] = [] {
        didSet { rebuildChildIndex() }
    }
    /// Дети каждого блока по порядку, `nil` это верхний уровень. Пересчитывается при каждом изменении блоков.
    private(set) var childIndex: [UUID?: [Block]] = [:]
    private(set) var isLoaded = false
    /// Живые страницы (для выбора ссылки и подписей блоков-ссылок) и обратные ссылки.
    private(set) var links = PageLinksSnapshot.empty
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// Блок, на который нужно перевести фокус. Вью сбрасывает его после применения.
    var focusRequest: UUID?
    /// Блок, в котором сейчас курсор. Вью обновляет его при каждой смене фокуса.
    @ObservationIgnored var focusedBlockId: UUID?
    /// Курсор нужно перевести в заголовок страницы. Вью сбрасывает флаг после применения.
    var focusTitleRequest = false
    /// Блок, который сейчас перетаскивают за ручку.
    @ObservationIgnored var draggingBlockId: UUID?
    /// Где сейчас встанет перетаскиваемый блок. Одно значение на всю страницу,
    /// поэтому подсветка не остаётся на строках, которые курсор уже покинул.
    var dropIndicator: DropIndicator?
    /// Страница, которую нужно открыть (ссылка или новая подстраница). Вью сбрасывает её после перехода.
    var openRequest: UUID?
    /// Книга, которую нужно открыть (из выписки или шапки страницы заметок). Вью сбрасывает её после перехода.
    var openSourceRequest: SourceRequest?

    struct SourceRequest: Equatable {
        var sourceId: UUID
        /// Выделение, к которому прокрутить.
        var highlightId: UUID?
    }

    /// Открывает ссылку на место в уже открытой книге. Ставит читалка, у которой эта заметка рядом.
    /// Возвращает `false`, если ссылка ведёт в другую книгу.
    @ObservationIgnored var openPlaceInReader: ((ExcerptReference) -> Bool)?

    @ObservationIgnored private var dirtyBlocks: Set<UUID> = []
    /// Блоки, которые нужно удалить из базы. Удаляются после записи правок, чтобы каскадное
    /// удаление не забрало блоки, которые только что переехали из удаляемого родителя.
    @ObservationIgnored private var pendingDeletes: Set<UUID> = []
    @ObservationIgnored private var isTitleDirty = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    /// Набор текста подряд в одном поле отменяется одним шагом, а не по букве.
    @ObservationIgnored private var typingGroup: TypingGroup?
    @ObservationIgnored private var lastTypingAt = Date.distantPast

    private static let saveDelay: Duration = .milliseconds(350)
    private static let typingGroupInterval: TimeInterval = 1.5
    private static let undoLimit = 200

    /// Состояние страницы для отмены и повтора.
    private struct Snapshot {
        var title: String
        var blocks: [Block]
    }

    enum TypingGroup: Equatable {
        case title
        case block(UUID)
    }

    init(database: AppDatabase, pageId: UUID) {
        self.database = database
        self.pageId = pageId
    }

    // MARK: Загрузка и сохранение

    /// Загружает страницу один раз: встроенный редактор модель могли загрузить раньше, чем его показали.
    func load() async {
        guard !isLoaded else { return }
        do {
            page = try await database.page(pageId)
            title = page?.title ?? ""
            var loaded = try await database.blocks(of: pageId)
            if loaded.isEmpty {
                let block = Block(pageId: pageId, sortKey: SortKey.between(nil, nil))
                loaded = [block]
                dirtyBlocks.insert(block.id)
                scheduleSave()
            }
            blocks = loaded
            reorder()
            isLoaded = true
        } catch {
            NoticeCenter.shared.report("Не удалось открыть страницу", error)
        }
    }

    /// Следит за списком страниц и обратными ссылками, пока страница открыта.
    func observeLinks() async {
        let pageId = pageId
        let observation = ValueObservation.tracking { db in try PageLinksSnapshot.fetch(db, pageId: pageId) }
        do {
            for try await value in observation.values(in: database.reader) {
                links = value
                // Иконка, обложка и избранное могли поменяться в сайдбаре. Название не трогаем:
                // его источник правды здесь, пока страница открыта.
                if var fresh = value.pages.first(where: { $0.id == pageId }) {
                    fresh.title = title
                    page = fresh
                }
            }
        } catch {
            lumenLog.error("Links observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Немедленно записывает все несохранённые правки и ждёт, пока очередь записей опустеет.
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        await save()
        await lastWrite?.value
    }

    private func markDirty(_ id: UUID) {
        dirtyBlocks.insert(id)
        scheduleSave()
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            await self.save()
        }
    }

    /// Забирает накопленные правки и пишет их в базу.
    ///
    /// Запись идёт в отдельной задаче, которую не отменяет следующий таймер: GRDB не пишет
    /// из отменённой задачи, и забранные правки иначе потерялись бы. Записи выстраиваются
    /// в очередь, чтобы более поздняя правка не обогнала более раннюю.
    private func save() async {
        let pending = blocks.filter { dirtyBlocks.contains($0.id) }
        dirtyBlocks.removeAll()
        let deletes = pendingDeletes
        pendingDeletes.removeAll()
        let newTitle = isTitleDirty ? title : nil
        isTitleDirty = false
        guard newTitle != nil || !pending.isEmpty || !deletes.isEmpty else { return }

        let database = database
        let pageId = pageId
        let previous = lastWrite
        let write = Task {
            await previous?.value
            do {
                if let newTitle {
                    try await database.renamePage(pageId, title: newTitle)
                }
                // Порядок документа: родитель записывается раньше детей.
                for block in pending {
                    try await database.saveBlock(block)
                }
                for id in deletes {
                    try await database.deleteBlock(id)
                }
            } catch {
                NoticeCenter.shared.report("Не удалось сохранить изменения на странице", error)
            }
        }
        lastWrite = write
        await write.value
    }

    /// Удаление блоков из базы при следующей записи. Запоздалая запись их уже не вернёт:
    /// они убраны из несохранённых правок.
    private func enqueueDelete(_ ids: Set<UUID>) {
        dirtyBlocks.subtract(ids)
        pendingDeletes.formUnion(ids)
        scheduleSave()
    }

    // MARK: Отмена и повтор

    /// Запоминает состояние перед правкой. `typing` объединяет набор текста подряд в один шаг.
    func recordUndo(typing group: TypingGroup? = nil) {
        let now = Date()
        if let group, group == typingGroup, now.timeIntervalSince(lastTypingAt) < Self.typingGroupInterval {
            lastTypingAt = now
            return
        }
        typingGroup = group
        lastTypingAt = now
        undoStack.append(Snapshot(title: title, blocks: blocks))
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateUndoState()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(title: title, blocks: blocks))
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(title: title, blocks: blocks))
        restore(snapshot)
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// Возвращает страницу к снимку и записывает в базу только то, что изменилось.
    private func restore(_ snapshot: Snapshot) {
        typingGroup = nil
        let current = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        let restoredIds = Set(snapshot.blocks.map(\.id))
        let removed = blocks.map(\.id).filter { !restoredIds.contains($0) }
        let changed = snapshot.blocks.filter { current[$0.id] != $0 }.map(\.id)

        if title != snapshot.title {
            title = snapshot.title
            isTitleDirty = true
        }
        blocks = snapshot.blocks
        enqueueDelete(Set(removed))
        pendingDeletes.subtract(restoredIds)
        dirtyBlocks.formUnion(changed)
        scheduleSave()
        updateUndoState()
        if let first = changed.first ?? blocks.first?.id {
            focusRequest = first
        }
    }

    // MARK: Страница

    func setTitle(_ value: String) {
        // Return в названии переводит курсор в первый блок.
        let hasReturn = value.contains("\n")
        let newTitle = hasReturn ? value.replacingOccurrences(of: "\n", with: "") : value
        if hasReturn {
            focusFirstBlock()
        }
        guard newTitle != title else { return }
        recordUndo(typing: .title)
        title = newTitle
        isTitleDirty = true
        scheduleSave()
    }

    func setIcon(_ icon: String?) {
        page?.icon = icon
        Task {
            await NoticeCenter.shared.attempt("Не удалось сохранить оформление страницы") {
                try await database.setIcon(pageId, icon: icon)
            }
        }
    }

    func toggleFavorite() {
        guard let page else { return }
        self.page?.isFavorite.toggle()
        Task {
            await NoticeCenter.shared.attempt("Не удалось изменить избранное") {
                try await database.setFavorite(pageId, !page.isFavorite)
            }
        }
    }

    /// Убирает заметку из «Входящих» на верхний уровень дерева страниц.
    func moveOutOfInbox() {
        page?.inInbox = false
        Task {
            await NoticeCenter.shared.attempt("Не удалось переместить") {
                try await database.movePage(pageId, toParent: nil)
            }
        }
    }

    /// Убирает страницу в корзину и показывает плашку «Страница в корзине · Вернуть».
    func trash() async {
        await flush()
        NoticeCenter.shared.moveToTrash(.page(pageId), in: database)
    }

    func setCover(_ cover: PageCover?) {
        page?.pageCover = cover
        Task {
            await NoticeCenter.shared.attempt("Не удалось сохранить оформление страницы") {
                try await database.setCover(pageId, cover: cover)
            }
        }
    }

    func setBackground(_ background: PageBackground?) {
        page?.pageBackground = background
        Task {
            await NoticeCenter.shared.attempt("Не удалось сохранить оформление страницы") {
                try await database.setBackground(pageId, background: background)
            }
        }
    }

    // MARK: Дерево блоков

    /// Дочерние блоки по порядку. `nil` это верхний уровень страницы.
    func children(of parentId: UUID?) -> [Block] {
        childIndex[parentId] ?? []
    }

    /// Заголовки страницы по порядку для карты документа. Заголовок внутри тоггла или колонки
    /// прокручивается к своему блоку верхнего уровня: только они видны прокрутке.
    var outline: [OutlineItem] {
        var items: [OutlineItem] = []
        func walk(_ parentId: UUID?, anchor: UUID?) {
            for block in children(of: parentId) {
                let anchorId = anchor ?? block.id
                if let level = block.type.headingLevel {
                    let title = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    items.append(OutlineItem(
                        id: block.id,
                        title: title.isEmpty ? "Без названия" : title,
                        level: level,
                        anchorId: anchorId
                    ))
                }
                walk(block.id, anchor: anchorId)
            }
        }
        walk(nil, anchor: nil)
        return items
    }

    func findBlock(_ id: UUID?) -> Block? {
        guard let id, let index = position(of: id) else { return nil }
        return blocks[index]
    }

    func position(of id: UUID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    func update(_ id: UUID, _ change: (inout Block) -> Void) {
        guard let index = position(of: id) else { return }
        change(&blocks[index])
        markDirty(id)
    }

    private func rebuildChildIndex() {
        var index: [UUID?: [Block]] = [:]
        for block in blocks {
            index[block.parentBlockId, default: []].append(block)
        }
        childIndex = index
    }

    /// Блок и все его потомки.
    func subtree(of id: UUID) -> [UUID] {
        var result = [id]
        var cursor = 0
        while cursor < result.count {
            result += children(of: result[cursor]).map(\.id)
            cursor += 1
        }
        return result
    }

    /// Выстраивает `blocks` в порядке документа: родитель, затем его дети по `sortKey`.
    /// Блок, чей родитель потерялся, поднимается на верхний уровень.
    func reorder() {
        let ids = Set(blocks.map(\.id))
        for index in blocks.indices {
            if let parent = blocks[index].parentBlockId, !ids.contains(parent) || parent == blocks[index].id {
                blocks[index].parentBlockId = nil
                dirtyBlocks.insert(blocks[index].id)
            }
        }
        let grouped = Dictionary(grouping: blocks, by: \.parentBlockId).mapValues { siblings in
            siblings.sorted { ($0.sortKey, $0.id.uuidString) < ($1.sortKey, $1.id.uuidString) }
        }
        var ordered: [Block] = []
        var visited = Set<UUID>()
        func visit(_ parent: UUID?) {
            for block in grouped[parent] ?? [] where visited.insert(block.id).inserted {
                ordered.append(block)
                visit(block.id)
            }
        }
        visit(nil)
        // Циклы в родителях (повреждённые данные): такие блоки тоже показываем на верхнем уровне.
        for block in blocks where !visited.contains(block.id) {
            var block = block
            block.parentBlockId = nil
            dirtyBlocks.insert(block.id)
            ordered.append(block)
        }
        blocks = ordered
    }

    /// Ключ для вставки среди детей `parentId` сразу после `afterId` (`nil` значит в начало).
    func sortKey(in parentId: UUID?, after afterId: UUID?, excluding excluded: UUID? = nil) -> String {
        let siblings = children(of: parentId).filter { $0.id != excluded }
        guard let afterId, let index = siblings.firstIndex(where: { $0.id == afterId }) else {
            return SortKey.between(nil, siblings.first?.sortKey)
        }
        let upper = index + 1 < siblings.count ? siblings[index + 1].sortKey : nil
        return SortKey.between(siblings[index].sortKey, upper)
    }

    /// Ключ для вставки сразу перед `beforeId`.
    func sortKey(in parentId: UUID?, before beforeId: UUID, excluding excluded: UUID? = nil) -> String {
        let siblings = children(of: parentId).filter { $0.id != excluded }
        guard let index = siblings.firstIndex(where: { $0.id == beforeId }) else {
            return SortKey.between(siblings.last?.sortKey, nil)
        }
        let lower = index > 0 ? siblings[index - 1].sortKey : nil
        return SortKey.between(lower, siblings[index].sortKey)
    }

    @discardableResult
    func insertBlock(
        in parentId: UUID?,
        after afterId: UUID?,
        type: BlockType,
        content: BlockContent = BlockContent()
    ) -> Block {
        let block = Block(
            pageId: pageId,
            parentBlockId: parentId,
            type: type,
            content: content,
            sortKey: sortKey(in: parentId, after: afterId)
        )
        blocks.append(block)
        reorder()
        markDirty(block.id)
        return block
    }

    /// Новый блок сразу после `id`, на том же уровне.
    @discardableResult
    func insertBlock(after id: UUID, type: BlockType, content: BlockContent = BlockContent()) -> Block {
        insertBlock(in: findBlock(id)?.parentBlockId, after: id, type: type, content: content)
    }

    /// Добавляет готовые блоки (копии, служебные блоки колонок) и помечает их для записи.
    /// Порядок документа вызывающий восстанавливает сам через `reorder()`.
    func appendBlocks(_ newBlocks: [Block]) {
        blocks += newBlocks
        dirtyBlocks.formUnion(newBlocks.map(\.id))
    }

    /// Убирает блоки со страницы и ставит их удаление из базы в очередь.
    func removeBlocks(_ ids: Set<UUID>) {
        blocks.removeAll { ids.contains($0.id) }
        enqueueDelete(ids)
    }

    // MARK: Ссылки на страницы

    /// Страницы для меню по `[[` и `@`: сначала недавно изменённые.
    func linkCandidates(_ query: String, limit: Int = 8) -> [Page] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        return links.pages
            .filter { $0.id != pageId }
            .filter { query.isEmpty || $0.displayTitle.lowercased().contains(query) }
            .prefix(limit)
            .map { $0 }
    }

    func linkedPage(_ id: UUID?) -> Page? {
        guard let id else { return nil }
        return links.pages.first { $0.id == id }
    }

    /// Страница, в которую вложена эта, если она подстраница.
    var parentPage: Page? {
        linkedPage(page?.parentId)
    }

    /// Подстраницы этой страницы в их порядке.
    var subpages: [Page] {
        links.pages
            .filter { $0.parentId == pageId && !$0.isDatabaseRow }
            .sorted { $0.sortKey < $1.sortKey }
    }

    /// Заменяет набранный `[[запрос` или `@запрос` ссылкой на страницу. Если до триггера
    /// был текст, он остаётся в блоке, а ссылка встаёт следующим блоком.
    func linkPage(from id: UUID, to targetId: UUID) {
        guard let block = findBlock(id) else { return }
        recordUndo()
        let prefix = MentionTrigger.match(block.text)?.prefix ?? ""
        let remaining = prefix.trimmingCharacters(in: .whitespaces)
        let linkId: UUID
        if remaining.isEmpty {
            update(id) {
                $0.type = .page
                $0.content = BlockContent(pageId: targetId)
            }
            linkId = id
        } else {
            update(id) { $0.text = remaining }
            linkId = insertBlock(after: id, type: .page, content: BlockContent(pageId: targetId)).id
        }
        focusRequest = insertBlock(after: linkId, type: .paragraph).id
    }

    /// Новая подстраница этой страницы со ссылкой на неё вместо блока `id`.
    func createSubpage(from id: UUID, title: String, open: Bool) {
        Task {
            do {
                let child = try await database.createPage(title: title, parentId: pageId)
                linkPage(from: id, to: child.id)
                if open {
                    await flush()
                    openRequest = child.id
                }
            } catch {
                NoticeCenter.shared.report("Не удалось создать подстраницу", error)
            }
        }
    }

    func open(_ pageId: UUID) {
        Task {
            await flush()
            openRequest = pageId
        }
    }

    /// Новая пустая подстраница, сразу открытая.
    func addSubpage() {
        Task {
            do {
                let child = try await database.createPage(parentId: pageId)
                await flush()
                openRequest = child.id
            } catch {
                NoticeCenter.shared.report("Не удалось создать подстраницу", error)
            }
        }
    }
}

/// Заголовок на карте документа.
struct OutlineItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// 1, 2 или 3: чем меньше, тем длиннее полоска.
    let level: Int
    /// Блок верхнего уровня, к которому прокручивать.
    let anchorId: UUID
}

extension BlockType {
    /// Уровень заголовка или `nil` для остальных блоков.
    var headingLevel: Int? {
        switch self {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        default: nil
        }
    }
}
