import Foundation
import LumenCore

/// Выделение в тексте блока, в символах текста без разметки.
struct TextSelectionInfo: Equatable {
    var blockId: UUID
    var range: Range<Int>
}

/// Кнопки панели форматирования, сочетаний клавиш и меню по правой кнопке.
enum FormatAction: String, CaseIterable, Identifiable {
    case bold, italic, underline, strikethrough, code, clear

    var id: String { rawValue }

    var mark: TextMark? {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .underline: .underline
        case .strikethrough: .strikethrough
        case .code: .code
        case .clear: nil
        }
    }

    var title: String {
        switch self {
        case .bold: "Жирный"
        case .italic: "Курсив"
        case .underline: "Подчёркнутый"
        case .strikethrough: "Зачёркнутый"
        case .code: "Код"
        case .clear: "Убрать оформление"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .clear: "eraser"
        }
    }

    /// Подсказка с сочетанием клавиш.
    var shortcut: String? {
        switch self {
        case .bold: "⌘B"
        case .italic: "⌘I"
        case .underline: "⌘U"
        case .strikethrough: "⇧⌘X"
        case .code: "⌘E"
        case .clear: nil
        }
    }
}

/// Оформление выделенного текста: жирный, курсив, ссылка. Всё отменяется ⌘Z.
extension PageEditorModel {
    /// Весь текст блока: меню по правой кнопке без выделения оформляет блок целиком.
    func wholeText(of id: UUID) -> TextSelectionInfo? {
        guard let block = findBlock(id), block.type.hasText, block.type != .code else { return nil }
        return TextSelectionInfo(blockId: id, range: 0..<block.text.count)
    }

    /// Что из оформления есть на всём выделении: эти кнопки на панели подсвечены.
    func marks(in selection: TextSelectionInfo) -> Set<TextMark> {
        guard let runs = findBlock(selection.blockId)?.content.runs else { return [] }
        return Set(TextMark.allCases.filter { InlineMarkup.hasMark($0, in: runs, range: selection.range) })
    }

    func link(in selection: TextSelectionInfo) -> String? {
        guard let runs = findBlock(selection.blockId)?.content.runs else { return nil }
        return InlineMarkup.link(in: runs, range: selection.range)
    }

    func apply(_ action: FormatAction, to selection: TextSelectionInfo) {
        guard let runs = findBlock(selection.blockId)?.content.runs else { return }
        let changed: [TextRun]
        if let mark = action.mark {
            changed = InlineMarkup.toggling(mark, in: runs, range: selection.range)
        } else {
            changed = InlineMarkup.clearingFormatting(in: runs, range: selection.range)
        }
        commitFormatting(changed, selection: selection)
    }

    /// Ссылка на выделенный текст. Пустой адрес убирает ссылку.
    func setLink(_ url: String?, in selection: TextSelectionInfo) {
        guard let runs = findBlock(selection.blockId)?.content.runs else { return }
        let link = url.map(Self.normalizedLink)
        commitFormatting(InlineMarkup.settingLink(link, in: runs, range: selection.range), selection: selection)
    }

    private func commitFormatting(_ runs: [TextRun], selection: TextSelectionInfo) {
        guard let block = findBlock(selection.blockId), InlineMarkup.normalized(block.content.runs) != runs else { return }
        LumenSounds.play(.tap)
        setRuns(selection.blockId, runs)
        selectionRestore = selection
    }

    /// «example.com» становится «https://example.com», ссылки lumen:// и почта остаются как есть.
    static func normalizedLink(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://"), !trimmed.hasPrefix("mailto:") else { return trimmed }
        if trimmed.contains("@"), !trimmed.contains("/") { return "mailto:" + trimmed }
        return "https://" + trimmed
    }
}
