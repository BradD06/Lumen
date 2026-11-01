import Foundation
import LumenCore
import PDFKit
import PencilKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Рисунки от руки: блок «Рисунок» в заметке и листы рукописной заметки.
extension PageEditorModel {
    // MARK: Рисунок в заметке

    /// Начать рисовать в блоке: курсор уходит из текста, чтобы на iPhone спряталась клавиатура.
    func startDrawing(_ id: UUID) {
        guard findBlock(id)?.type == .drawing else { return }
        focusRequest = nil
        activeDrawingId = id
    }

    func stopDrawing() {
        activeDrawingId = nil
    }

    /// Новые штрихи блока. `recordsUndo: false` продолжает прошлый шаг отмены,
    /// например когда ластик за одно движение стирает несколько штрихов.
    /// `visibleWidth`: сколько пунктов рисунка видно по ширине области. По нему запоминается
    /// ширина холста, чтобы в узкой панели рисунок уменьшался целиком, а не обрезался.
    func setDrawing(_ id: UUID, data: Data?, recordsUndo: Bool = true, visibleWidth: Double? = nil) {
        guard let block = findBlock(id), block.drawing != data else { return }
        if recordsUndo {
            recordUndo()
        }
        let inkWidth = DrawingSupport.inkWidth(of: data)
        let width = DrawingArea.updatedWidth(
            stored: block.content.drawingWidth,
            inkWidth: inkWidth,
            visibleWidth: visibleWidth ?? inkWidth ?? 0
        )
        update(id) {
            $0.drawing = data
            $0.content.drawingWidth = width
        }
    }

    func clearDrawing(_ id: UUID) {
        setDrawing(id, data: nil)
    }

    /// Высота области рисунка, в пределах `DrawingArea`.
    func setDrawingHeight(_ id: UUID, _ height: Double) {
        guard let block = findBlock(id), block.type == .drawing else { return }
        let clamped = DrawingArea.clampedHeight(height)
        guard clamped != DrawingArea.height(of: block.content) else { return }
        recordUndo()
        update(id) { $0.content.drawingHeight = clamped }
    }

    // MARK: Рукописная заметка

    var isNotebook: Bool { page?.isNotebook == true }

    /// Блок, в котором лежат все листы рукописной заметки.
    var notebookBlock: Block? {
        children(of: nil).first { $0.type == .drawing }
    }

    var notebookSheetCount: Int {
        notebookBlock.map { NotebookLayout.sheetCount(of: $0.content) } ?? 1
    }

    /// У рукописной заметки всегда есть блок с листами. Если его нет (заметку сделали
    /// на другом устройстве не до конца), им становится пустой абзац или новый блок.
    func ensureNotebookBlock() {
        guard isLoaded, isNotebook, notebookBlock == nil else { return }
        let content = BlockContent(sheetCount: 1, paper: .lined, paperTone: .white)
        if let empty = children(of: nil).first(where: { $0.type == .paragraph && $0.text.isEmpty }) {
            update(empty.id) {
                $0.type = .drawing
                $0.content = content
            }
        } else {
            insertBlock(in: nil, after: nil, type: .drawing, content: content)
        }
    }

    /// Чистый лист в конец тетради или после листа `index`.
    func addNotebookSheet(after index: Int? = nil) {
        insertNotebookSheets([nil], after: index)
    }

    /// Листы после листа `index` (или в конец): чистые (`nil`) или со страницами PDF.
    /// Всё, что ниже, опускается вместе со своими листами. Возвращает номер первого нового листа.
    @discardableResult
    func insertNotebookSheets(_ backgrounds: [SheetBackground?], after index: Int?) -> Int? {
        guard let block = notebookBlock, !backgrounds.isEmpty else { return nil }
        let count = NotebookLayout.sheetCount(of: block.content)
        let added = min(backgrounds.count, NotebookLayout.maxSheets - count)
        guard added > 0 else { return nil }
        let pages = Array(backgrounds.prefix(added))
        let after = index.flatMap { $0 < count - 1 ? max($0, -1) : nil }
        recordUndo()
        update(block.id) {
            $0.content.sheetCount = count + added
            $0.content.sheetBackgrounds = NotebookSheets.inserting(
                pages, after: after, into: $0.content.sheetBackgrounds, sheetCount: count
            )
            if let after {
                let drawing = NotebookEditing.insertingSheet(after: after, count: added, in: DrawingSupport.drawing(from: $0.drawing))
                $0.drawing = DrawingSupport.data(of: drawing)
                if let items = $0.content.items {
                    $0.content.items = NotebookEditing.insertingSheet(after: after, count: added, in: items)
                }
            }
        }
        return (after ?? count - 1) + 1
    }

    /// Убирает лист вместе с тем, что на нём написано. Последний лист не удаляется.
    func removeNotebookSheet(_ index: Int) {
        guard let block = notebookBlock else { return }
        let count = NotebookLayout.sheetCount(of: block.content)
        guard count > 1, (0..<count).contains(index) else { return }
        recordUndo()
        update(block.id) {
            $0.content.sheetCount = count - 1
            let drawing = NotebookEditing.removingSheet(index, from: DrawingSupport.drawing(from: $0.drawing))
            $0.drawing = DrawingSupport.data(of: drawing)
            if let items = $0.content.items {
                let rest = NotebookEditing.removingSheet(index, from: items)
                $0.content.items = rest.isEmpty ? nil : rest
            }
            $0.content.sheetBackgrounds = NotebookSheets.removing(index, from: $0.content.sheetBackgrounds)
        }
    }

    /// Страницы PDF листами тетради после листа `index` (или в конец). Выбранные страницы
    /// сохраняются во вложения отдельным PDF: тетрадь не зависит от исходного файла или книги.
    /// Пустая тетрадь (один чистый лист) просто заменяется страницами. Возвращает первый новый лист.
    @discardableResult
    func insertPDFSheets(from document: PDFDocument, pages: ClosedRange<Int>, after index: Int?) -> Int? {
        guard let block = notebookBlock else { return nil }
        let count = NotebookLayout.sheetCount(of: block.content)
        let isBlank = NotebookSheets.isBlank(block.content, hasInk: block.drawing != nil)
        let room = NotebookLayout.maxSheets - (isBlank ? 0 : count)
        let wanted = pages.clamped(to: 0...max(document.pageCount - 1, 0))
        guard document.pageCount > 0, room > 0 else { return nil }
        let chosen = Array(wanted.prefix(room))
        if chosen.count < wanted.count {
            NoticeCenter.shared.show("Вставлено \(chosen.count) страниц: в тетради не больше \(NotebookLayout.maxSheets) листов")
        }
        let copy = PDFDocument()
        for pageIndex in chosen {
            if let page = document.page(at: pageIndex)?.copy() as? PDFPage {
                copy.insert(page, at: copy.pageCount)
            }
        }
        guard copy.pageCount > 0, let data = copy.dataRepresentation() else {
            NoticeCenter.shared.report("Не удалось вставить PDF", CocoaError(.fileReadCorruptFile))
            return nil
        }
        let name: String
        do {
            name = try database.attachments.save(data, fileExtension: "pdf")
        } catch {
            NoticeCenter.shared.report("Не удалось вставить PDF", error)
            return nil
        }
        let backgrounds: [SheetBackground?] = (0..<copy.pageCount).map { SheetBackground(attachment: name, page: $0) }
        if isBlank {
            recordUndo()
            update(block.id) {
                $0.content.sheetCount = backgrounds.count
                $0.content.sheetBackgrounds = backgrounds
            }
            return 0
        }
        return insertNotebookSheets(backgrounds, after: index)
    }

    /// Рисунок и элементы тетради одной правкой: так правка лассо отменяется целиком.
    /// `nil` значит, что это не менялось.
    func setNotebookContent(drawing: PKDrawing?, items: [NotebookItem]?, recordsUndo: Bool) {
        guard let block = notebookBlock else { return }
        if recordsUndo { recordUndo() }
        update(block.id) {
            if let drawing { $0.drawing = DrawingSupport.data(of: drawing) }
            if let items { $0.content.items = items.isEmpty ? nil : items }
        }
    }

    func setPaper(_ pattern: PaperPattern) {
        guard let block = notebookBlock, block.content.paper != pattern else { return }
        recordUndo()
        update(block.id) { $0.content.paper = pattern }
    }

    func setPaperTone(_ tone: PaperTone) {
        guard let block = notebookBlock, block.content.paperTone != tone else { return }
        recordUndo()
        update(block.id) { $0.content.paperTone = tone }
    }
}

// MARK: - Тексты и картинки на листах

extension PageEditorModel {
    var notebookItems: [NotebookItem] {
        notebookBlock?.content.items ?? []
    }

    func notebookItem(_ id: UUID?) -> NotebookItem? {
        guard let id else { return nil }
        return notebookItems.first { $0.id == id }
    }

    /// Добавляет элемент на лист. Возвращает его, чтобы сразу выделить.
    @discardableResult
    func addNotebookItem(_ item: NotebookItem) -> NotebookItem? {
        guard let block = notebookBlock else { return nil }
        recordUndo()
        update(block.id) { $0.content.items = ($0.content.items ?? []) + [item] }
        return item
    }

    /// Меняет элемент. `recordsUndo: false` продолжает прошлый шаг: так перетаскивание
    /// или набор текста отменяются целиком, а не по кадру.
    func updateNotebookItem(_ id: UUID, recordsUndo: Bool = true, _ change: (inout NotebookItem) -> Void) {
        guard let block = notebookBlock, var items = block.content.items,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        change(&item)
        guard item != items[index] else { return }
        if recordsUndo { recordUndo() }
        items[index] = item
        update(block.id) { $0.content.items = items }
    }

    func removeNotebookItem(_ id: UUID) {
        guard let block = notebookBlock, let items = block.content.items, items.contains(where: { $0.id == id }) else { return }
        recordUndo()
        let rest = items.filter { $0.id != id }
        update(block.id) { $0.content.items = rest.isEmpty ? nil : rest }
    }

    /// Копия элемента чуть ниже и правее оригинала.
    @discardableResult
    func duplicateNotebookItem(_ id: UUID) -> NotebookItem? {
        guard var copy = notebookItem(id) else { return nil }
        copy.id = UUID()
        copy.frame = copy.frame.offsetBy(dx: 24, dy: 24)
        return addNotebookItem(copy)
    }

    /// Пустой текстовый блок, из которого ушли, убирается без следа в истории.
    func removeIfEmpty(_ id: UUID) {
        guard let block = notebookBlock, let item = notebookItem(id), item.isEmpty else { return }
        let rest = (block.content.items ?? []).filter { $0.id != id }
        update(block.id) { $0.content.items = rest.isEmpty ? nil : rest }
    }

    /// Новый текстовый блок с левым верхним углом в точке листа.
    @discardableResult
    func addTextBox(at point: CGPoint, color: HexColor? = nil) -> NotebookItem? {
        let sheet = NotebookLayout.sheetRect(NotebookLayout.sheetIndex(at: point.y, sheets: notebookSheetCount))
        let width = min(360, sheet.maxX - point.x - 16)
        let frame = CGRect(x: point.x, y: point.y, width: max(width, 120), height: NotebookItem.defaultFontSize * 1.6)
        return addNotebookItem(NotebookItem(kind: .text, frame: frame, color: color?.hex ?? "#141414"))
    }

    /// Картинка на лист: сохраняется во вложения и встаёт по центру листа, не шире 60% листа.
    @discardableResult
    func addNotebookImage(data: Data, fileExtension: String?, onSheet index: Int) -> NotebookItem? {
        guard let image = PlatformImage(data: data), image.size.width > 0, image.size.height > 0 else {
            NoticeCenter.shared.report("Не удалось вставить картинку", CocoaError(.fileReadCorruptFile))
            return nil
        }
        do {
            let name = try database.attachments.save(data, fileExtension: fileExtension)
            let sheet = NotebookLayout.sheetRect(min(max(index, 0), notebookSheetCount - 1))
            var width = min(image.size.width, sheet.width * 0.6)
            var height = width * image.size.height / image.size.width
            // Крошечную картинку увеличиваем, чтобы её можно было взять пальцем, без искажения.
            let shortest = min(width, height)
            if shortest < NotebookItem.minSize {
                width *= NotebookItem.minSize / shortest
                height *= NotebookItem.minSize / shortest
            }
            let frame = CGRect(x: sheet.midX - width / 2, y: sheet.minY + min(120, sheet.height / 4), width: width, height: height)
            return addNotebookItem(NotebookItem(kind: .image, frame: frame, attachment: name))
        } catch {
            NoticeCenter.shared.report("Не удалось вставить картинку", error)
            return nil
        }
    }
}
