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
    private(set) var blocks: [Block] = []
    private(set) var isLoaded = false
    /// Живые страницы (для выбора ссылки и подписей блоков-ссылок) и обратные ссылки.
    private(set) var links = PageLinksSnapshot.empty
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// Блок, на который нужно перевести фокус. Вью сбрасывает его после применения.
    var focusRequest: UUID?
    /// Страница, которую нужно открыть (ссылка или новая подстраница). Вью сбрасывает её после перехода.
    var openRequest: UUID?

    @ObservationIgnored private var dirtyBlocks: Set<UUID> = []
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

    func load() async {
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
        let newTitle = isTitleDirty ? title : nil
        isTitleDirty = false
        guard newTitle != nil || !pending.isEmpty else { return }

        let database = database
        let pageId = pageId
        let previous = lastWrite
        let write = Task {
            await previous?.value
            do {
                if let newTitle {
                    try await database.renamePage(pageId, title: newTitle)
                }
                for block in pending {
                    try await database.saveBlock(block)
                }
            } catch {
                print("Failed to save page \(pageId): \(error)")
            }
        }
        lastWrite = write
        await write.value
    }

    /// Удаление блока из базы в той же очереди, что и сохранения,
    /// чтобы запоздалая запись не вернула удалённый блок.
    private func enqueueDelete(_ id: UUID) {
        dirtyBlocks.remove(id)
        let database = database
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            try? await database.deleteBlock(id)
        }
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
        for id in removed {
            enqueueDelete(id)
        }
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

    // MARK: Блоки

    func focusFirstBlock() {
        focusRequest = blocks.first?.id
    }

    /// Нажатие на пустое место под блоками: фокус в последний пустой абзац или новый абзац в конце.
    func focusEnd() {
        if let last = blocks.last, last.type == .paragraph, last.text.isEmpty {
            focusRequest = last.id
        } else {
            focusRequest = insertBlock(after: blocks.indices.last, type: .paragraph).id
        }
    }

    func updateText(_ id: UUID, to newText: String) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        var block = blocks[index]

        if newText.contains("\n"), block.type != .code {
            recordUndo()
            split(at: index, text: newText)
            return
        }

        if block.type == .paragraph, let shortcut = MarkdownShortcut.match(newText) {
            recordUndo()
            block.type = shortcut.type
            block.text = shortcut.remainder
            blocks[index] = block
            markDirty(id)
            if shortcut.type == .divider {
                focusRequest = insertBlock(after: index, type: .paragraph).id
            }
            return
        }

        guard block.text != newText else { return }
        recordUndo(typing: .block(id))
        block.text = newText
        blocks[index] = block
        markDirty(id)
    }

    /// Return в конце блока (на macOS приходит как submit, а не как перевод строки).
    func submit(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        split(at: index, text: blocks[index].text + "\n")
    }

    /// Делит блок по переводам строки: первая строка остаётся, остальные становятся новыми блоками.
    /// Return в пустом пункте списка выходит из списка, как в Notion.
    private func split(at index: Int, text: String) {
        var block = blocks[index]
        let lines = text.components(separatedBy: "\n")

        if block.type.continuation != .paragraph, lines.allSatisfy(\.isEmpty) {
            block.type = .paragraph
            block.text = ""
            blocks[index] = block
            markDirty(block.id)
            return
        }

        block.text = lines[0]
        blocks[index] = block
        markDirty(block.id)

        var lastIndex = index
        var lastId = block.id
        for line in lines.dropFirst() {
            lastId = insertBlock(after: lastIndex, type: block.type.continuation, content: BlockContent(text: line)).id
            lastIndex += 1
        }
        focusRequest = lastId
    }

    @discardableResult
    private func insertBlock(after index: Int?, type: BlockType, content: BlockContent = BlockContent()) -> Block {
        let position = index.map { $0 + 1 } ?? 0
        let lower = position > 0 ? blocks[position - 1].sortKey : nil
        let upper = position < blocks.count ? blocks[position].sortKey : nil
        let block = Block(
            pageId: pageId,
            type: type,
            content: content,
            sortKey: SortKey.between(lower, upper)
        )
        blocks.insert(block, at: position)
        markDirty(block.id)
        return block
    }

    /// Меняет тип блока (из slash-меню или контекстного меню).
    /// «Страница» создаёт новую подстраницу и сразу открывает её, как в Notion.
    func setType(_ id: UUID, _ type: BlockType) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        if type == .page {
            createSubpage(from: id, title: "", open: true)
            return
        }
        recordUndo()
        var block = blocks[index]
        block.type = type
        if !type.hasText || block.text.hasPrefix("/") {
            block.text = ""
        }
        blocks[index] = block
        markDirty(id)
        if type.hasText {
            focusRequest = id
        } else {
            focusRequest = insertBlock(after: index, type: .paragraph).id
        }
    }

    func toggleChecked(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        blocks[index].content.isChecked.toggle()
        markDirty(id)
    }

    /// Backspace в пустом блоке: особый блок сначала становится абзацем, пустой абзац удаляется.
    /// Возвращает `true`, если нажатие обработано.
    func backspaceInEmptyBlock(_ id: UUID) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].text.isEmpty else { return false }
        if blocks[index].type != .paragraph {
            recordUndo()
            blocks[index].type = .paragraph
            markDirty(id)
            return true
        }
        guard index > 0 else { return false }
        deleteBlock(id)
        return true
    }

    func deleteBlock(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        blocks.remove(at: index)
        if blocks.isEmpty {
            insertBlock(after: nil, type: .paragraph)
        }
        focusRequest = blocks[max(index - 1, 0)].id
        enqueueDelete(id)
    }

    // MARK: Перемещение

    /// Ставит блок на место другого: при перетаскивании вниз он встаёт после цели, вверх перед ней.
    func moveBlock(_ id: UUID, onto targetId: UUID) {
        guard id != targetId,
              let from = blocks.firstIndex(where: { $0.id == id }),
              let to = blocks.firstIndex(where: { $0.id == targetId }) else { return }
        recordUndo()
        var block = blocks.remove(at: from)
        let lower = to > 0 ? blocks[to - 1].sortKey : nil
        let upper = to < blocks.count ? blocks[to].sortKey : nil
        block.sortKey = SortKey.between(lower, upper)
        blocks.insert(block, at: to)
        markDirty(id)
    }

    /// Сдвигает блок на одну позицию вверх (`-1`) или вниз (`+1`).
    func moveBlock(_ id: UUID, by offset: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard blocks.indices.contains(target) else { return }
        moveBlock(id, onto: blocks[target].id)
        focusRequest = id
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

    /// Заменяет набранный `[[запрос` или `@запрос` ссылкой на страницу. Если до триггера
    /// был текст, он остаётся в блоке, а ссылка встаёт следующим блоком.
    func linkPage(from id: UUID, to targetId: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        let prefix = MentionTrigger.match(blocks[index].text)?.prefix ?? ""
        let remaining = prefix.trimmingCharacters(in: .whitespaces)
        let linkIndex: Int
        if remaining.isEmpty {
            blocks[index].type = .page
            blocks[index].content = BlockContent(pageId: targetId)
            markDirty(id)
            linkIndex = index
        } else {
            blocks[index].text = remaining
            markDirty(id)
            insertBlock(after: index, type: .page, content: BlockContent(pageId: targetId))
            linkIndex = index + 1
        }
        focusRequest = insertBlock(after: linkIndex, type: .paragraph).id
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

    // MARK: Картинки

    /// Сохраняет картинку во вложения и показывает её в блоке.
    func setImage(_ id: UUID, data: Data, fileExtension: String?) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        do {
            let name = try database.attachments.save(data, fileExtension: fileExtension)
            recordUndo()
            blocks[index].content.attachment = name
            markDirty(id)
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

    /// Номер пункта в нумерованном списке: считаются подряд идущие нумерованные блоки.
    func listNumber(at index: Int) -> Int {
        var number = 1
        var current = index - 1
        while current >= 0, blocks[current].type == .numberedList {
            number += 1
            current -= 1
        }
        return number
    }
}
