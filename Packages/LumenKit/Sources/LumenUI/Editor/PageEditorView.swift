import LumenCore
import LumenStorage
import LumenThemes
import PhotosUI
import SwiftUI
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
    @State private var focusTask: Task<Void, Never>?
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif
    /// Насколько прокручена страница: по ней солнце на горах опускается за гряды.
    @State private var scrollOffset: CGFloat = 0
    /// Открыта ли панель подстраниц справа. Запоминается между страницами и запусками,
    /// а анимируется копия в `showsSubpages`: изменение `@AppStorage` анимацию не несёт.
    @AppStorage("editor.subpagesPanel") private var remembersSubpages = false
    @State private var showsSubpages = false
    @AppStorage(LumenSounds.enabledKey) private var soundsEnabled = true
    /// Блоки верхнего уровня, видные на экране: по ним подсвечивается заголовок на карте.
    @State private var visibleBlockIds: [UUID] = []
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme

    private static let icons = ["📝", "📘", "📚", "🎓", "💡", "✅", "🧠", "🌅", "🗂️", "⭐️"]
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Обложка на всю ширину окна, от края до края, как в Notion.
                    if let cover = model.page?.pageCover {
                        PageCoverView(cover: cover, attachments: model.database.attachments, sunset: scrollOffset / 220)
                    }
                    content
                }
            }
            .onScrollTargetVisibilityChange(idType: UUID.self) { ids in
                visibleBlockIds = ids
            }
            .overlay(alignment: .trailing) {
                let outline = model.outline
                if showsOutline, !showsSubpages, outline.count >= 2 {
                    PageOutlineView(items: outline, currentId: currentHeadingId(in: outline)) { item in
                        LumenSounds.play(.navigate)
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(item.anchorId, anchor: .top)
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = max(offset, 0)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            PageBackgroundView(
                background: model.page?.pageBackground,
                attachments: model.database.attachments,
                sunset: scrollOffset / 700
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
                    Spacer()
                    // На iPhone в панели окна места нет: отмена и повтор над клавиатурой.
                    if isCompact && !isEmbedded {
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
        .onAppear { showsSubpages = remembersSubpages && !isEmbedded }
        .task {
            await model.load()
            if model.title.isEmpty {
                focus = .title
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
            moveFocus(to: request)
        }
        .onChange(of: model.focusTitleRequest) { _, requested in
            guard requested else { return }
            model.focusTitleRequest = false
            focus = .title
        }
        .onChange(of: focus) { _, newFocus in
            if case .block(let id) = newFocus {
                model.focusedBlockId = id
            } else {
                model.focusedBlockId = nil
            }
        }
        #if os(macOS)
        .onAppear { installKeyMonitor() }
        #else
        .onAppear { EmptyBackspace.install() }
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
            #endif
            Task { await model.flush() }
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
                // Заметки к книге живут рядом с книгой, в папку их не кладут.
                if let page = model.page, page.sourceId == nil {
                    Button {
                        isMovingToFolder = true
                    } label: {
                        Label("Переместить в папку…", systemImage: "arrow.right.doc.on.clipboard")
                    }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let plain = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function]).isEmpty
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
    #endif

    /// Переводит курсор в блок. Новый блок после Return появляется в ленивом списке не сразу,
    /// а поле, в котором нажали Return, на macOS ещё успевает забрать фокус обратно.
    /// Поэтому фокус ставится сразу и повторяется в следующих кадрах, пока не закрепится.
    private func moveFocus(to id: UUID) {
        let target = EditorFocus.block(id)
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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
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

    /// Заголовок, в разделе которого сейчас верх экрана: последний, что начинается не ниже
    /// первого видного блока. Пока виден текст до первого заголовка, не подсвечен ни один.
    private func currentHeadingId(in outline: [OutlineItem]) -> UUID? {
        let topLevel = model.children(of: nil).map(\.id)
        let visible = visibleBlockIds.compactMap { topLevel.firstIndex(of: $0) }
        guard let first = visible.min() else { return nil }
        return outline.last { item in
            (topLevel.firstIndex(of: item.anchorId) ?? .max) <= first
        }?.id
    }

    /// Поле на Mac, получив фокус, выделяет весь свой текст. Курсор ставится в конец, как в Notion.
    private func placeCaretAtEnd() {
        #if os(macOS)
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        #endif
    }

    /// Колонка с текстом страницы: заголовок, блоки и обратные ссылки.
    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            header
                .padding(.bottom, 12)
            ForEach(model.children(of: nil)) { block in
                BlockTree(block: block, depth: 0, model: model, focus: $focus)
                    .id(block.id)
            }
            Color.clear
                .frame(height: model.links.backlinks.isEmpty ? 200 : 60)
                .contentShape(Rectangle())
                .onTapGesture { model.focusEnd() }
            if !model.links.backlinks.isEmpty {
                backlinks
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, isCompact ? 16 : 28)
        .padding(.vertical, isCompact ? 16 : 24)
        .frame(maxWidth: 780, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

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
            }
            if let parent = model.parentPage {
                Button {
                    model.open(parent.id)
                } label: {
                    Label {
                        Text(parent.displayTitle).lineLimit(1)
                    } icon: {
                        Image(systemName: "arrow.turn.left.up")
                    }
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Открыть страницу, в которую вложена эта")
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(Self.icons, id: \.self) { icon in
                        Button(icon) { model.setIcon(icon) }
                    }
                    if model.page?.icon != nil {
                        Divider()
                        Button("Убрать иконку", role: .destructive) { model.setIcon(nil) }
                    }
                } label: {
                    if let icon = model.page?.icon, !icon.isEmpty {
                        Text(icon).font(.system(size: 44))
                    } else {
                        Label("Иконка", systemImage: "face.smiling")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()

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
                }
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

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } else {
            content
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
