import LumenCore
import LumenThemes
import PencilKit
import SwiftUI

/// Рукописная заметка, как в Goodnotes: листы бумаги друг под другом, на которых пишут от руки.
/// Название и кнопки сверху, ниже листы. На iPhone и iPad холст PencilKit (палец или Apple Pencil,
/// щипок увеличивает), на Mac рисуют мышью или трекпадом.
struct NotebookView: View {
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding
    var isCompact: Bool

    /// Лист посередине экрана: его удаляют и после него добавляют новый.
    @State private var visibleSheet = 0
    @State private var parsed = ParsedDrawing()
    #if os(iOS)
    /// Пишет ли палец. Выключите, чтобы листать тетрадь одним пальцем.
    @State private var isDrawing = true
    #else
    /// Увеличение листов относительно ширины окна.
    @State private var zoom: CGFloat = 1
    #endif
    @Environment(\.lumenTheme) private var theme

    private var block: Block? { model.notebookBlock }
    private var sheets: Int { model.notebookSheetCount }
    private var pattern: PaperPattern { block?.content.paper ?? .lined }
    private var tone: PaperTone { block?.content.paperTone ?? .white }

    var body: some View {
        VStack(spacing: 0) {
            header
            canvas
        }
        .task(id: model.isLoaded) {
            model.ensureNotebookBlock()
        }
    }

    // MARK: Шапка

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if let icon = model.page?.icon, !icon.isEmpty {
                    Text(icon).font(.system(size: 26))
                }
                TextField(
                    "Без названия",
                    text: Binding(get: { model.title }, set: { model.setTitle($0) })
                )
                .textFieldStyle(.plain)
                .font(.system(size: isCompact ? 22 : 28, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .focused(focus, equals: .title)
                .onSubmit { focus.wrappedValue = nil }

                Spacer(minLength: 0)

                Text("Лист \(min(visibleSheet, sheets - 1) + 1) из \(sheets)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()

                controls
            }
            #if os(macOS)
            HStack {
                MouseInkBar()
                Spacer(minLength: 0)
                zoomControls
            }
            #endif
        }
        .padding(.horizontal, isCompact ? 14 : 24)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var controls: some View {
        #if os(iOS)
        if isCompact {
            Button {
                model.undo()
            } label: {
                Label("Отменить", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .labelStyle(.iconOnly)
        }
        Button {
            isDrawing.toggle()
        } label: {
            Label(isDrawing ? "Листать" : "Писать", systemImage: isDrawing ? "hand.draw" : "pencil.tip")
        }
        .labelStyle(.iconOnly)
        .help(isDrawing ? "Листать тетрадь пальцем" : "Писать пальцем")
        #endif

        Menu {
            Button {
                LumenSounds.play(.create)
                model.addNotebookSheet()
            } label: {
                Label("Добавить лист в конец", systemImage: "doc.badge.plus")
            }
            if visibleSheet < sheets - 1 {
                Button {
                    LumenSounds.play(.create)
                    model.addNotebookSheet(after: visibleSheet)
                } label: {
                    Label("Добавить лист после \(visibleSheet + 1)-го", systemImage: "plus.rectangle.on.rectangle")
                }
            }
            if sheets > 1 {
                Button(role: .destructive) {
                    model.removeNotebookSheet(min(visibleSheet, sheets - 1))
                } label: {
                    Label("Удалить лист \(min(visibleSheet, sheets - 1) + 1)", systemImage: "trash")
                }
            }
            Divider()
            Picker("Линовка", selection: Binding(get: { pattern }, set: { model.setPaper($0) })) {
                ForEach(PaperPattern.allCases) { pattern in
                    Label(pattern.title, systemImage: pattern.symbolName).tag(pattern)
                }
            }
            Picker("Бумага", selection: Binding(get: { tone }, set: { model.setPaperTone($0) })) {
                ForEach(PaperTone.allCases) { tone in
                    Text(tone.title).tag(tone)
                }
            }
        } label: {
            Label("Листы", systemImage: "doc.on.doc")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .fixedSize()
        .help("Листы и бумага")

        Button {
            LumenSounds.play(.create)
            model.addNotebookSheet()
        } label: {
            Label("Лист", systemImage: "plus")
        }
        .help("Добавить лист в конец")
    }

    // MARK: Листы

    @ViewBuilder
    private var canvas: some View {
        if let block {
            #if os(iOS)
            PencilCanvas(
                data: block.drawing,
                isDrawingEnabled: isDrawing,
                showsToolPicker: isDrawing,
                isDark: tone.isDark,
                notebook: PencilCanvas.Notebook(sheets: sheets, pattern: pattern, tone: tone),
                onChange: { model.setDrawing(block.id, data: $0) },
                onVisibleSheet: { visibleSheet = $0 }
            )
            .ignoresSafeArea(.container, edges: .bottom)
            #else
            macSheets(block)
            #endif
        } else {
            Spacer()
        }
    }

    #if os(macOS)
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                zoom = max(0.5, zoom - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoom <= 0.5)
            .keyboardShortcut("-", modifiers: .command)
            Button {
                zoom = 1
            } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .keyboardShortcut("0", modifiers: .command)
            Button {
                zoom = min(3, zoom + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoom >= 3)
            .keyboardShortcut("=", modifiers: .command)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textSecondary)
        .help("Масштаб листов")
    }

    private func macSheets(_ block: Block) -> some View {
        GeometryReader { geometry in
            let fitWidth = max(min(geometry.size.width - 48, 860), 200)
            let width = fitWidth * zoom
            let scale = width / NotebookLayout.sheetWidth
            let drawing = parsed.drawing(for: block.drawing)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(spacing: NotebookLayout.sheetGap * scale) {
                    ForEach(0..<sheets, id: \.self) { index in
                        macSheet(index, block: block, drawing: drawing, scale: scale)
                            .frame(width: width, height: NotebookLayout.sheetHeight * scale)
                    }
                    Button {
                        LumenSounds.play(.create)
                        model.addNotebookSheet()
                    } label: {
                        Label("Добавить лист", systemImage: "plus")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .frame(minWidth: geometry.size.width)
            }
            .onScrollGeometryChange(for: Int.self) { [sheets] scroll in
                let middle = (scroll.contentOffset.y + scroll.containerSize.height / 2 - 8) / scale
                return NotebookLayout.sheetIndex(at: middle, sheets: sheets)
            } action: { _, index in
                visibleSheet = index
            }
        }
    }

    private func macSheet(_ index: Int, block: Block, drawing: PKDrawing, scale: CGFloat) -> some View {
        let rect = NotebookLayout.sheetRect(index)
        return ZStack {
            PaperSheet(pattern: pattern, tone: tone)
            DrawingImageView(data: block.drawing, drawing: drawing, rect: rect, isDark: tone.isDark)
            MouseDrawingLayer(
                drawing: drawing,
                origin: rect.origin,
                scale: scale,
                isDark: tone.isDark,
                onChange: { drawing, isNewStep in
                    model.setDrawing(block.id, data: DrawingSupport.data(of: drawing), recordsUndo: isNewStep)
                }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .contextMenu {
            Button {
                model.addNotebookSheet(after: index)
            } label: {
                Label("Добавить лист после этого", systemImage: "plus.rectangle.on.rectangle")
            }
            if sheets > 1 {
                Button(role: .destructive) {
                    model.removeNotebookSheet(index)
                } label: {
                    Label("Удалить лист", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel("Лист \(index + 1)")
    }
    #endif
}

/// Разобранный рисунок тетради: один на все листы, разбирается заново, только когда поменялись штрихи.
final class ParsedDrawing {
    private var data: Data?
    private var drawing = PKDrawing()
    private var isParsed = false

    func drawing(for data: Data?) -> PKDrawing {
        if !isParsed || data != self.data {
            self.data = data
            drawing = DrawingSupport.drawing(from: data)
            isParsed = true
        }
        return drawing
    }
}
