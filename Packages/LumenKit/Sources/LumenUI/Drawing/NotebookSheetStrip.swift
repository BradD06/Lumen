import CoreGraphics
import LumenCore
import LumenStorage
import LumenThemes
import PencilKit
import SwiftUI

/// Переход к листу тетради: новый номер каждый раз, чтобы можно было перейти к тому же листу снова.
struct NotebookJump: Equatable {
    var id = UUID()
    var sheet: Int
}

/// Миниатюры листов тетради, как в Goodnotes: нажатие открывает лист, перетаскивание
/// переставляет, в меню копия, шаблон, новый лист и удаление.
/// На Mac и iPad колонка слева от листов, на iPhone сетка в отдельном окне.
struct NotebookSheetStrip: View {
    let model: PageEditorModel
    let drawing: PKDrawing
    /// Лист, который сейчас на экране.
    let current: Int
    var columns: Int = 1
    let onOpen: (Int) -> Void

    @Environment(\.lumenTheme) private var theme

    private var block: Block? { model.notebookBlock }
    private var sheets: Int { model.notebookSheetCount }

    var body: some View {
        let content = block?.content ?? BlockContent()
        let bySheet = strokesBySheet()
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: max(columns, 1)),
                    spacing: 14
                ) {
                    ForEach(0..<sheets, id: \.self) { index in
                        SheetThumbnail(
                            index: index,
                            content: content,
                            strokes: bySheet[index] ?? [],
                            attachments: model.database.attachments,
                            isCurrent: index == current
                        )
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(index) }
                        .draggable(SheetDragToken.text(for: index)) {
                            SheetDragPreview(index: index)
                        }
                        .dropDestination(for: String.self) { tokens, _ in
                            guard let from = tokens.lazy.compactMap(SheetDragToken.sheet(from:)).first, from != index else {
                                return false
                            }
                            LumenSounds.play(.tap)
                            model.moveNotebookSheet(from: from, to: index)
                            onOpen(index)
                            return true
                        }
                        .contextMenu { menu(for: index) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Лист \(index + 1)")
                        .accessibilityAddTraits(index == current ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(12)
            }
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, sheet in
                withAnimation(LumenMotion.standard) { proxy.scrollTo(sheet, anchor: .center) }
            }
        }
    }

    /// Штрихи по листам: по середине штриха, как при удалении листа.
    private func strokesBySheet() -> [Int: [PKStroke]] {
        Dictionary(grouping: drawing.strokes) { stroke in
            NotebookEditing.sheet(ofMidY: stroke.renderBounds.midY, sheets: sheets)
        }
    }

    @ViewBuilder
    private func menu(for index: Int) -> some View {
        Button {
            onOpen(index)
        } label: {
            Label("Открыть лист", systemImage: "arrow.right.circle")
        }
        Button {
            LumenSounds.play(.create)
            if let copy = model.duplicateNotebookSheet(index) { onOpen(copy) }
        } label: {
            Label("Дублировать лист", systemImage: "plus.square.on.square")
        }
        Button {
            LumenSounds.play(.create)
            model.addNotebookSheet(after: index)
            onOpen(index + 1)
        } label: {
            Label("Новый лист после этого", systemImage: "plus.rectangle.on.rectangle")
        }
        if index > 0 {
            Button {
                model.moveNotebookSheet(from: index, to: index - 1)
                onOpen(index - 1)
            } label: {
                Label("Выше", systemImage: "arrow.up")
            }
        }
        if index < sheets - 1 {
            Button {
                model.moveNotebookSheet(from: index, to: index + 1)
                onOpen(index + 1)
            } label: {
                Label("Ниже", systemImage: "arrow.down")
            }
        }
        if sheets > 1 {
            Divider()
            Button(role: .destructive) {
                model.removeNotebookSheet(index)
            } label: {
                Label("Удалить лист", systemImage: "trash")
            }
        }
    }
}

/// Перетаскиваемый лист: обычная строка с меткой, чтобы чужой текст не переставлял листы.
enum SheetDragToken {
    private static let prefix = "lumen-notebook-sheet:"

    static func text(for sheet: Int) -> String { prefix + String(sheet) }

    static func sheet(from text: String) -> Int? {
        guard text.hasPrefix(prefix) else { return nil }
        return Int(text.dropFirst(prefix.count))
    }
}

private struct SheetDragPreview: View {
    let index: Int
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Text("Лист \(index + 1)")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.sheet, in: Capsule())
            .foregroundStyle(theme.textPrimary)
    }
}

/// Миниатюра одного листа: бумага, страница PDF, тексты и картинки, чернила и номер.
struct SheetThumbnail: View {
    let index: Int
    let content: BlockContent
    let strokes: [PKStroke]
    let attachments: AttachmentStore
    let isCurrent: Bool

    @Environment(\.lumenTheme) private var theme

    private var tone: PaperTone { content.paperTone ?? .white }

    var body: some View {
        let rect = NotebookLayout.sheetRect(index)
        let background = NotebookSheets.background(of: content, sheet: index)
        let count = NotebookLayout.sheetCount(of: content)
        let items = (content.items ?? []).filter {
            NotebookEditing.sheet(ofMidY: $0.frame.midY, sheets: count) == index
        }
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let scale = geometry.size.width / NotebookLayout.sheetWidth
                ZStack(alignment: .topLeading) {
                    PaperSheet(pattern: background == nil ? NotebookSheets.paper(of: content, sheet: index) : .blank, tone: tone)
                    if let background {
                        SheetPDFPage(background: background, attachments: attachments, dark: tone.isDark)
                    }
                    if !items.isEmpty {
                        NotebookItemsLayer(
                            items: items,
                            viewport: NotebookViewport(origin: rect.origin, scale: scale),
                            isDark: tone.isDark,
                            attachments: attachments
                        )
                    }
                    ThumbnailInk(strokes: strokes, rect: rect, isDark: tone.isDark)
                }
            }
            .aspectRatio(NotebookLayout.sheetWidth / NotebookLayout.sheetHeight, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isCurrent ? theme.accent : theme.line, lineWidth: isCurrent ? 2.5 : 1)
            }
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? theme.accent : theme.textSecondary)
        }
    }
}

/// Чернила листа маленькой картинкой. Перерисовывается, только когда поменялись штрихи этого листа.
private struct ThumbnailInk: View {
    let strokes: [PKStroke]
    let rect: CGRect
    let isDark: Bool

    @State private var cache = ThumbnailInkCache()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let scale = rect.width > 0 ? geometry.size.width / rect.width * displayScale : 1
            if let image = cache.image(strokes: strokes, rect: rect, scale: scale, isDark: isDark) {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

final class ThumbnailInkCache {
    private struct Key: Equatable {
        var count: Int
        var bounds: CGRect
        var points: Int
        var scale: CGFloat
        var isDark: Bool
    }

    private var key: Key?
    private var image: PlatformImage?

    @MainActor
    func image(strokes: [PKStroke], rect: CGRect, scale: CGFloat, isDark: Bool) -> PlatformImage? {
        let bounds = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let newKey = Key(
            count: strokes.count,
            bounds: bounds.isNull ? .zero : bounds.offsetBy(dx: -rect.minX, dy: -rect.minY),
            points: strokes.reduce(0) { $0 + $1.path.count },
            scale: (scale * 4).rounded() / 4,
            isDark: isDark
        )
        if newKey != key {
            key = newKey
            image = strokes.isEmpty ? nil : DrawingSupport.image(
                of: PKDrawing(strokes: strokes),
                in: rect,
                scale: max(newKey.scale, 0.25),
                isDark: isDark
            )
        }
        return image
    }
}
