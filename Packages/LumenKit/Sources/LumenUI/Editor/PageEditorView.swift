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
    var onOpenPage: (UUID) -> Void
    var onClose: () -> Void

    @FocusState private var focus: EditorFocus?
    /// Куда пойдёт фото из галереи: в обложку или в фон страницы.
    @State private var photoTarget: PhotoTarget = .cover
    @State private var isPickingPhoto = false
    /// Фото для фона выбирают после закрытия окна фона: два окна сразу показать нельзя.
    @State private var wantsBackgroundPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isEditingBackground = false
    @State private var focusTask: Task<Void, Never>?
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif
    /// Насколько прокручена страница: по ней солнце на горах опускается за гряды.
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.lumenTheme) private var theme

    private static let icons = ["📝", "📘", "📚", "🎓", "💡", "✅", "🧠", "🌅", "🗂️", "⭐️"]
    private static let coverGradients = ["Персик", "Солнце", "Лаванда", "Лайм", "Небо"]

    init(database: AppDatabase, pageId: UUID, onOpenPage: @escaping (UUID) -> Void, onClose: @escaping () -> Void) {
        _model = State(initialValue: PageEditorModel(database: database, pageId: pageId))
        self.onOpenPage = onOpenPage
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Обложка на всю ширину окна, от края до края, как в Notion.
                if let cover = model.page?.pageCover {
                    PageCoverView(cover: cover, attachments: model.database.attachments, sunset: scrollOffset / 220)
                }
                content
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
        .navigationTitle(model.isLoaded ? displayTitle : "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                }
            }
            #endif
            ToolbarItemGroup {
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
        }
        .task {
            await model.load()
            if model.title.isEmpty {
                focus = .title
            }
            await model.observeLinks()
        }
        .focusedSceneValue(\.pageEditor, model)
        .onChange(of: model.openRequest) { _, request in
            guard let request else { return }
            model.openRequest = nil
            onOpenPage(request)
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
            }
            Color.clear
                .frame(height: model.links.backlinks.isEmpty && model.subpages.isEmpty ? 200 : 60)
                .contentShape(Rectangle())
                .onTapGesture { model.focusEnd() }
            if !model.subpages.isEmpty {
                subpages
            }
            if !model.links.backlinks.isEmpty {
                backlinks
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 780, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var displayTitle: String {
        let trimmed = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
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

    /// Подстраницы: вложенные в эту страницу, с кнопкой для новой.
    private var subpages: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Подстраницы", systemImage: "doc.on.doc")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            ForEach(model.subpages) { page in
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
            Button {
                model.addSubpage()
            } label: {
                Label("Новая подстраница", systemImage: "plus")
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .lumenCard(padding: 14)
        .padding(.bottom, model.links.backlinks.isEmpty ? 40 : 8)
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
