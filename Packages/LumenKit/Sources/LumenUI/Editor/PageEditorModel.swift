import Foundation
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
    /// Блок, на который нужно перевести фокус. Вью сбрасывает его после применения.
    var focusRequest: UUID?

    @ObservationIgnored private var dirtyBlocks: Set<UUID> = []
    @ObservationIgnored private var isTitleDirty = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    private static let saveDelay: Duration = .milliseconds(350)

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

    /// Немедленно записывает все несохранённые правки.
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        await save()
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

    // MARK: Страница

    func setTitle(_ value: String) {
        // Return в названии переводит курсор в первый блок.
        if value.contains("\n") {
            title = value.replacingOccurrences(of: "\n", with: "")
            focusFirstBlock()
        } else {
            title = value
        }
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
            split(at: index, text: newText)
            return
        }

        if block.type == .paragraph, let shortcut = MarkdownShortcut.match(newText) {
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
        block.text = newText
        blocks[index] = block
        markDirty(id)
    }

    /// Return в конце блока (на macOS приходит как submit, а не как перевод строки).
    func submit(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
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
            lastId = insertBlock(after: lastIndex, type: block.type.continuation, text: line).id
            lastIndex += 1
        }
        focusRequest = lastId
    }

    @discardableResult
    private func insertBlock(after index: Int?, type: BlockType, text: String = "") -> Block {
        let position = index.map { $0 + 1 } ?? 0
        let lower = position > 0 ? blocks[position - 1].sortKey : nil
        let upper = position < blocks.count ? blocks[position].sortKey : nil
        let block = Block(
            pageId: pageId,
            type: type,
            content: BlockContent(text: text),
            sortKey: SortKey.between(lower, upper)
        )
        blocks.insert(block, at: position)
        markDirty(block.id)
        return block
    }

    /// Меняет тип блока (из slash-меню или контекстного меню).
    func setType(_ id: UUID, _ type: BlockType) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
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
        blocks[index].content.isChecked.toggle()
        markDirty(id)
    }

    /// Backspace в пустом блоке: особый блок сначала становится абзацем, пустой абзац удаляется.
    /// Возвращает `true`, если нажатие обработано.
    func backspaceInEmptyBlock(_ id: UUID) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == id }), blocks[index].text.isEmpty else { return false }
        if blocks[index].type != .paragraph {
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
        blocks.remove(at: index)
        dirtyBlocks.remove(id)
        if blocks.isEmpty {
            insertBlock(after: nil, type: .paragraph)
        }
        focusRequest = blocks[max(index - 1, 0)].id
        // В ту же очередь, что и сохранения, чтобы запоздалая запись не вернула удалённый блок.
        let database = database
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            try? await database.deleteBlock(id)
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
