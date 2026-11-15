import Foundation
import LumenCore
import LumenStorage

/// Шаблоны страниц: начать пустую страницу с шаблона и сохранить страницу как шаблон.
extension PageEditorModel {
    /// На странице ничего нет: один пустой абзац (или ничего). Тогда предлагаются шаблоны.
    var isBlankPage: Bool {
        guard isLoaded, page?.isNotebook != true else { return false }
        return blocks.allSatisfy { $0.type == .paragraph && $0.text.isEmpty && ($0.content.comments ?? []).isEmpty }
            && blocks.count <= 1
    }

    /// Блоки шаблона на страницу: пустая страница заполняется им, иначе он встаёт в конец.
    /// Значок шаблона достаётся странице, если своего у неё нет. Одним шагом отмены.
    func applyTemplate(_ template: PageTemplate) {
        let clipboard = template.blocks
        guard !clipboard.blocks.isEmpty else { return }
        recordUndo()
        let inserted: [UUID]
        if isBlankPage {
            let old = Set(blocks.map(\.id))
            let keys = SortKey.sequence(count: clipboard.rootIds.count)
            let copies = clipboard.copies(pageId: pageId, parentId: nil, rootKeys: keys)
            removeBlocks(old)
            appendBlocks(copies.blocks)
            reorder()
            scheduleSave()
            inserted = copies.blocks.map(\.id)
        } else if let last = children(of: nil).last(where: { $0.type != .sheetBreak }) ?? children(of: nil).last {
            let roots = insertClipboard(clipboard, after: last.id)
            inserted = roots.flatMap { subtree(of: $0) }
        } else {
            return
        }
        if page?.icon?.isEmpty ?? true, let icon = template.icon {
            setIcon(icon)
        }
        // Курсор в первый текст шаблона после заголовков, чтобы сразу писать.
        let ids = Set(inserted)
        focusRequest = blocks.first { ids.contains($0.id) && $0.type.hasText && !$0.type.isHeading }?.id
            ?? blocks.first { ids.contains($0.id) && $0.type.hasText }?.id
    }

    /// Страница как свой шаблон: все блоки, кроме границ листов.
    func saveAsTemplate() async {
        await flush()
        let roots = children(of: nil).map(\.id)
        let clipboard = BlockClipboard.make(roots: roots, from: blocks)
        guard !clipboard.blocks.isEmpty else { return }
        let title = title.trimmingCharacters(in: .whitespaces)
        do {
            try await database.savePageTemplate(title: title, icon: page?.icon, blocks: clipboard)
            NoticeCenter.shared.show("Шаблон «\(title.isEmpty ? "Без названия" : title)» сохранён")
        } catch {
            NoticeCenter.shared.report("Не удалось сохранить шаблон", error)
        }
    }
}

extension BlockType {
    var isHeading: Bool { self == .heading1 || self == .heading2 || self == .heading3 }
}
