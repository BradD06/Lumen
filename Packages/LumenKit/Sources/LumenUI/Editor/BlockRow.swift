import LumenCore
import LumenStorage
import LumenThemes
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Один блок страницы: ручка для перетаскивания, маркер (точка, номер, чекбокс) и содержимое.
struct BlockRow: View {
    let block: Block
    let number: Int
    let depth: Int
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding

    /// Сколько места слева от текста занимает ручка вместе с промежутком.
    static let handleWidth: CGFloat = 18
    static let handleSpacing: CGFloat = 4
    static var handleInset: CGFloat { handleWidth + handleSpacing }

    @State private var isHovered = false
    @State private var size: CGSize = .zero
    @State private var isColorPickerShown = false
    /// Разметка, которую человек сейчас набирает. Держится, пока блок в фокусе, чтобы курсор
    /// не прыгал, если та же разметка собирается из фрагментов чуть иначе.
    @State private var editingSource: String?
    @Environment(\.lumenTheme) private var theme
    @Environment(\.workspaceActions) private var workspaceActions
    private let focusMode = FocusModeState.shared

    var body: some View {
        HStack(alignment: .top, spacing: Self.handleSpacing) {
            dragHandle
            VStack(alignment: .leading, spacing: 6) {
                content
                    .blockBackground(block.content.backgroundColor)
                    .popover(isPresented: $isColorPickerShown, arrowEdge: .bottom) {
                        BlockColorPicker(block: block, model: model)
                            .presentationCompactAdaptation(.popover)
                    }
                if isFocused, let query = slashQuery {
                    SlashMenu(query: query) { type in
                        model.setType(block.id, type)
                    }
                } else if isFocused, let mention = mention {
                    PageLinkMenu(
                        query: mention.query,
                        pages: model.linkCandidates(mention.query),
                        onSelect: { model.linkPage(from: block.id, to: $0) },
                        onCreate: { model.createSubpage(from: block.id, title: $0, open: false) }
                    )
                }
            }
        }
        .padding(.vertical, verticalPadding)
        .overlay(alignment: .topLeading) { addButton }
        #if os(macOS)
        // Панель оформления рисует сам редактор поверх всех строк (PageEditorView): внутри строки
        // она висела бы за её границей, и клики уходили бы в блок выше.
        .anchorPreference(key: FormatBarAnchorKey.self, value: .bounds) { [selection = formatBarSelection] bounds in
            selection.map { FormatBarAnchor(selection: $0, bounds: bounds) }
        }
        .onChange(of: model.colorPickerRequest) { _, id in
            guard let id, id == block.id else { return }
            model.colorPickerRequest = nil
            isColorPickerShown = true
        }
        #endif
        // Режим фокуса: всё, кроме блока с курсором, приглушено.
        .opacity(focusMode.isOn && focus.wrappedValue != nil && !isFocused ? 0.3 : 1)
        .animation(.easeInOut(duration: 0.25), value: isFocused)
        .overlay { dropIndicator }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            // Перетаскивание отменили мимо строк: обычное наведение убирает оставшуюся линию.
            // Во время самого перетаскивания линию сразу ставит заново приём блока.
            if hovering, model.dropIndicator != nil {
                model.dropIndicator = nil
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onDrop(
            of: [.lumenBlock],
            delegate: BlockDropDelegate(targetId: block.id, size: size, model: model)
        )
        .modifier(BlockContextMenu(previewPage: linkedPage, database: model.database, menu: menu))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("row-\(block.text)")
    }

    /// Меню по правой кнопке или нажатию двумя пальцами: сначала частые правки,
    /// потом перемещение, удаление в самом низу.
    @ViewBuilder
    private var menu: some View {
        if let page = linkedPage {
            Button {
                model.open(page.id)
            } label: {
                Label("Открыть страницу", systemImage: "arrow.up.right")
            }
            if let workspaceActions {
                Button {
                    workspaceActions.openBeside(.page(page.id))
                } label: {
                    Label("Открыть рядом", systemImage: "rectangle.split.2x1")
                }
            }
            Divider()
        }
        Button {
            model.addBlock(below: block.id)
        } label: {
            Label("Добавить блок ниже", systemImage: "plus")
        }
        if block.type.isConvertible {
            Menu {
                ForEach(BlockType.allCases.filter(\.isConvertible)) { type in
                    Button {
                        model.setType(block.id, type)
                    } label: {
                        Label(type.title, systemImage: type.symbolName)
                    }
                    .disabled(type == block.type)
                }
            } label: {
                Label("Превратить в", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        if let target = formatMenuTarget {
            Menu {
                ForEach(FormatAction.allCases) { action in
                    Button {
                        model.apply(action, to: target)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            } label: {
                Label(model.textSelection?.blockId == block.id ? "Оформить выделенное" : "Оформить весь текст", systemImage: "textformat")
            }
        }
        if block.type.hasText {
            Button {
                // Палитра открывается после того, как закроется контекстное меню.
                DispatchQueue.main.async { isColorPickerShown = true }
            } label: {
                Label("Цвет текста и фона…", systemImage: "paintpalette")
            }
        }
        if block.type.hasText, !block.text.isEmpty {
            Button {
                copyText(block.text)
            } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }
            Button {
                sendToTasks()
            } label: {
                Label("Отправить в «Задачи» на сегодня", systemImage: "checklist")
            }
        }
        if let reference = block.content.excerpt {
            Button {
                copyLink(reference.link)
            } label: {
                Label(reference.isPlace ? "Скопировать ссылку на место" : "Скопировать ссылку на цитату", systemImage: "link")
            }
            Button {
                model.openExcerpt(reference)
            } label: {
                Label("Открыть в книге", systemImage: "book")
            }
        }
        Button {
            model.duplicateBlock(block.id)
        } label: {
            Label("Дублировать", systemImage: "plus.square.on.square")
        }
        Divider()
        Menu {
            Button {
                model.moveBlock(block.id, by: -1)
            } label: {
                Label("Вверх", systemImage: "arrow.up")
            }
            Button {
                model.moveBlock(block.id, by: 1)
            } label: {
                Label("Вниз", systemImage: "arrow.down")
            }
            if model.canIndent(block.id) {
                Button {
                    model.indent(block.id)
                } label: {
                    Label("Вложить в блок выше", systemImage: "increase.indent")
                }
            }
            if model.canOutdent(block.id) {
                Button {
                    model.outdent(block.id)
                } label: {
                    Label("Вынести на уровень выше", systemImage: "decrease.indent")
                }
            }
            if model.previousSibling(of: block.id) != nil {
                Button {
                    model.placeBesidePrevious(block.id)
                } label: {
                    Label("В колонку рядом с блоком выше", systemImage: "rectangle.split.2x1")
                }
            }
        } label: {
            Label("Переместить", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
        }
        Divider()
        Button(role: .destructive) {
            model.deleteBlock(block.id)
        } label: {
            Label("Удалить блок", systemImage: "trash")
        }
    }

    /// Страница, на которую ведёт блок-ссылка, если она жива.
    private var linkedPage: Page? {
        guard block.type == .page else { return nil }
        return model.linkedPage(block.content.pageId)
    }

    /// Что оформляет меню блока: выделенный текст, а без выделения весь текст блока.
    private var formatMenuTarget: TextSelectionInfo? {
        guard isRichText, !block.text.isEmpty else { return nil }
        if let selection = model.textSelection, selection.blockId == block.id { return selection }
        return model.wholeText(of: block.id)
    }

    /// Текст блока задачей на сегодня. Блок остаётся на странице.
    private func sendToTasks() {
        let title = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let database = model.database
        Task {
            if await NoticeCenter.shared.attempt("Не удалось добавить задачу", {
                _ = try await Creator.addTodayTask(title: title, in: database)
            }) {
                LumenSounds.play(.create)
                NoticeCenter.shared.show("Задача на сегодня добавлена")
            }
        }
    }

    /// Куда встанет перетаскиваемый блок: линия сверху, снизу или справа (новая колонка).
    @ViewBuilder
    private var dropIndicator: some View {
        switch model.dropIndicator?.blockId == block.id ? model.dropIndicator?.zone : nil {
        case .before:
            VStack {
                Capsule().fill(theme.accent).frame(height: 3).offset(y: -3)
                Spacer()
            }
        case .after:
            VStack {
                Spacer()
                Capsule().fill(theme.accent).frame(height: 3).offset(y: 3)
            }
        case .beside:
            HStack {
                Spacer()
                Capsule().fill(theme.accent).frame(width: 3)
            }
        case nil:
            EmptyView()
        }
    }

    private var isFocused: Bool {
        focus.wrappedValue == .block(block.id)
    }

    /// Текст после `/` в пустом абзаце открывает меню выбора типа блока.
    private var slashQuery: String? {
        guard block.type == .paragraph, block.text.hasPrefix("/") else { return nil }
        return String(block.text.dropFirst())
    }

    /// `[[` или `@` в конце текста открывает меню ссылок на страницы.
    private var mention: MentionTrigger.Match? {
        guard block.type.hasText, block.type != .code else { return nil }
        return MentionTrigger.match(block.text)
    }

    /// Ручка слева от блока: потяните, чтобы переставить блок. На Mac видна при наведении.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .frame(width: Self.handleWidth, height: 24)
            .contentShape(Rectangle())
            .opacity(handleOpacity)
            // Какой блок тянут, запоминаем в модели в момент начала перетаскивания: так приём
            // не зависит от того, сумеет ли система передать и расшифровать свой тип данных.
            .onDrag {
                model.draggingBlockId = block.id
                model.dropIndicator = nil
                let provider = NSItemProvider()
                provider.register(BlockDragItem(blockId: block.id))
                return provider
            } preview: {
                Label(dragTitle, systemImage: block.type.symbolName)
                    .padding(8)
                    .lumenCard(padding: 4)
            }
            .help("Перетащите, чтобы переместить блок")
            .accessibilityLabel("Переместить блок")
            .accessibilityIdentifier("handle-\(block.text)")
    }

    /// «+» слева от ручки на Mac: новый пустой блок сразу под этим.
    @ViewBuilder
    private var addButton: some View {
        #if os(macOS)
        if isHovered, model.draggingBlockId == nil {
            Button {
                model.addBlock(below: block.id)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 20, height: 22)
                    .background(theme.textPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: -24, y: 1)
            .help("Добавить блок ниже. Или нажмите «/» в пустой строке")
            .accessibilityLabel("Добавить блок ниже")
        }
        #endif
    }

    private var handleOpacity: Double {
        #if os(macOS)
        return isHovered || isFocused ? 0.8 : 0
        #else
        return isFocused ? 0.8 : 0.25
        #endif
    }

    private var dragTitle: String {
        if block.type == .page { return model.linkedPage(block.content.pageId)?.displayTitle ?? block.type.title }
        return block.text.isEmpty ? block.type.title : String(block.text.prefix(40))
    }

    @ViewBuilder
    private var content: some View {
        switch block.type {
        case .divider:
            Rectangle()
                .fill(theme.textSecondary.opacity(0.35))
                .frame(height: 1)
                .padding(.vertical, 10)
                .contentShape(Rectangle().inset(by: -8))

        case .bulletedList:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(["•", "◦", "▪"][depth % 3])
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.accent)
                field
            }

        case .numberedList:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
                field
            }

        case .todo:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    LumenSounds.play(block.content.isChecked ? .tap : .toggle)
                    model.toggleChecked(block.id)
                } label: {
                    Image(systemName: block.content.isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(block.content.isChecked ? theme.accent : theme.textSecondary)
                }
                .buttonStyle(.plain)
                field
                    .strikethrough(block.content.isChecked)
                    .opacity(block.content.isChecked ? 0.55 : 1)
            }

        case .quote:
            HStack(spacing: 12) {
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 3)
                field
                    .italic()
            }
            .fixedSize(horizontal: false, vertical: true)

        case .callout:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("💡")
                field
            }
            .lumenCard(padding: 12)

        case .code:
            CodeBlockBody(code: block.text, isEditing: isFocused, font: font) {
                field
            }

        case .page:
            PageLinkBlock(page: linkedPage, database: model.database) {
                if let pageId = block.content.pageId {
                    model.open(pageId)
                }
            }

        case .image:
            ImageBlock(block: block, model: model)

        case .drawing:
            DrawingBlock(block: block, model: model)

        case .excerpt:
            ExcerptBlock(
                text: block.text,
                reference: block.content.excerpt,
                source: model.source(block.content.excerpt?.sourceId),
                attachments: model.database.attachments
            ) {
                if let reference = block.content.excerpt {
                    model.openExcerpt(reference)
                }
            }

        case .toggle:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    model.toggleCollapsed(block.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(block.content.isCollapsed ? 0 : 90))
                        .animation(.snappy, value: block.content.isCollapsed)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                field
            }

        case .columnList, .column:
            EmptyView()

        case .paragraph, .heading1, .heading2, .heading3:
            field
        }
    }

    private var field: some View {
        TextField(placeholder, text: fieldText, axis: .vertical)
        .textFieldStyle(.plain)
        .font(font)
        .foregroundStyle(fieldColor)
        .focused(focus, equals: .block(block.id))
        .onSubmit { model.submit(block.id) }
        // Backspace в пустом блоке ловит редактор: на Mac через NSEvent, на iPhone через
        // подменённый deleteBackward (PageEditorView.installKeyMonitor, EmptyBackspace).
        // ⌥⌘↑ и ⌥⌘↓ двигают блок, как в Notion.
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.command), press.modifiers.contains(.option) else { return .ignored }
            model.moveBlock(block.id, by: press.key == .upArrow ? -1 : 1)
            return .handled
        }
        // Tab вкладывает блок в предыдущий, ⇧Tab выносит на уровень выше.
        .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
            if press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}") {
                guard model.canOutdent(block.id) else { return .ignored }
                model.outdent(block.id)
            } else {
                guard model.canIndent(block.id) else { return .ignored }
                model.indent(block.id)
            }
            return .handled
        }
        // ⌘D дублирует блок.
        .onKeyPress(keys: ["d"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.duplicateBlock(block.id)
            return .handled
        }
        // ⌘B, ⌘I, ⌘U, ⇧⌘X и ⌘E: оформление выделенного текста.
        .onKeyPress(keys: ["b", "i", "u", "x", "X", "e"]) { press in
            guard isRichText, press.modifiers.contains(.command), !press.modifiers.contains(.option) else { return .ignored }
            let action: FormatAction
            switch press.key.character {
            case "b": action = .bold
            case "i": action = .italic
            case "u": action = .underline
            case "e": action = .code
            case "x", "X":
                guard press.modifiers.contains(.shift) else { return .ignored }
                action = .strikethrough
            default: return .ignored
            }
            TextFormatting.perform(action, model: model, blockId: block.id)
            return .handled
        }
        .overlay(alignment: .topLeading) {
            if showsRenderedText {
                Text(RichTextRendering.attributed(InlineMarkup.normalized(block.content.runs), linkColor: theme.accent))
                    .font(font)
                    .foregroundStyle(block.content.textColor.map(\.textColor) ?? theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        #if os(macOS)
        // Выделение на Mac: над ним всплывает панель оформления.
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { notification in
            guard isFocused, isRichText, let textView = notification.object as? NSTextView,
                  textView === NSApp.keyWindow?.firstResponder else { return }
            let info = TextFormatting.currentSelection(blockId: block.id)
            if model.textSelection != info { model.textSelection = info }
        }
        #endif
        .onChange(of: isFocused) { _, focused in
            if focused {
                TextFormatMenu.editor = model
            } else {
                editingSource = nil
                if model.textSelection?.blockId == block.id { model.textSelection = nil }
            }
        }
        // Разметку поменяли не набором (отмена, смена типа): поле берёт её заново.
        .onChange(of: block.content.runs) { _, runs in
            guard let editingSource, InlineMarkup.runs(from: editingSource) != InlineMarkup.normalized(runs) else { return }
            self.editingSource = nil
        }
        .onChange(of: model.selectionRestore) { _, restore in
            guard let restore, restore.blockId == block.id else { return }
            model.selectionRestore = nil
            restoreSelection(restore.range)
        }
    }

    // MARK: Оформление текста

    /// Обычный текст с оформлением. В коде оформления нет: там разметка была бы самим кодом.
    private var isRichText: Bool {
        block.type.hasText && block.type != .code
    }

    private var markupSource: String {
        editingSource ?? InlineMarkup.source(block.content.runs)
    }

    /// В поле видна разметка: **жирный**, *курсив*. Вне фокуса поверх лежит уже оформленный текст.
    private var fieldText: Binding<String> {
        guard isRichText else {
            return Binding(get: { block.text }, set: { model.updateText(block.id, to: $0) })
        }
        return Binding(
            get: { markupSource },
            set: { value in
                editingSource = value
                model.updateMarkup(block.id, to: value)
            }
        )
    }

    /// Оформленный текст рисуется поверх поля, когда курсор не в блоке.
    private var showsRenderedText: Bool {
        isRichText && !isFocused && InlineMarkup.hasFormatting(block.content.runs)
    }

    /// После смены оформления разметка в поле другая: выделение ставится на тот же текст.
    private func restoreSelection(_ range: Range<Int>) {
        let source = InlineMarkup.source(block.content.runs)
        editingSource = source
        let target = InlineMarkup.parse(source).sourceRange(forPlain: range)
        ActiveTextField.select(target, whenTextIs: source)
    }

    /// Выделенный текст этого блока, над которым на Mac стоит панель оформления.
    /// На iPhone и iPad панель над клавиатурой (PageEditorView).
    private var formatBarSelection: TextSelectionInfo? {
        guard isFocused, let info = model.textSelection, info.blockId == block.id else { return nil }
        return info
    }

    /// Код вне редактирования рисует подсвеченная копия поверх поля, само поле тогда прозрачное.
    private var fieldColor: Color {
        if block.type == .code, !isFocused, !block.text.isEmpty { return .clear }
        if showsRenderedText { return .clear }
        return block.content.textColor.map(\.textColor) ?? theme.textPrimary
    }

    private var placeholder: String {
        switch block.type {
        case .paragraph: isFocused ? "Пишите или нажмите «/»: заголовок, список, задача, картинка…" : ""
        case .heading1: "Заголовок 1"
        case .heading2: "Заголовок 2"
        case .heading3: "Заголовок 3"
        case .bulletedList, .numberedList: "Пункт списка"
        case .todo: "Задача"
        case .quote: "Цитата"
        case .callout: "Выноска"
        case .code: "Код"
        case .toggle: "Сворачиваемый блок"
        case .divider, .page, .image, .columnList, .column, .excerpt, .drawing: ""
        }
    }

    private var font: Font {
        switch block.type {
        case .heading1: .system(size: 30, weight: .bold)
        case .heading2: .system(size: 24, weight: .semibold)
        case .heading3: .system(size: 19, weight: .semibold)
        case .code: .system(.callout, design: .monospaced)
        default: .system(size: 17)
        }
    }

    private var verticalPadding: CGFloat {
        switch block.type {
        case .heading1: 10
        case .heading2: 8
        case .heading3: 6
        default: 2
        }
    }
}

enum BlockDropZone: Equatable {
    case before, after, beside
}

struct DropIndicator: Equatable {
    var blockId: UUID
    var zone: BlockDropZone
}

/// Приём перетаскиваемого блока: верхняя половина строки ставит его перед целью, нижняя после,
/// правая четверть ставит рядом в новую колонку.
struct BlockDropDelegate: DropDelegate {
    let targetId: UUID
    let size: CGSize
    let model: PageEditorModel

    private func zone(at location: CGPoint) -> BlockDropZone {
        if size.width > 0, location.x > size.width * 0.75 { return .beside }
        return location.y < size.height / 2 ? .before : .after
    }

    func validateDrop(info: DropInfo) -> Bool {
        model.draggingBlockId != nil || info.hasItemsConforming(to: [.lumenBlock])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let indicator = DropIndicator(blockId: targetId, zone: zone(at: info.location))
        if model.dropIndicator != indicator {
            model.dropIndicator = indicator
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if model.dropIndicator?.blockId == targetId {
            model.dropIndicator = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = zone(at: info.location)
        model.dropIndicator = nil
        if let dragged = model.draggingBlockId {
            model.draggingBlockId = nil
            Self.apply(target, moving: dragged, to: targetId, in: model)
            return true
        }
        // Запасной путь: блок пришёл без отметки в модели, читаем его из данных перетаскивания.
        guard let provider = info.itemProviders(for: [.lumenBlock]).first else { return false }
        let targetId = targetId
        let model = model
        _ = provider.loadTransferable(type: BlockDragItem.self) { result in
            guard case .success(let item) = result else { return }
            Task { @MainActor in
                Self.apply(target, moving: item.blockId, to: targetId, in: model)
            }
        }
        return true
    }

    @MainActor
    private static func apply(_ zone: BlockDropZone, moving id: UUID, to targetId: UUID, in model: PageEditorModel) {
        switch zone {
        case .before: model.moveBlock(id, nextTo: targetId, after: false)
        case .after: model.moveBlock(id, nextTo: targetId, after: true)
        case .beside: model.placeBeside(id, targetId)
        }
    }
}

/// Что переносится при перетаскивании блока. Свой тип данных, чтобы блок
/// нельзя было случайно бросить в текстовое поле как строку.
struct BlockDragItem: Codable, Transferable {
    let blockId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .lumenBlock)
    }
}

extension UTType {
    static let lumenBlock = UTType(exportedAs: "app.lumen.block")
}

/// Блок-ссылка на другую страницу или подстраницу. Курсор задержался на ссылке:
/// всплывает карточка с началом страницы и кнопками «Открыть» и «Открыть рядом».
private struct PageLinkBlock: View {
    let page: Page?
    let database: AppDatabase
    var onOpen: () -> Void

    @State private var isPreviewShown = false
    /// Курсор над самой карточкой: пока он там, карточка не закрывается.
    @State private var isCardHovered = false
    @State private var hoverTask: Task<Void, Never>?
    @Environment(\.workspaceActions) private var workspaceActions
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                if let page {
                    PageLabel(page: page)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .underline(color: theme.textSecondary.opacity(0.5))
                } else {
                    Label("Страница удалена", systemImage: "doc.questionmark")
                        .foregroundStyle(theme.textSecondary)
                }
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(page == nil)
        .onHover { hovering in
            guard page != nil else { return }
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if !Task.isCancelled { isPreviewShown = true }
                }
            } else {
                closeSoon()
            }
        }
        .popover(isPresented: $isPreviewShown, arrowEdge: .bottom) {
            if let page {
                PageLinkPreview(
                    page: page,
                    database: database,
                    onOpen: {
                        isPreviewShown = false
                        onOpen()
                    },
                    onOpenBeside: openBesideAction(page)
                )
                .onHover { hovering in
                    isCardHovered = hovering
                    if hovering {
                        hoverTask?.cancel()
                    } else {
                        closeSoon()
                    }
                }
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    /// «Открыть рядом» есть там, где окно умеет делиться на две панели.
    private func openBesideAction(_ page: Page) -> (() -> Void)? {
        guard let workspaceActions else { return nil }
        return {
            isPreviewShown = false
            workspaceActions.openBeside(.page(page.id))
        }
    }

    /// Курсор ушёл со ссылки: даём время дойти до карточки, иначе закрываем.
    private func closeSoon() {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled, !isCardHovered { isPreviewShown = false }
        }
    }
}

/// Меню блока по правой кнопке или долгому нажатию. У ссылки на страницу на iPhone и iPad
/// долгое нажатие показывает над меню карточку с началом этой страницы.
private struct BlockContextMenu<MenuItems: View>: ViewModifier {
    let previewPage: Page?
    let database: AppDatabase
    let menu: MenuItems

    func body(content: Content) -> some View {
        #if os(iOS)
        if let previewPage {
            content.contextMenu {
                menu
            } preview: {
                PageLinkPreview(page: previewPage, database: database)
            }
        } else {
            content.contextMenu { menu }
        }
        #else
        content.contextMenu { menu }
        #endif
    }
}

/// Выписка из книги: цитата, книга и место. Нажатие открывает книгу на этом месте.
private struct ExcerptBlock: View {
    let text: String
    let reference: ExcerptReference?
    let source: Source?
    let attachments: AttachmentStore
    var onOpen: () -> Void

    @State private var isPreviewShown = false
    @State private var hoverTask: Task<Void, Never>?
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if reference?.isPlace == true {
                placeLink
            } else if theme.layout == .rooms {
                clipping
            } else {
                quote
            }
        }
        // Курсор задержался на цитате: карточка с книгой и местом, откуда она.
        .onHover { hovering in
            hoverTask?.cancel()
            guard source != nil else { return }
            if hovering {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if !Task.isCancelled { isPreviewShown = true }
                }
            } else {
                isPreviewShown = false
            }
        }
        .popover(isPresented: $isPreviewShown, arrowEdge: .bottom) {
            if let source {
                ExcerptPreviewCard(text: text, reference: reference, source: source, attachments: attachments)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    /// Ссылка на место без цитаты: книга и место, нажатие открывает книгу там.
    private var placeLink: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(tint)
                if !text.isEmpty {
                    Text(text)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                }
                Text(caption)
                    .lineLimit(1)
                    .foregroundStyle(source == nil ? theme.textSecondary.opacity(0.7) : theme.accent)
                if source != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .font(.callout.weight(.medium))
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.16), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(source == nil)
        .help(source == nil ? "Книгу удалили" : "Открыть книгу на этом месте")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quote: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Text("\u{201C}")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(tint.opacity(0.85))
                    .frame(height: 22, alignment: .top)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(.system(size: 17, design: .serif))
                        .italic()
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Image(systemName: source?.format.symbolName ?? "book.closed")
                        Text(caption)
                            .lineLimit(1)
                        if source != nil {
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(source == nil ? theme.textSecondary.opacity(0.7) : theme.accent)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 12)
            .padding(.horizontal, 14)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tint.opacity(0.16), lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(source == nil)
        .help(source == nil ? "Книгу удалили" : "Открыть книгу на этом месте")
    }

    /// «Кабинет»: выписка вклеена в тетрадь, как вырезка из книги, с полосками скотча сверху.
    private var clipping: some View {
        let paper = Color(hex: 0xEFE4CC)
        let ink = Color(hex: 0x2A2118)
        return Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\u{AB}\(text)\u{BB}")
                    .font(.system(size: 17, design: .serif))
                    .italic()
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(source == nil ? caption : "вклейка · \(caption)")
                        .lineLimit(1)
                    if source != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.bold))
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(hex: 0x7A5A1E).opacity(source == nil ? 0.6 : 1))
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            .padding(.horizontal, 16)
            .background(paper, in: Rectangle())
            .overlay(alignment: .topLeading) { tape(angle: -8).offset(x: 10, y: -6) }
            .overlay(alignment: .topTrailing) { tape(angle: 7).offset(x: -10, y: -6) }
            .shadow(color: .black.opacity(0.35), radius: 3, x: 1, y: 2)
            .rotationEffect(.degrees(-0.4))
            .padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(source == nil)
        .help(source == nil ? "Книгу удалили" : "Открыть книгу на этом месте")
    }

    /// Полоска полупрозрачного скотча.
    private func tape(angle: Double) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.38))
            .frame(width: 38, height: 13)
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
            .rotationEffect(.degrees(angle))
            .accessibilityHidden(true)
    }

    /// Мягкий тёплый тон цитаты.
    private var tint: Color {
        theme.vividCard(1).colors.first ?? theme.accent
    }

    private var caption: String {
        guard let source else { return "Книга удалена" }
        let label = reference?.label ?? ""
        return label.isEmpty ? source.displayTitle : "\(source.displayTitle) · \(label)"
    }
}

/// Превью цитаты: обложка, книга, место и полный текст выписки.
private struct ExcerptPreviewCard: View {
    let text: String
    let reference: ExcerptReference?
    let source: Source
    let attachments: AttachmentStore

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SourceCoverArt(source: source, attachments: attachments, width: 52, height: 74)
            VStack(alignment: .leading, spacing: 5) {
                Text(source.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                if let author = source.author, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                if let label = reference?.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                if !text.isEmpty {
                    Text(text)
                        .font(.system(.callout, design: .serif))
                        .italic()
                        .lineLimit(6)
                        .padding(.top, 2)
                }
                Text("Нажмите на цитату, чтобы открыть это место")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.top, 2)
            }
            .frame(width: 240, alignment: .leading)
        }
        .padding(14)
    }
}

/// Блок-картинка. Пока картинка не выбрана, показывает кнопки выбора из фото и файлов.
private struct ImageBlock: View {
    let block: Block
    let model: PageEditorModel

    @State private var photo: PhotosPickerItem?
    @State private var isImportingFile = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if let name = block.content.attachment {
                AttachmentImage(name: name, attachments: model.database.attachments)
                    .frame(maxWidth: .infinity, maxHeight: 460, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                picker
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.setImage(block.id, data: data, fileExtension: nil)
                }
                photo = nil
            }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                model.setImage(block.id, data: data, fileExtension: url.pathExtension)
            }
        }
    }

    private var picker: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(theme.textSecondary)
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Выбрать фото", systemImage: "photo.on.rectangle")
            }
            Button {
                isImportingFile = true
            } label: {
                Label("Из файлов", systemImage: "folder")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .lumenCard(padding: 14)
    }
}

/// Меню ссылок на страницы по `[[` и `@`.
struct PageLinkMenu: View {
    let query: String
    let pages: [Page]
    var onSelect: (UUID) -> Void
    var onCreate: (String) -> Void

    @Environment(\.lumenTheme) private var theme

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ссылка на страницу")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.top, 4)
            ForEach(pages) { page in
                menuButton { onSelect(page.id) } label: { PageLabel(page: page) }
            }
            menuButton {
                onCreate(trimmedQuery)
            } label: {
                Label(
                    trimmedQuery.isEmpty ? "Новая подстраница" : "Новая подстраница «\(trimmedQuery)»",
                    systemImage: "doc.badge.plus"
                )
            }
        }
        .frame(maxWidth: 320)
        .lumenCard(padding: 6)
    }

    private func menuButton<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Меню типов блоков по `/`.
struct SlashMenu: View {
    let query: String
    var onSelect: (BlockType) -> Void

    @Environment(\.lumenTheme) private var theme

    private var types: [BlockType] {
        BlockType.allCases.filter { $0.isInsertable && $0.matches(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if types.isEmpty {
                Text("Ничего не найдено")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .padding(8)
            }
            ForEach(types) { type in
                Button {
                    onSelect(type)
                } label: {
                    Label(type.title, systemImage: type.symbolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 300)
        .lumenCard(padding: 6)
    }
}
