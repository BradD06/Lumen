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

    private enum TypingGroup: Equatable {
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
            print("Failed to load page \(pageId): \(error)")
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
            print("Links observation failed: \(error)")
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

    private func scheduleSave() {
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
                print("Failed to save page \(pageId): \(error)")
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
    private func recordUndo(typing group: TypingGroup? = nil) {
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
        Task { try? await database.setIcon(pageId, icon: icon) }
    }

    func toggleFavorite() {
        guard let page else { return }
        self.page?.isFavorite.toggle()
        Task { try? await database.setFavorite(pageId, !page.isFavorite) }
    }

    /// Убирает заметку из «Входящих» на верхний уровень дерева страниц.
    func moveOutOfInbox() {
        page?.inInbox = false
        Task { try? await database.movePage(pageId, toParent: nil) }
    }

    func trash() async {
        await flush()
        try? await database.trashPage(pageId)
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

    private func position(of id: UUID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout Block) -> Void) {
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
    private func subtree(of id: UUID) -> [UUID] {
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
    private func reorder() {
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
    private func sortKey(in parentId: UUID?, after afterId: UUID?, excluding excluded: UUID? = nil) -> String {
        let siblings = children(of: parentId).filter { $0.id != excluded }
        guard let afterId, let index = siblings.firstIndex(where: { $0.id == afterId }) else {
            return SortKey.between(nil, siblings.first?.sortKey)
        }
        let upper = index + 1 < siblings.count ? siblings[index + 1].sortKey : nil
        return SortKey.between(siblings[index].sortKey, upper)
    }

    /// Ключ для вставки сразу перед `beforeId`.
    private func sortKey(in parentId: UUID?, before beforeId: UUID, excluding excluded: UUID? = nil) -> String {
        let siblings = children(of: parentId).filter { $0.id != excluded }
        guard let index = siblings.firstIndex(where: { $0.id == beforeId }) else {
            return SortKey.between(siblings.last?.sortKey, nil)
        }
        let lower = index > 0 ? siblings[index - 1].sortKey : nil
        return SortKey.between(lower, siblings[index].sortKey)
    }

    @discardableResult
    private func insertBlock(
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
    private func insertBlock(after id: UUID, type: BlockType, content: BlockContent = BlockContent()) -> Block {
        insertBlock(in: findBlock(id)?.parentBlockId, after: id, type: type, content: content)
    }

    // MARK: Блоки

    func focusFirstBlock() {
        focusRequest = blocks.first { $0.type.hasText }?.id ?? blocks.first?.id
    }

    /// Нажатие на пустое место под блоками: фокус в последний пустой абзац или новый абзац в конце.
    func focusEnd() {
        let topLevel = children(of: nil)
        if let last = topLevel.last, last.type == .paragraph, last.text.isEmpty {
            focusRequest = last.id
        } else {
            focusRequest = insertBlock(in: nil, after: topLevel.last?.id, type: .paragraph).id
        }
    }

    func updateText(_ id: UUID, to newText: String) {
        guard let block = findBlock(id) else { return }

        if newText.contains("\n"), block.type != .code {
            recordUndo()
            split(id, text: newText)
            return
        }

        // В коде Return переносит строку. Return на пустой последней строке выходит из блока.
        if block.type == .code, newText.hasSuffix("\n\n"), newText.count > block.text.count {
            recordUndo()
            leaveCodeBlock(id, text: String(newText.dropLast(2)))
            return
        }

        if block.type == .paragraph, let shortcut = MarkdownShortcut.match(newText) {
            recordUndo()
            update(id) {
                $0.type = shortcut.type
                $0.text = shortcut.remainder
            }
            if shortcut.type == .divider {
                focusRequest = insertBlock(after: id, type: .paragraph).id
            } else {
                // Блок другого типа рисуется новым полем: курсор нужно вернуть в него.
                focusRequest = id
            }
            return
        }

        guard block.text != newText else { return }
        recordUndo(typing: .block(id))
        update(id) { $0.text = newText }
    }

    /// Return в конце блока (на macOS приходит как submit, а не как перевод строки).
    func submit(_ id: UUID) {
        guard let block = findBlock(id) else { return }
        recordUndo()
        if block.type == .code {
            if block.text.hasSuffix("\n") {
                leaveCodeBlock(id, text: String(block.text.dropLast()))
            } else {
                update(id) { $0.text += "\n" }
                // Курсор переходит на новую строку в конце блока.
                focusRequest = id
            }
            return
        }
        split(id, text: block.text + "\n")
    }

    /// Второй Return подряд в блоке кода: лишняя пустая строка убирается, ниже появляется абзац.
    private func leaveCodeBlock(_ id: UUID, text: String) {
        update(id) { $0.text = text }
        focusRequest = insertBlock(after: id, type: .paragraph).id
    }

    /// Делит блок по переводам строки: первая строка остаётся, остальные становятся новыми блоками.
    /// Return в пустом пункте списка выходит из списка (или из вложенности), как в Notion.
    /// В раскрытом сворачиваемом блоке новые строки становятся его первыми детьми.
    private func split(_ id: UUID, text: String) {
        guard let block = findBlock(id) else { return }
        let lines = text.components(separatedBy: "\n")

        if block.type.continuation != .paragraph, lines.allSatisfy(\.isEmpty) {
            if isNested(block) {
                outdent(id, recording: false)
            } else {
                update(id) {
                    $0.type = .paragraph
                    $0.text = ""
                }
            }
            focusRequest = id
            return
        }

        update(id) { $0.text = lines[0] }

        let opensInside = block.type == .toggle && !block.content.isCollapsed
        var lastId = id
        for (offset, line) in lines.dropFirst().enumerated() {
            let content = BlockContent(text: line)
            if opensInside && offset == 0 {
                lastId = insertBlock(in: id, after: nil, type: .paragraph, content: content).id
            } else {
                let type = opensInside ? BlockType.paragraph : block.type.continuation
                lastId = insertBlock(after: lastId, type: type, content: content).id
            }
        }
        focusRequest = lastId
    }

    /// Меняет тип блока (из slash-меню или контекстного меню).
    /// «Страница» создаёт новую подстраницу и сразу открывает её, как в Notion.
    func setType(_ id: UUID, _ type: BlockType) {
        guard let block = findBlock(id) else { return }
        if type == .page {
            createSubpage(from: id, title: "", open: true)
            return
        }
        recordUndo()
        update(id) {
            $0.type = type
            if !type.hasText || block.text.hasPrefix("/") {
                $0.text = ""
            }
        }
        if type.hasText {
            focusRequest = id
        } else {
            focusRequest = insertBlock(after: id, type: .paragraph).id
        }
    }

    func toggleChecked(_ id: UUID) {
        recordUndo()
        update(id) { $0.content.isChecked.toggle() }
    }

    /// Свернуть или раскрыть сворачиваемый блок. Это не правка текста, поэтому в историю отмены не попадает.
    func toggleCollapsed(_ id: UUID) {
        update(id) { $0.content.isCollapsed.toggle() }
    }

    /// Пустой раскрытый сворачиваемый блок: первый абзац внутри него.
    func addFirstChild(to id: UUID) {
        recordUndo()
        update(id) { $0.content.isCollapsed = false }
        focusRequest = insertBlock(in: id, after: nil, type: .paragraph).id
    }

    func setTextColor(_ id: UUID, _ color: BlockColor?) {
        recordUndo()
        update(id) {
            $0.content.textColor = color
        }
    }

    func setBackgroundColor(_ id: UUID, _ color: BlockColor?) {
        recordUndo()
        update(id) {
            $0.content.backgroundColor = color
        }
    }

    /// Backspace в пустом блоке: особый блок сначала становится абзацем, вложенный абзац
    /// поднимается на уровень выше, пустой абзац удаляется. Возвращает `true`, если нажатие обработано.
    func backspaceInEmptyBlock(_ id: UUID) -> Bool {
        guard let block = findBlock(id), block.text.isEmpty else { return false }
        if block.type != .paragraph {
            recordUndo()
            update(id) { $0.type = .paragraph }
            return true
        }
        if isNested(block) {
            outdent(id)
            return true
        }
        // Пустой блок удаляется, курсор встаёт в конец блока выше. Единственный блок на странице остаётся.
        guard children(of: id).isEmpty, blocks.contains(where: { $0.id != id && $0.type.hasText }) else {
            return false
        }
        let isFirst = blocks.first { $0.type.hasText }?.id == id
        deleteBlock(id)
        if isFirst {
            // Выше блоков нет: как в Notion, курсор уходит в заголовок.
            focusRequest = nil
            focusTitleRequest = true
        }
        return true
    }

    /// Удаляет блок вместе со всеми вложенными.
    func deleteBlock(_ id: UUID) {
        guard let index = position(of: id) else { return }
        recordUndo()
        let removed = Set(subtree(of: id))
        let previous = blocks[..<index].last { $0.type.hasText && !removed.contains($0.id) }
        blocks.removeAll { removed.contains($0.id) }
        enqueueDelete(removed)
        normalizeColumns()
        if blocks.isEmpty {
            insertBlock(in: nil, after: nil, type: .paragraph)
        }
        focusRequest = previous?.id ?? blocks.first?.id
    }

    /// Копия блока со всеми вложенными сразу под оригиналом.
    func duplicateBlock(_ id: UUID) {
        guard let original = findBlock(id), !original.type.isLayout else { return }
        recordUndo()
        var newIds: [UUID: UUID] = [:]
        for blockId in subtree(of: id) {
            newIds[blockId] = UUID()
        }
        var copies: [Block] = []
        for blockId in subtree(of: id) {
            guard var copy = findBlock(blockId), let newId = newIds[blockId] else { continue }
            copy.id = newId
            copy.createdAt = Date()
            copy.updatedAt = copy.createdAt
            if blockId == id {
                copy.sortKey = sortKey(in: original.parentBlockId, after: id)
            } else {
                copy.parentBlockId = copy.parentBlockId.flatMap { newIds[$0] }
            }
            copies.append(copy)
        }
        blocks += copies
        reorder()
        dirtyBlocks.formUnion(copies.map(\.id))
        scheduleSave()
        focusRequest = newIds[id]
    }

    // MARK: Вложенность

    /// Вложен ли блок в обычный блок (а не лежит на верхнем уровне или прямо в колонке).
    private func isNested(_ block: Block) -> Bool {
        guard let parent = self.findBlock(block.parentBlockId) else { return false }
        return !parent.type.isLayout
    }

    func canIndent(_ id: UUID) -> Bool {
        guard let block = findBlock(id) else { return false }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }), index > 0 else { return false }
        return siblings[index - 1].type.canNest
    }

    func canOutdent(_ id: UUID) -> Bool {
        guard let block = findBlock(id) else { return false }
        return isNested(block)
    }

    /// Tab: блок становится последним ребёнком предыдущего соседа.
    func indent(_ id: UUID) {
        guard canIndent(id), let block = findBlock(id) else { return }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return }
        let newParent = siblings[index - 1]
        recordUndo()
        if newParent.content.isCollapsed {
            update(newParent.id) { $0.content.isCollapsed = false }
        }
        let key = SortKey.between(children(of: newParent.id).last?.sortKey, nil)
        update(id) {
            $0.parentBlockId = newParent.id
            $0.sortKey = key
        }
        reorder()
        focusRequest = id
    }

    /// ⇧Tab: блок выходит на уровень выше и встаёт сразу после бывшего родителя.
    func outdent(_ id: UUID) {
        outdent(id, recording: true)
    }

    private func outdent(_ id: UUID, recording: Bool) {
        guard let block = findBlock(id), isNested(block), let parent = self.findBlock(block.parentBlockId) else { return }
        if recording {
            recordUndo()
        }
        let key = sortKey(in: parent.parentBlockId, after: parent.id)
        update(id) {
            $0.parentBlockId = parent.parentBlockId
            $0.sortKey = key
        }
        reorder()
        focusRequest = id
    }

    // MARK: Перемещение

    /// Ставит блок рядом с другим на его уровне: перед ним или после него.
    func moveBlock(_ id: UUID, nextTo targetId: UUID, after: Bool) {
        guard id != targetId, let target = findBlock(targetId), findBlock(id) != nil,
              !subtree(of: id).contains(targetId) else { return }
        recordUndo()
        let key = after
            ? sortKey(in: target.parentBlockId, after: targetId, excluding: id)
            : sortKey(in: target.parentBlockId, before: targetId, excluding: id)
        update(id) {
            $0.parentBlockId = target.parentBlockId
            $0.sortKey = key
        }
        reorder()
        normalizeColumns()
    }

    /// Ставит блок на место другого: при перетаскивании вниз он встаёт после цели, вверх перед ней.
    func moveBlock(_ id: UUID, onto targetId: UUID) {
        guard let from = position(of: id), let to = position(of: targetId) else { return }
        moveBlock(id, nextTo: targetId, after: from < to)
    }

    /// Сдвигает блок на одну позицию среди соседей вверх (`-1`) или вниз (`+1`).
    func moveBlock(_ id: UUID, by offset: Int) {
        guard let block = findBlock(id) else { return }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }), siblings.indices.contains(index + offset) else {
            return
        }
        moveBlock(id, nextTo: siblings[index + offset].id, after: offset > 0)
        focusRequest = id
    }

    // MARK: Колонки

    /// Ставит блок в колонку рядом с другим блоком, как при перетаскивании к правому краю в Notion.
    func placeBeside(_ id: UUID, _ targetId: UUID) {
        guard id != targetId, let target = findBlock(targetId), let moving = findBlock(id), !moving.type.isLayout,
              !subtree(of: id).contains(targetId) else { return }
        recordUndo()

        if let column = findBlock(target.parentBlockId), column.type == .column {
            // Цель уже в колонке: добавляем новую колонку справа от неё.
            let newColumn = insertBlock(in: column.parentBlockId, after: column.id, type: .column)
            update(id) {
                $0.parentBlockId = newColumn.id
                $0.sortKey = SortKey.between(nil, nil)
            }
        } else {
            // Ряд колонок встаёт на место цели, цель уходит в левую колонку, блок в правую.
            let row = Block(pageId: pageId, parentBlockId: target.parentBlockId, type: .columnList, sortKey: target.sortKey)
            let keys = SortKey.sequence(count: 2)
            let left = Block(pageId: pageId, parentBlockId: row.id, type: .column, sortKey: keys[0])
            let right = Block(pageId: pageId, parentBlockId: row.id, type: .column, sortKey: keys[1])
            blocks += [row, left, right]
            dirtyBlocks.formUnion([row.id, left.id, right.id])
            update(targetId) { $0.parentBlockId = left.id }
            update(id) {
                $0.parentBlockId = right.id
                $0.sortKey = SortKey.between(nil, nil)
            }
        }
        reorder()
        normalizeColumns()
        focusRequest = id
    }

    /// Блок выше на том же уровне: рядом с ним встанет новая колонка из меню блока.
    func previousSibling(of id: UUID) -> Block? {
        guard let block = findBlock(id) else { return nil }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        let previous = siblings[index - 1]
        return previous.type.isLayout ? nil : previous
    }

    /// Пункт меню «Поставить в колонку рядом»: блок встаёт справа от блока выше.
    func placeBesidePrevious(_ id: UUID) {
        guard let previous = previousSibling(of: id) else { return }
        placeBeside(id, previous.id)
    }

    /// Доли ширины колонок ряда, в сумме 1. Колонка без сохранённой ширины получает среднюю долю.
    func columnFractions(_ rowId: UUID) -> [Double] {
        let columns = children(of: rowId)
        guard !columns.isEmpty else { return [] }
        let saved = columns.compactMap(\.content.columnWidth).filter { $0 > 0 }
        let fallback = saved.isEmpty ? 1 : saved.reduce(0, +) / Double(saved.count)
        let raw = columns.map { column -> Double in
            guard let width = column.content.columnWidth, width > 0 else { return fallback }
            return width
        }
        let total = raw.reduce(0, +)
        return raw.map { $0 / total }
    }

    /// Сохраняет ширины колонок после перетаскивания разделителя.
    func setColumnFractions(_ rowId: UUID, _ fractions: [Double]) {
        let columns = children(of: rowId)
        guard columns.count == fractions.count, fractions != columnFractions(rowId) else { return }
        recordUndo()
        for (column, fraction) in zip(columns, fractions) {
            update(column.id) { $0.content.columnWidth = fraction }
        }
    }

    /// Убирает пустые колонки, а ряд из одной колонки разворачивает обратно в обычные блоки.
    private func normalizeColumns() {
        var changed = true
        while changed {
            changed = false
            for column in blocks where column.type == .column && children(of: column.id).isEmpty {
                removeLayoutBlock(column.id)
                changed = true
                break
            }
            if changed { continue }
            for row in blocks where row.type == .columnList {
                let columns = children(of: row.id)
                guard columns.count <= 1 else { continue }
                let contents = columns.first.map { children(of: $0.id) } ?? []
                let siblings = children(of: row.parentBlockId)
                let index = siblings.firstIndex { $0.id == row.id }
                let lower = index.flatMap { $0 > 0 ? siblings[$0 - 1].sortKey : nil }
                let upper = index.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1].sortKey : nil }
                let keys = SortKey.sequence(count: contents.count, after: lower, before: upper)
                for (block, key) in zip(contents, keys) {
                    update(block.id) {
                        $0.parentBlockId = row.parentBlockId
                        $0.sortKey = key
                    }
                }
                for column in columns {
                    removeLayoutBlock(column.id)
                }
                removeLayoutBlock(row.id)
                reorder()
                changed = true
                break
            }
        }
    }

    /// Удаляет пустой служебный блок колонок. Детей у него к этому моменту уже нет.
    private func removeLayoutBlock(_ id: UUID) {
        blocks.removeAll { $0.id == id }
        enqueueDelete([id])
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
                print("Failed to create subpage: \(error)")
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
                print("Failed to create subpage: \(error)")
            }
        }
    }

    // MARK: Выписки из книг

    func source(_ id: UUID?) -> Source? {
        guard let id else { return nil }
        return links.sources.first { $0.id == id }
    }

    /// Книга, к которой это страница заметок.
    var notesSource: Source? { source(page?.sourceId) }

    func openExcerpt(_ reference: ExcerptReference) {
        guard reference.isPlace, let locator = reference.locator else {
            openSource(reference.sourceId, highlight: reference.highlightId)
            return
        }
        if openPlaceInReader?(reference) == true { return }
        // Другая книга откроется там, где остановились, поэтому место из ссылки сначала становится местом чтения.
        Task {
            await flush()
            try? await database.setReadingLocator(reference.sourceId, locator: locator)
            openSourceRequest = SourceRequest(sourceId: reference.sourceId, highlightId: nil)
        }
    }

    func openSource(_ sourceId: UUID, highlight: UUID? = nil) {
        Task {
            await flush()
            openSourceRequest = SourceRequest(sourceId: sourceId, highlightId: highlight)
        }
    }

    /// Ссылка на место в книге в конец страницы. Вставляется как выписка без текста.
    func appendPlaceLink(_ reference: ExcerptReference) {
        appendExcerpt(text: "", reference: reference)
    }

    /// Вставляет выписку в конец страницы, а после неё пустой абзац, чтобы сразу дописать мысль.
    /// Если страница пустая, выписка встаёт на место пустого абзаца.
    func appendExcerpt(text: String, reference: ExcerptReference) {
        recordUndo()
        let content = BlockContent(runs: [TextRun(text)], excerpt: reference)
        let topLevel = children(of: nil)
        if topLevel.count == 1, let only = topLevel.first, only.type == .paragraph, only.text.isEmpty {
            update(only.id) {
                $0.type = .excerpt
                $0.content = content
            }
            insertBlock(in: nil, after: only.id, type: .paragraph)
            return
        }
        // Пустой абзац в конце остаётся последним: выписка встаёт перед ним.
        if let last = topLevel.last, last.type == .paragraph, last.text.isEmpty, children(of: last.id).isEmpty {
            let previous = topLevel.dropLast().last
            insertBlock(in: nil, after: previous?.id, type: .excerpt, content: content)
        } else {
            let excerpt = insertBlock(in: nil, after: topLevel.last?.id, type: .excerpt, content: content)
            insertBlock(in: nil, after: excerpt.id, type: .paragraph)
        }
    }

    // MARK: Картинки

    /// Сохраняет картинку во вложения и показывает её в блоке.
    func setImage(_ id: UUID, data: Data, fileExtension: String?) {
        guard findBlock(id) != nil else { return }
        do {
            let name = try database.attachments.save(data, fileExtension: fileExtension)
            recordUndo()
            update(id) { $0.content.attachment = name }
        } catch {
            print("Failed to save image: \(error)")
        }
    }

    func setCover(_ cover: PageCover?) {
        page?.pageCover = cover
        Task { try? await database.setCover(pageId, cover: cover) }
    }

    func setCoverImage(data: Data) {
        do {
            setCover(.image(try database.attachments.save(data)))
        } catch {
            print("Failed to save cover: \(error)")
        }
    }

    func setBackground(_ background: PageBackground?) {
        page?.pageBackground = background
        Task { try? await database.setBackground(pageId, background: background) }
    }

    func setBackgroundImage(data: Data) {
        do {
            setBackground(.image(try database.attachments.save(data)))
        } catch {
            print("Failed to save background: \(error)")
        }
    }

    /// Номер пункта в нумерованном списке: считаются подряд идущие нумерованные соседи.
    func listNumber(for id: UUID) -> Int {
        guard let block = findBlock(id) else { return 1 }
        let siblings = children(of: block.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return 1 }
        var number = 1
        var current = index - 1
        while current >= 0, siblings[current].type == .numberedList {
            number += 1
            current -= 1
        }
        return number
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
