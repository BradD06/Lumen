import LumenCore
import LumenThemes
import PencilKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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
    /// Перо, выделение или текст. В выделении палец листает тетрадь.
    @State private var tool: NotebookTool = .draw
    /// Выделенный текст или картинка.
    @State private var selection: UUID?
    /// Текст, который сейчас набирают.
    @State private var editingId: UUID?
    @State private var isPickingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isImportingImage = false
    #if os(iOS)
    /// Где холст на экране: по нему слой правки ставит рамки поверх элементов.
    @State private var viewport = NotebookViewport()
    #else
    /// Увеличение листов относительно ширины окна.
    @State private var zoom: CGFloat = 1
    /// Элемент, который сейчас тащат, и лист, на котором его взяли. Пока его тащат, рамкой
    /// правки владеет этот лист, даже если середина элемента ушла на соседний: иначе рамка
    /// переехала бы в другой лист посреди движения и жест оборвался бы.
    @State private var dragged: (id: UUID, sheet: Int)?
    /// Перехват ⌘V: картинка из буфера обмена встаёт на лист.
    @State private var pasteKey: NotebookPasteKey?
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
        .onChange(of: tool) { _, newTool in
            editingId = nil
            if newTool == .draw { selection = nil }
        }
        .onChange(of: editingId) { old, _ in
            // Пустой текстовый блок, из которого ушли, не остаётся на листе.
            if let old {
                model.removeIfEmpty(old)
                if model.notebookItem(old) == nil, selection == old { selection = nil }
            }
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    insertImage(data, fileExtension: item.supportedContentTypes.first?.preferredFilenameExtension)
                }
                pickedPhoto = nil
            }
        }
        #if os(macOS)
        .onAppear {
            let key = pasteKey ?? NotebookPasteKey()
            pasteKey = key
            key.start { pasteImage() }
        }
        .onDisappear { pasteKey?.stop() }
        #endif
        .fileImporter(isPresented: $isImportingImage, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                insertImage(data, fileExtension: url.pathExtension)
            }
        }
    }

    private var items: [NotebookItem] { model.notebookItems }

    private func insertImage(_ data: Data, fileExtension: String?) {
        guard let item = model.addNotebookImage(data: data, fileExtension: fileExtension, onSheet: visibleSheet) else { return }
        LumenSounds.play(.create)
        tool = .select
        selection = item.id
    }

    /// Картинка или скриншот из буфера обмена. Возвращает `false`, если картинки там нет.
    @discardableResult
    private func pasteImage() -> Bool {
        guard let image = NotebookPasteboard.image() else {
            NoticeCenter.shared.show("В буфере обмена нет картинки")
            return false
        }
        insertImage(image.data, fileExtension: image.fileExtension)
        return true
    }

    /// Нажатие на пустое место листа в координатах холста.
    private func tapEmpty(at point: CGPoint) {
        if editingId != nil {
            editingId = nil
            return
        }
        switch tool {
        case .text:
            let color: HexColor? = {
                #if os(macOS)
                MouseInk.shared.color
                #else
                nil
                #endif
            }()
            if let item = model.addTextBox(at: point, color: color) {
                selection = item.id
                editingId = item.id
            }
        case .select:
            selection = nil
        case .draw:
            break
        }
    }

    /// Перо, выделение, текст и вставка картинки.
    private var toolRow: some View {
        HStack(spacing: 10) {
            Picker("Инструмент", selection: $tool) {
                ForEach(NotebookTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbolName).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .fixedSize()
            .help("Перо, выделение или текст")

            Menu {
                Button {
                    isPickingPhoto = true
                } label: {
                    Label("Из фото", systemImage: "photo.on.rectangle")
                }
                Button {
                    isImportingImage = true
                } label: {
                    Label("Из файла", systemImage: "folder")
                }
                Button {
                    pasteImage()
                } label: {
                    Label("Из буфера обмена", systemImage: "doc.on.clipboard")
                }
            } label: {
                Label("Картинка", systemImage: "photo.badge.plus")
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Вставить картинку на лист")

            #if os(macOS)
            if tool == .draw {
                MouseInkBar()
            }
            Spacer(minLength: 0)
            zoomControls
            #else
            Spacer(minLength: 0)
            #endif
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
            toolRow
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
            ZStack(alignment: .topLeading) {
                PencilCanvas(
                    data: block.drawing,
                    isDrawingEnabled: tool == .draw,
                    showsToolPicker: tool == .draw,
                    isDark: tone.isDark,
                    notebook: PencilCanvas.Notebook(sheets: sheets, pattern: pattern, tone: tone),
                    onChange: { model.setDrawing(block.id, data: $0) },
                    onVisibleSheet: { visibleSheet = $0 },
                    items: PencilCanvas.NotebookItemsContent(
                        items: items,
                        hiddenId: editingId,
                        attachments: model.database.attachments
                    ),
                    onTap: tool == .draw ? nil : { tapEmpty(at: $0) },
                    onViewport: tool == .draw ? nil : { viewport = $0 }
                )
                if tool != .draw {
                    NotebookItemsEditor(
                        model: model,
                        items: items,
                        viewport: viewport,
                        isDark: tone.isDark,
                        tool: tool,
                        selection: $selection,
                        editingId: $editingId
                    )
                }
            }
            .clipped()
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
        let viewport = NotebookViewport(origin: rect.origin, scale: scale)
        let visible = items.filter { $0.frame.intersects(rect) }
        // Правят элемент на том листе, где его середина: так рамка не появляется дважды.
        let owned = items.filter { item in
            if let dragged, dragged.id == item.id { return dragged.sheet == index }
            return NotebookLayout.sheetIndex(at: item.frame.midY, sheets: sheets) == index
        }
        return ZStack(alignment: .topLeading) {
            PaperSheet(pattern: pattern, tone: tone)
            NotebookItemsLayer(
                items: visible,
                viewport: viewport,
                isDark: tone.isDark,
                attachments: model.database.attachments,
                hiddenId: editingId
            )
            DrawingImageView(data: block.drawing, drawing: drawing, rect: rect, isDark: tone.isDark)
            if tool == .draw {
                MouseDrawingLayer(
                    drawing: drawing,
                    origin: rect.origin,
                    scale: scale,
                    isDark: tone.isDark,
                    onChange: { drawing, isNewStep in
                        model.setDrawing(block.id, data: DrawingSupport.data(of: drawing), recordsUndo: isNewStep)
                    }
                )
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        tapEmpty(at: viewport.toCanvas(location))
                    }
                    .pointerStyle(tool == .text ? PointerStyle.horizontalText : PointerStyle.default)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .overlay(alignment: .topLeading) {
            if tool != .draw {
                NotebookItemsEditor(
                    model: model,
                    items: owned,
                    viewport: viewport,
                    isDark: tone.isDark,
                    tool: tool,
                    selection: $selection,
                    editingId: $editingId,
                    onDrag: { id in dragged = id.map { ($0, index) } }
                )
            }
        }
        .dropDestination(for: URL.self) { urls, location in
            dropImages(urls, at: viewport.toCanvas(location))
        }
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
        .zIndex(owned.contains { $0.id == selection } ? 1 : 0)
        .accessibilityLabel("Лист \(index + 1)")
    }

    /// Картинки, брошенные на лист из Finder, встают туда, куда их бросили.
    private func dropImages(_ urls: [URL], at point: CGPoint) -> Bool {
        var inserted = false
        for url in urls {
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                  let data = try? Data(contentsOf: url),
                  let item = model.addNotebookImage(data: data, fileExtension: url.pathExtension, onSheet: visibleSheet)
            else { continue }
            let frame = CGRect(x: point.x - item.width / 2, y: point.y - item.height / 2, width: item.width, height: item.height)
            model.updateNotebookItem(item.id, recordsUndo: false) { $0.frame = frame }
            selection = item.id
            inserted = true
        }
        if inserted {
            LumenSounds.play(.create)
            tool = .select
        }
        return inserted
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

#if os(macOS)
/// ⌘V вставляет картинку из буфера обмена прямо на лист. Если курсор стоит в тексте
/// (название, текстовый блок), ⌘V вставляет текст как обычно.
@MainActor
final class NotebookPasteKey {
    private var monitor: Any?
    private var paste: () -> Bool = { false }

    func start(_ paste: @escaping () -> Bool) {
        self.paste = paste
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if NSApp.keyWindow?.firstResponder is NSText { return false }
                guard NotebookPasteboard.hasImage else { return false }
                return self.paste()
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        paste = { false }
    }
}
#endif
