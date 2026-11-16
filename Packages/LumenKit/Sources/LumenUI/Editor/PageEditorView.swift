import LumenCore
import LumenStorage
import LumenThemes
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

private enum PhotoTarget {
    case cover
    case background
}

enum EditorFocus: Hashable {
    case title
    case block(UUID)
    /// Ячейка таблицы: блок, строка, столбец.
    case cell(UUID, Int, Int)
}

/// Редактор страницы. Первая простая версия по плану: каждый блок это отдельное текстовое поле
/// в ленивом стеке. Markdown-сокращения, slash-меню, Return и Backspace работают как в Notion.
struct PageEditorView: View {
    @State private var model: PageEditorModel
    /// Редактор встроен в другой экран (заметки рядом с книгой): без своих кнопок в панели окна.
    var isEmbedded = false
    var onOpenPage: (UUID) -> Void
    var onClose: () -> Void
    /// Открыть книгу, а если указано выделение, то на его месте.
    var onOpenSource: (UUID, UUID?) -> Void = { _, _ in }

    @FocusState private var focus: EditorFocus?
    /// В разделённом экране кнопки в панели окна и ⌘Z только у активной панели.
    @Environment(\.isActivePane) private var isActivePane
    /// Куда пойдёт фото из галереи: в обложку или в фон страницы.
    @State private var photoTarget: PhotoTarget = .cover
    @State private var isPickingPhoto = false
    /// Фото для фона выбирают после закрытия окна фона: два окна сразу показать нельзя.
    @State private var wantsBackgroundPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isEditingBackground = false
    /// Формат, в который выгружают страницу из меню «Экспорт».
    @State private var exportRequest: PageExportFormat?
    @State private var isMovingToFolder = false
    @State private var isShowingHistory = false
    @State private var isPickingIcon = false
    @State private var focusTask: Task<Void, Never>?
    #if os(macOS)
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    /// Окно редактора: клавиши выделения блоков работают только в нём.
    @State private var windowBox = EditorWindowBox()
    #endif
    /// Насколько прокручена страница: по ней солнце на горах опускается за гряды.
    /// Отдельный объект: прокрутку читают только фон и обложка, и редактор со всеми блоками
    /// не пересчитывается на каждом кадре прокрутки.
    @State private var scroll = PageScrollOffset()
    /// Открыта ли панель подстраниц справа. Запоминается между страницами и запусками,
    /// а анимируется копия в `showsSubpages`: изменение `@AppStorage` анимацию не несёт.
    @AppStorage("editor.subpagesPanel") private var remembersSubpages = false
    @State private var showsSubpages = false
    @AppStorage(LumenSounds.enabledKey) private var soundsEnabled = true
    @AppStorage(ScreenOptions.breadcrumbsKey) private var showsBreadcrumbs = false
    /// Листы, видные на экране (по якорю листа): по ним подсвечивается заголовок на карте и номер листа.
    /// Отдельный объект: его читают только карта и миниатюры, и редактор со всеми листами
    /// не пересчитывается, когда при листании на экран выходит следующий лист.
    @State private var visibility = SheetVisibility()
    /// Есть ли место рядом с листом для миниатюр листов слева. Только да или нет, а не ширина:
    /// иначе весь редактор со всеми листами пересчитывался бы на каждом кадре изменения размера окна.
    @State private var hasRoomForRail = false
    /// Над заметкой держат выписку, утащенную из книги.
    @State private var isExcerptTargeted = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme
    private let focusMode = FocusModeState.shared

    private static let coverGradients = ["Персик", "Солнце", "Лаванда", "Лайм", "Небо"]

    init(
        database: AppDatabase,
        pageId: UUID,
        onOpenPage: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void,
        onOpenSource: @escaping (UUID, UUID?) -> Void = { _, _ in }
    ) {
        _model = State(initialValue: PageEditorModel(database: database, pageId: pageId))
        self.onOpenPage = onOpenPage
        self.onClose = onClose
        self.onOpenSource = onOpenSource
    }

    /// Встроенный редактор: модель создаёт и держит экран вокруг, например читалка, чтобы вставлять выписки.
    init(
        model: PageEditorModel,
        onOpenPage: @escaping (UUID) -> Void,
        onOpenSource: @escaping (UUID, UUID?) -> Void
    ) {
        _model = State(initialValue: model)
        isEmbedded = true
        self.onOpenPage = onOpenPage
        self.onClose = {}
        self.onOpenSource = onOpenSource
    }

    var body: some View {
        Group {
            if model.isNotebook {
                NotebookView(model: model, focus: $focus, isCompact: isCompact)
            } else {
                blockPage
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scroll.offset = max(offset, 0)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            ScrolledPageBackground(
                scroll: scroll,
                background: model.page?.pageBackground,
                attachments: model.database.attachments
            )
        )
        .modifier(EditorNavigationTitle(title: model.isLoaded ? displayTitle : "", isEnabled: !isEmbedded && isActivePane))
        .pageExport(database: model.database, pageId: model.pageId, request: $exportRequest) {
            await model.flush()
        }
        .toolbar {
            #if os(iOS)
            // На экранной клавиатуре нет Tab: вложенность меняется кнопками над клавиатурой.
            ToolbarItemGroup(placement: .keyboard) {
                if case .block(let id) = focus {
                    Button {
                        model.addBlock(below: id)
                    } label: {
                        Label("Новый блок", systemImage: "plus")
                    }
                    Button {
                        model.outdent(id)
                    } label: {
                        Label("Вынести на уровень выше", systemImage: "decrease.indent")
                    }
                    .disabled(!model.canOutdent(id))
                    Button {
                        model.indent(id)
                    } label: {
                        Label("Вложить в блок выше", systemImage: "increase.indent")
                    }
                    .disabled(!model.canIndent(id))
                    Button {
                        model.moveBlock(id, by: -1)
                    } label: {
                        Label("Переместить вверх", systemImage: "arrow.up")
                    }
                    Button {
                        model.moveBlock(id, by: 1)
                    } label: {
                        Label("Переместить вниз", systemImage: "arrow.down")
                    }
                    Spacer()
                    // На iPhone в панели окна места нет: отмена и повтор над клавиатурой.
                    if isCompact && !isEmbedded {
                        Button {
                            model.undo()
                        } label: {
                            Label("Отменить", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!model.canUndo)
                    }
                    Button {
                        focus = nil
                    } label: {
                        Label("Спрятать клавиатуру", systemImage: "keyboard.chevron.compact.down")
                    }
                }
            }
            #endif
            if !isEmbedded && isActivePane {
                editorToolbar
            }
        }
        .overlay(alignment: .trailing) {
            // Панель плавает над текстом и не сдвигает его: 80% высоты окна редактора.
            // Она всегда в дереве и уезжает за правый край: так выезд анимируется в обе стороны.
            GeometryReader { geometry in
                let width = min(300, geometry.size.width - 32)
                SubpagesPanel(
                    subpages: model.subpages,
                    onOpen: { model.open($0) },
                    onAdd: {
                        LumenSounds.play(.create)
                        model.addSubpage()
                    },
                    onClose: { setSubpagesPanel(false) }
                )
                .frame(width: width, height: geometry.size.height * 0.8)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: showsSubpages ? 0 : width + 60)
                .opacity(showsSubpages ? 1 : 0)
                .allowsHitTesting(showsSubpages)
                // Закрытая панель не ловит Escape и не видна VoiceOver.
                .disabled(!showsSubpages)
                .accessibilityHidden(!showsSubpages)
            }
        }
        .onAppear {
            showsSubpages = remembersSubpages && !isEmbedded
            // Встроенный редактор держит читалка, она и так знает про него.
            if !isEmbedded { OpenPageEditors.shared.register(model, id: model.pageId) }
        }
        .task {
            await model.load()
            // В новой рукописной заметке сразу пишут на листе, клавиатура не нужна.
            if model.title.isEmpty, !model.isNotebook {
                focus = .title
            }
            // Заметку открыли с полки приколотым листом: прокрутка к нему, когда листы построятся.
            if let sheet = SheetJump.take(model.pageId), sheet > 0, !model.isNotebook {
                try? await Task.sleep(for: .milliseconds(150))
                model.sheetScrollRequest = sheet
            }
            await model.observeLinks()
        }
        .focusedSceneValue(\.pageEditor, isActivePane ? model : nil)
        .onChange(of: model.openRequest) { _, request in
            guard let request else { return }
            model.openRequest = nil
            onOpenPage(request)
        }
        .onChange(of: model.openSourceRequest) { _, request in
            guard let request else { return }
            model.openSourceRequest = nil
            onOpenSource(request.sourceId, request.highlightId)
        }
        .photosPicker(
            isPresented: $isPickingPhoto,
            selection: $pickedPhoto,
            matching: .images
        )
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            let target = photoTarget
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    switch target {
                    case .cover: model.setCoverImage(data: data)
                    case .background: model.setBackgroundImage(data: data)
                    }
                }
                pickedPhoto = nil
            }
        }
        .sheet(isPresented: $isShowingHistory) {
            PageHistorySheet(model: model) { isShowingHistory = false }
        }
        .sheet(isPresented: $isMovingToFolder) {
            if let page = model.page {
                MoveToFolderSheet(
                    database: model.database,
                    item: .page(page.id),
                    currentFolderId: page.folderId,
                    // Заметке из «Входящих» и подстранице подходит любая папка, включая корень.
                    isFromInbox: page.inInbox || page.parentId != nil
                ) {
                    isMovingToFolder = false
                }
            }
        }
        .sheet(isPresented: $isEditingBackground, onDismiss: {
            if wantsBackgroundPhoto {
                wantsBackgroundPhoto = false
                photoTarget = .background
                isPickingPhoto = true
            }
        }) {
            PageBackgroundPicker(model: model) {
                wantsBackgroundPhoto = true
            }
        }
        .onChange(of: model.focusRequest) { _, request in
            guard let request else { return }
            model.focusRequest = nil
            moveFocus(to: .block(request))
        }
        .onChange(of: model.cellFocusRequest) { _, request in
            guard let request else { return }
            model.cellFocusRequest = nil
            moveFocus(to: .cell(request.blockId, request.row, request.column))
        }
        .onChange(of: model.focusTitleRequest) { _, requested in
            guard requested else { return }
            model.focusTitleRequest = false
            focus = .title
        }
        .onChange(of: focus) { _, newFocus in
            // Курсор встал в текст (здесь или в соседней панели): выделение блоков снимается.
            if newFocus != nil, let owner = BlockSelectionOwner.current, owner.hasBlockSelection {
                owner.clearSelection()
            }
            if case .block(let id) = newFocus {
                model.focusedBlockId = id
                // Курсор ушёл в текст: рисование в блоке «Рисунок» заканчивается.
                model.stopDrawing()
            } else {
                model.focusedBlockId = nil
            }
        }
        // Выделили блоки: курсор уходит из текста, иначе клавиши правили бы текст, а не блоки.
        .onChange(of: model.hasBlockSelection) { _, selected in
            if selected, focus != nil { focus = nil }
        }
        #if os(macOS)
        .background(EditorWindowReader(box: windowBox))
        .onAppear {
            installKeyMonitor()
            installMouseMonitor()
            TextFormatMenu.install()
        }
        #else
        .onAppear {
            EmptyBackspace.install()
            TextFormatMenu.install()
        }
        // Стирание на пустом блоке: экранная клавиатура не даёт об этом знать иначе.
        .onReceive(NotificationCenter.default.publisher(for: .lumenBackspaceInEmptyField)) { _ in
            guard let id = model.focusedBlockId else { return }
            _ = model.backspaceInEmptyBlock(id)
        }
        #endif
        .onDisappear {
            #if os(macOS)
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            #endif
            if BlockSelectionOwner.current === model { model.clearSelection() }
            if !isEmbedded { OpenPageEditors.shared.unregister(model, id: model.pageId) }
            Task { await model.flush() }
        }
    }

    /// Обычная страница из блоков: обложка, заголовок, блоки и обратные ссылки.
    private var blockPage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Обложка на всю ширину окна, от края до края, как в Notion.
                    if let cover = model.page?.pageCover {
                        ScrolledPageCover(scroll: scroll, cover: cover, attachments: model.database.attachments)
                    }
                    content
                }
            }
            .keyHintClip()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.hasBlockSelection {
                    BlockSelectionBar(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(LumenMotion.standard, value: model.hasBlockSelection)
            .onScrollTargetVisibilityChange(idType: UUID.self) { ids in
                visibility.ids = ids
                let anchors = model.sheets.map { sheetAnchor($0) }
                if let first = ids.compactMap({ anchors.firstIndex(of: $0) }).min(), model.visibleSheet != first {
                    model.visibleSheet = first
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size.width >= Self.railMinWidth } action: { hasRoomForRail = $0 }
            .onChange(of: model.sheetScrollRequest) { _, request in
                guard let request else { return }
                model.sheetScrollRequest = nil
                scrollToSheet(request, proxy: proxy)
            }
            .overlay(alignment: .topLeading) {
                if showsSheetRail {
                    LiveSheetRail(
                        model: model,
                        onSelect: { scrollToSheet($0, proxy: proxy) },
                        onAdd: {
                            LumenSounds.play(.addSheet)
                            model.addSheet()
                        },
                        onDelete: { index in
                            LumenSounds.play(.trash)
                            model.deleteSheet(index)
                        }
                    )
                    .padding(.leading, 16)
                    .padding(.top, 24)
                }
            }
            // Выписку из книги можно дотащить до заметки: она встанет выпиской со ссылкой на место.
            .onDrop(of: [.lumenExcerpt], isTargeted: $isExcerptTargeted) { providers in
                ExcerptDrag.accept(providers, into: model)
            }
            .overlay { ExcerptDropHighlight(isTargeted: isExcerptTargeted) }
            .animation(LumenMotion.quick, value: isExcerptTargeted)
            .overlay(alignment: .bottomTrailing) {
                if !isEmbedded, !isCompact, isActivePane {
                    LiveWordCount(
                        model: model,
                        isFocusMode: focusMode.isOn,
                        onToggleFocus: { focusMode.toggle() },
                        timerEnd: focusMode.timerEnd,
                        onStartTimer: { focusMode.startTimer() },
                        onStopTimer: { focusMode.stopTimer() }
                    )
                    .padding(18)
                }
            }
            #if os(iOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // В блоке есть текст: над клавиатурой панель оформления, она берёт выделение из поля.
                // В пустом блоке на iPhone вместо неё ряд типов блока.
                if case .block(let id) = focus, let block = model.findBlock(id), block.type.hasText, block.type != .code,
                   !block.text.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        FormatBar(model: model, blockId: id)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                } else if isCompact, case .block(let id) = focus, let block = model.findBlock(id), block.type.isConvertible {
                    BlockTypeChips(current: block.type) { model.setType(id, $0) }
                }
            }
            #endif
            .overlay(alignment: .trailing) {
                if showsOutline, !showsSubpages {
                    LiveOutline(model: model, visibility: visibility) { item in
                        LumenSounds.play(.navigate)
                        // Лист в ленивом списке мог ещё не построиться: сначала к листу, потом к заголовку.
                        if let sheet = model.sheets.first(where: { $0.blocks.contains { $0.id == item.anchorId } }) {
                            proxy.scrollTo(sheetAnchor(sheet), anchor: .top)
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(30))
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(item.anchorId, anchor: .top)
                            }
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup {
            if !isCompact {
                Button {
                    model.undo()
                } label: {
                    Label("Отменить", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                Button {
                    model.redo()
                } label: {
                    Label("Повторить", systemImage: "arrow.uturn.forward")
                }
                .disabled(!model.canRedo)
            }
        }
        ToolbarItem {
            Menu {
                Button {
                    model.toggleFavorite()
                } label: {
                    if model.page?.isFavorite == true {
                        Label("Убрать из избранного", systemImage: "star.slash")
                    } else {
                        Label("В избранное", systemImage: "star")
                    }
                }
                if model.page?.inInbox == true {
                    Button {
                        model.moveOutOfInbox()
                    } label: {
                        Label("Перенести в страницы", systemImage: "folder")
                    }
                }
                Button {
                    isMovingToFolder = true
                } label: {
                    Label("Переместить в папку…", systemImage: "arrow.right.doc.on.clipboard")
                }
                Button {
                    duplicatePage()
                } label: {
                    Label("Дублировать", systemImage: "plus.square.on.square")
                }
                Button {
                    copyLink(.page(model.pageId))
                } label: {
                    Label("Скопировать ссылку", systemImage: "link")
                }
                if model.page?.isNotebook != true {
                    Button {
                        isShowingHistory = true
                    } label: {
                        Label("История версий…", systemImage: "clock.arrow.circlepath")
                    }
                }
                if model.page?.isNotebook != true {
                    Button {
                        Task { await model.saveAsTemplate() }
                    } label: {
                        Label("Сохранить как шаблон", systemImage: "square.on.square.dashed")
                    }
                }
                PageExportButtons(request: $exportRequest)
                Toggle("Звуки", isOn: $soundsEnabled)
                Divider()
                Button(role: .destructive) {
                    Task {
                        await model.trash()
                        onClose()
                    }
                } label: {
                    Label("Удалить страницу", systemImage: "trash")
                }
            } label: {
                Label("Ещё", systemImage: "ellipsis.circle")
            }
        }
        ToolbarItem {
            Button {
                setSubpagesPanel(!showsSubpages)
            } label: {
                Label("Подстраницы", systemImage: "sidebar.right")
            }
            .help(model.subpages.isEmpty ? "Подстраницы" : "Подстраницы: \(model.subpages.count)")
        }
    }

    /// Копия страницы рядом с оригиналом. Сначала записываются несохранённые правки,
    /// чтобы копия была точной, потом копия открывается.
    private func duplicatePage() {
        let database = model.database
        let pageId = model.pageId
        Task {
            await model.flush()
            if let copy = await NoticeCenter.shared.perform("Не удалось сделать копию страницы", {
                try await database.duplicatePage(pageId)
            }) {
                LumenSounds.play(.create)
                onOpenPage(copy.id)
            }
        }
    }

    #if os(macOS)
    /// Клавиши, которые текстовое поле на Mac обрабатывает само, до SwiftUI они не доходят.
    /// Поэтому нажатие перехватывается раньше поля, пока курсор стоит в блоке:
    /// Backspace в пустом блоке удаляет его, Return в блоке кода переносит строку.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let model = model
        let windowBox = windowBox
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            let keyCode = event.keyCode
            let eventWindow = event.window
            // Выделение блоков: свои клавиши, но только в окне редактора и без листа поверх.
            let handledSelection = MainActor.assumeIsolated { () -> Bool in
                guard let window = windowBox.window, eventWindow === window, window.attachedSheet == nil else { return false }
                let textView = window.firstResponder as? NSTextView
                if model.hasBlockSelection, textView?.isEditable != true {
                    return BlockSelectionKeys.handleSelection(model, keyCode: keyCode, flags: flags)
                }
                if let textView, textView.isEditable {
                    return BlockSelectionKeys.handleText(model, textView: textView, keyCode: keyCode, flags: flags)
                }
                return false
            }
            if handledSelection { return nil }
            let plain = flags.isEmpty
            let isBackspace = plain && event.keyCode == 51
            let isReturn = plain && (event.keyCode == 36 || event.keyCode == 76)
            guard isBackspace || isReturn else { return event }
            let handled = MainActor.assumeIsolated {
                guard let id = model.focusedBlockId else { return false }
                if isBackspace {
                    return model.backspaceInEmptyBlock(id)
                }
                // Перевод строки вставляет само поле там, где стоит курсор. Второй Return
                // на пустой последней строке модель превращает в выход из блока кода.
                guard model.findBlock(id)?.type == .code,
                      let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
                      !textView.hasMarkedText() else { return false }
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            return handled ? nil : event
        }
    }

    /// ⇧-щелчок по другому блоку, когда курсор в тексте или блоки уже выделены: выделяется
    /// диапазон блоков, как в Notion. Поле ввода сам щелчок не увидит.
    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        let model = model
        let windowBox = windowBox
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            guard flags == .shift else { return event }
            let eventWindow = event.window
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let window = windowBox.window, eventWindow === window, window.attachedSheet == nil,
                      let hovered = model.hoveredBlockId, model.findBlock(hovered) != nil else { return false }
                guard model.hasBlockSelection || (model.focusedBlockId != nil && model.focusedBlockId != hovered) else {
                    return false
                }
                model.clickHandle(hovered, extend: true, toggle: false)
                return true
            }
            return handled ? nil : event
        }
    }
    #endif

    /// Переводит курсор в блок. Новый блок после Return появляется в ленивом списке не сразу,
    /// а поле, в котором нажали Return, на macOS ещё успевает забрать фокус обратно.
    /// Поэтому фокус ставится сразу и повторяется в следующих кадрах, пока не закрепится.
    private func moveFocus(to target: EditorFocus) {
        focus = target
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            for delay in [16, 50, 120, 250] {
                try? await Task.sleep(for: .milliseconds(delay))
                // Следующий Return уже запросил другой блок: этот запрос устарел.
                if Task.isCancelled { return }
                if focus != target {
                    focus = target
                } else {
                    placeCaretAtEnd()
                }
            }
        }
    }

    private func setSubpagesPanel(_ isOpen: Bool) {
        guard isOpen != showsSubpages else { return }
        LumenSounds.play(isOpen ? .panelOpen : .panelClose)
        withAnimation(LumenMotion.standard) {
            showsSubpages = isOpen
        }
        remembersSubpages = isOpen
    }

    /// Узкий экран iPhone: поля меньше, отмена и повтор над клавиатурой.
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// На узком iPhone карта заняла бы поля текста, там её нет.
    private var showsOutline: Bool {
        #if os(iOS)
        horizontalSizeClass != .compact
        #else
        true
        #endif
    }

    /// Поле на Mac, получив фокус, выделяет весь свой текст. Курсор ставится в конец, как в Notion.
    private func placeCaretAtEnd() {
        #if os(macOS)
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        #endif
    }

    /// Листы заметки: на первом заголовок, под последним «Добавить лист», ниже обратные ссылки.
    private var content: some View {
        let sheets = model.sheets
        let lastFull = sheets.last.map { model.fillShare(of: $0) >= NoteSheets.fullShare } ?? false
        return LazyVStack(alignment: .leading, spacing: isCompact ? 16 : 28) {
            ForEach(sheets, id: \.index) { sheet in
                sheetView(sheet, count: sheets.count)
                    .id(sheetAnchor(sheet))
            }
            AddSheetBar(sheetCount: sheets.count, isLastFull: lastFull) { model.addSheet() }
            Color.clear
                .frame(height: model.links.backlinks.isEmpty ? 120 : 30)
                .contentShape(Rectangle())
                .onTapGesture { model.focusEnd() }
            if !model.links.backlinks.isEmpty {
                backlinks
            }
        }
        .scrollTargetLayout()
        .floatingFormatBar(model: model)
        .padding(.horizontal, isCompact ? 8 : 24)
        .padding(.vertical, isCompact ? 12 : 24)
        .frame(maxWidth: CGFloat(NoteSheets.width) + (isCompact ? 16 : 48), alignment: .leading)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .modifier(BlockMarqueeSelection(model: model) { focus = nil })
        #else
        .coordinateSpace(.named(EditorSpace.blocks))
        #endif
    }

    /// Один лист: шапка на первом, блоки, просьба разложить лишнее, если текст не поместился.
    private func sheetView(_ sheet: NoteSheets.Sheet, count: Int) -> some View {
        let share = model.fillShare(of: sheet)
        let overflows = model.overflowIndex(of: sheet) != nil
        return SheetPaper(
            number: sheet.index + 1,
            title: displayTitle,
            isPinned: model.pinnedSheet == sheet.index,
            isFull: share >= NoteSheets.fullShare && !overflows,
            isCompact: isCompact
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if sheet.isFirst {
                    header
                        .padding(.bottom, 12)
                }
                ForEach(sheet.blocks) { block in
                    BlockTree(block: block, depth: 0, model: model, focus: $focus)
                        .id(block.id)
                }
                if sheet.isFirst, model.isBlankPage {
                    TemplateSuggestions(model: model)
                }
                if sheet.blocks.isEmpty {
                    Button {
                        model.startWriting(on: sheet)
                    } label: {
                        Text("Чистый лист: нажмите, чтобы писать")
                            .font(.callout)
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if overflows {
                    overflowNotice(sheet)
                }
            }
        } menu: {
            sheetMenu(sheet.index, count: count)
        }
    }

    /// Текст не поместился на лист: лишнее можно разложить по новым листам одной кнопкой.
    private func overflowNotice(_ sheet: NoteSheets.Sheet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(theme.accent)
            Text("Текст не помещается на лист")
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 8)
            Button {
                LumenSounds.play(.arrange)
                model.paginateAll()
            } label: {
                Text("Разложить по листам")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.accent.opacity(0.16), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Лишнее с каждого листа переедет на новые листы сразу за ним")
            .accessibilityIdentifier("paginate-sheets")
        }
        .padding(12)
        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 10)
    }

    @ViewBuilder
    private func sheetMenu(_ index: Int, count: Int) -> some View {
        if model.pinnedSheet == index {
            Button("Открепить от полки", systemImage: "pin.slash") { model.pinSheet(nil) }
        } else {
            Button("Приколоть к полке", systemImage: "pin") {
                LumenSounds.play(.pin)
                model.pinSheet(index)
            }
        }
        Divider()
        Button("Переместить выше", systemImage: "arrow.up") { model.moveSheet(index, by: -1) }
            .disabled(index == 0)
        Button("Переместить ниже", systemImage: "arrow.down") { model.moveSheet(index, by: 1) }
            .disabled(index >= count - 1)
        Button("Соединить с листом выше", systemImage: "arrow.up.and.down.text.horizontal") {
            model.mergeSheetWithPrevious(index)
        }
        .disabled(index == 0)
        Divider()
        Button("Удалить лист", systemImage: "trash", role: .destructive) {
            LumenSounds.play(.trash)
            model.deleteSheet(index)
        }
        .disabled(count < 2)
    }

    /// Якорь листа для прокрутки: граница листа, у первого листа id страницы.
    private func sheetAnchor(_ sheet: NoteSheets.Sheet) -> UUID {
        model.sheetAnchor(sheet)
    }

    private func scrollToSheet(_ index: Int, proxy: ScrollViewProxy) {
        let sheets = model.sheets
        guard sheets.indices.contains(index) else { return }
        LumenSounds.play(.navigate)
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(sheetAnchor(sheets[index]), anchor: .top)
        }
    }

    /// Миниатюры листов слева: на широком экране, когда листов больше одного и рядом с листом есть место.
    private var showsSheetRail: Bool {
        !isEmbedded && !isCompact && model.sheetCount > 1 && hasRoomForRail
    }

    /// С какой ширины редактора рядом с листом помещаются миниатюры.
    private static let railMinWidth = CGFloat(NoteSheets.width) + 48 + 2 * 110

    private var displayTitle: String {
        let trimmed = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isEmbedded, let source = model.notesSource {
                Button {
                    LumenSounds.play(.navigate)
                    model.openSource(source.id)
                } label: {
                    Label {
                        Text("Заметки к «\(source.displayTitle)» · открыть рядом с книгой").lineLimit(1)
                    } icon: {
                        Image(systemName: "book.pages")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .keyHint("Открыть книгу") {
                    LumenSounds.play(.navigate)
                    model.openSource(source.id)
                }
            }
            if !isEmbedded, showsBreadcrumbs {
                PageBreadcrumbs(database: model.database, pageId: model.pageId) { model.open($0) }
            }
            HStack(spacing: 8) {
                Button {
                    isPickingIcon = true
                } label: {
                    if let icon = model.page?.icon, !icon.isEmpty {
                        Text(icon).font(.system(size: 44))
                    } else {
                        Label("Иконка", systemImage: "face.smiling")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Значок заметки: любой эмодзи")
                .keyHint("Значок") { isPickingIcon = true }
                .popover(isPresented: $isPickingIcon) {
                    IconPicker(current: model.page?.icon) { icon in
                        model.setIcon(icon)
                        isPickingIcon = false
                    }
                    .presentationCompactAdaptation(.popover)
                }

                coverMenu

                Button {
                    isEditingBackground = true
                } label: {
                    Label("Фон", systemImage: "mountain.2")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Фон страницы: обои из слоёв гор или своё фото")
                .keyHint("Фон") { isEditingBackground = true }

                if model.page?.inInbox == true {
                    Button {
                        model.moveOutOfInbox()
                    } label: {
                        Label("Во входящих", systemImage: "tray")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(theme.accent.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                    .help("Перенести в страницы")
                    .keyHint("Перенести в страницы") { model.moveOutOfInbox() }
                }
                Spacer(minLength: 8)
                SaveStatusLabel(hasUnsavedChanges: model.hasUnsavedChanges)
            }

            TextField(
                "Без названия",
                text: Binding(get: { model.title }, set: { model.setTitle($0) }),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(theme.textPrimary)
            .focused($focus, equals: .title)
            .onSubmit { model.focusFirstBlock() }
            .keyHint("Заголовок") { focus = .title }

            // Строка базы данных: статус, срок и другие свойства над текстом.
            if let page = model.page, page.isDatabaseRow {
                RowPropertiesPanel(database: model.database, rowId: page.id) { model.open($0) }
                Divider()
            }
        }
    }

    private var coverMenu: some View {
        Menu {
            Menu {
                ForEach(WallpaperPalette.all) { palette in
                    Button(palette.name) { setMountainCover(palette: palette.id, isFaceted: false) }
                }
            } label: {
                Label("Горы", systemImage: "mountain.2")
            }
            Menu {
                ForEach(WallpaperPalette.all) { palette in
                    Button(palette.name) { setMountainCover(palette: palette.id, isFaceted: true) }
                }
            } label: {
                Label("Гранёные горы", systemImage: "triangle")
            }
            if case .wallpaper(var wallpaper) = model.page?.pageCover {
                Button {
                    wallpaper.seed = Int.random(in: 0..<100_000)
                    model.setCover(.wallpaper(wallpaper))
                } label: {
                    Label("Другие горы", systemImage: "shuffle")
                }
            }
            Divider()
            ForEach(Array(Self.coverGradients.enumerated()), id: \.offset) { index, name in
                Button(name) { model.setCover(.gradient(index)) }
            }
            Divider()
            Button {
                photoTarget = .cover
                isPickingPhoto = true
            } label: {
                Label("Фото…", systemImage: "photo")
            }
            if model.page?.cover != nil {
                Divider()
                Button("Убрать обложку", role: .destructive) { model.setCover(nil) }
            }
        } label: {
            Label("Обложка", systemImage: "photo.artframe")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

    /// Горная обложка в выбранной палитре. Если горы уже стоят, их форма сохраняется.
    private func setMountainCover(palette: Int, isFaceted: Bool) {
        var wallpaper: Wallpaper
        if case .wallpaper(let current) = model.page?.pageCover {
            wallpaper = current
        } else {
            wallpaper = Wallpaper(layers: 4, seed: Int.random(in: 0..<100_000))
        }
        wallpaper.palette = palette
        wallpaper.isFaceted = isFaceted
        model.setCover(.wallpaper(wallpaper))
    }

    /// Обратные ссылки: страницы, в которых есть ссылка на эту.
    private var backlinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ссылки на эту страницу", systemImage: "arrow.turn.down.left")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            ForEach(model.links.backlinks) { page in
                Button {
                    model.open(page.id)
                } label: {
                    PageLabel(page: page)
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .lumenCard(padding: 14)
        .padding(.bottom, 40)
    }
}

/// Название страницы в панели окна. Встроенный редактор его не ставит: название там у экрана вокруг.
private struct EditorNavigationTitle: ViewModifier {
    let title: String
    let isEnabled: Bool

    /// Заголовок ставит невидимый вид позади экрана, а не сам экран. Если бы экран попадал
    /// в одну из двух веток `if`, то при переходе в другую половину разделённого окна SwiftUI
    /// создавал бы его заново: сбрасывались бы инструмент тетради, выделение и прокрутка.
    func body(content: Content) -> some View {
        content.background {
            if isEnabled {
                Color.clear
                    .navigationTitle(title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
        }
    }
}

// MARK: - Отмена и повтор в меню

private struct PageEditorKey: FocusedValueKey {
    typealias Value = PageEditorModel
}

extension FocusedValues {
    /// Редактор в активном окне: к нему обращаются ⌘Z и ⇧⌘Z из меню.
    var pageEditor: PageEditorModel? {
        get { self[PageEditorKey.self] }
        set { self[PageEditorKey.self] = newValue }
    }
}

/// Команды «Отменить» и «Повторить» для открытой страницы. Заменяют стандартные пункты меню
/// «Правка», чтобы ⌘Z отменял и правки текста, и действия с блоками одной историей.
public struct EditorCommands: Commands {
    @FocusedValue(\.pageEditor) private var editor

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Отменить") { editor?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(editor?.canUndo != true)
            Button("Повторить") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editor?.canRedo != true)
        }
    }
}

/// Какие листы сейчас на экране (по якорю листа). Читают только карта заголовков и миниатюры.
@MainActor
@Observable
final class SheetVisibility {
    var ids: [UUID] = []
}

extension PageEditorModel {
    /// Якорь листа для прокрутки: граница листа, у первого листа id страницы.
    func sheetAnchor(_ sheet: NoteSheets.Sheet) -> UUID {
        sheet.breakId ?? pageId
    }
}

/// Миниатюры листов слева. Номер видного листа читается здесь, а не в редакторе:
/// при листании пересчитывается только колонка миниатюр.
private struct LiveSheetRail: View {
    let model: PageEditorModel
    var onSelect: (Int) -> Void
    var onAdd: () -> Void
    var onDelete: (Int) -> Void

    var body: some View {
        SheetRail(
            count: model.sheetCount,
            current: model.visibleSheet,
            pinned: model.pinnedSheet,
            onSelect: onSelect,
            onAdd: onAdd,
            onDelete: onDelete
        )
    }
}

/// Счётчик слов: слова считаются здесь, а не при каждой сборке редактора.
private struct LiveWordCount: View {
    let model: PageEditorModel
    let isFocusMode: Bool
    var onToggleFocus: () -> Void
    var timerEnd: Date?
    var onStartTimer: () -> Void
    var onStopTimer: () -> Void

    var body: some View {
        WordCountCapsule(
            words: model.wordCount,
            isFocusMode: isFocusMode,
            onToggleFocus: onToggleFocus,
            timerEnd: timerEnd,
            onStartTimer: onStartTimer,
            onStopTimer: onStopTimer
        )
    }
}

/// Карта заголовков справа. Какой заголовок подсветить, зависит от листов на экране,
/// поэтому это считается здесь: при листании пересчитывается только карта.
private struct LiveOutline: View {
    let model: PageEditorModel
    let visibility: SheetVisibility
    var onSelect: (OutlineItem) -> Void

    var body: some View {
        let outline = model.outline
        if outline.count >= 2 {
            PageOutlineView(items: outline, currentId: currentHeadingId(in: outline), onSelect: onSelect)
        }
    }

    /// Заголовок, в разделе которого сейчас верх экрана: последний, что начинается не ниже
    /// начала первого видного листа. Пока виден текст до первого заголовка, не подсвечен ни один.
    private func currentHeadingId(in outline: [OutlineItem]) -> UUID? {
        let topLevel = model.children(of: nil).map(\.id)
        let sheets = model.sheets
        let visible = visibility.ids.compactMap { id in sheets.firstIndex { model.sheetAnchor($0) == id } }
        guard let first = visible.min() else { return nil }
        // Первый блок видного листа; у пустого листа его граница.
        guard let start = sheets[first].blocks.first?.id ?? sheets[first].breakId,
              let startIndex = topLevel.firstIndex(of: start) else { return nil }
        return outline.last { item in
            (topLevel.firstIndex(of: item.anchorId) ?? .max) <= startIndex
        }?.id
    }
}

/// Насколько прокручена страница. Его читают только фон и обложка ниже.
@MainActor
@Observable
final class PageScrollOffset {
    var offset: CGFloat = 0
}

/// Фон страницы, на котором солнце садится по мере прокрутки.
private struct ScrolledPageBackground: View {
    let scroll: PageScrollOffset
    let background: PageBackground?
    let attachments: AttachmentStore

    var body: some View {
        // Без обоев прокрутка фону не нужна: не читаем её, и фон не перерисовывается.
        PageBackgroundView(
            background: background,
            attachments: attachments,
            sunset: background == nil ? 0 : scroll.offset / 700
        )
    }
}

/// Обложка страницы: горы на ней тоже темнеют при прокрутке.
private struct ScrolledPageCover: View {
    let scroll: PageScrollOffset
    let cover: PageCover
    let attachments: AttachmentStore

    var body: some View {
        PageCoverView(cover: cover, attachments: attachments, sunset: scroll.offset / 220)
    }
}
