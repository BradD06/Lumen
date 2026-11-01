import Foundation
import LumenCore
import PencilKit

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
    func setDrawing(_ id: UUID, data: Data?, recordsUndo: Bool = true) {
        guard let block = findBlock(id), block.drawing != data else { return }
        if recordsUndo {
            recordUndo()
        }
        update(id) { $0.drawing = data }
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
        guard let block = notebookBlock else { return }
        let count = NotebookLayout.sheetCount(of: block.content)
        guard count < NotebookLayout.maxSheets else { return }
        recordUndo()
        update(block.id) {
            $0.content.sheetCount = count + 1
            if let index, index < count - 1 {
                let drawing = NotebookEditing.insertingSheet(after: index, in: DrawingSupport.drawing(from: $0.drawing))
                $0.drawing = DrawingSupport.data(of: drawing)
            }
        }
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
