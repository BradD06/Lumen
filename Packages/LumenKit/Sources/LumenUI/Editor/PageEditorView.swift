import LumenCore
import LumenStorage
import LumenThemes
import PhotosUI
import SwiftUI

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
    @State private var isPickingCover = false
    @State private var coverPhoto: PhotosPickerItem?
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
            LazyVStack(alignment: .leading, spacing: 6) {
                header
                    .padding(.bottom, 12)
                ForEach(Array(model.blocks.enumerated()), id: \.element.id) { index, block in
                    BlockRow(
                        block: block,
                        number: model.listNumber(at: index),
                        model: model,
                        focus: $focus
                    )
                }
                Color.clear
                    .frame(height: model.links.backlinks.isEmpty ? 200 : 60)
                    .contentShape(Rectangle())
                    .onTapGesture { model.focusEnd() }
                if !model.links.backlinks.isEmpty {
                    backlinks
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ThemedBackground())
        .navigationTitle(model.isLoaded ? displayTitle : "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
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
        .photosPicker(isPresented: $isPickingCover, selection: $coverPhoto, matching: .images)
        .onChange(of: coverPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.setCoverImage(data: data)
                }
                coverPhoto = nil
            }
        }
        .onChange(of: model.focusRequest) { _, request in
            guard let request else { return }
            focus = .block(request)
            model.focusRequest = nil
        }
        .onDisappear {
            Task { await model.flush() }
        }
    }

    private var displayTitle: String {
        let trimmed = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover = model.page?.pageCover {
                PageCoverView(cover: cover, attachments: model.database.attachments)
                    .padding(.bottom, 6)
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
            ForEach(Array(Self.coverGradients.enumerated()), id: \.offset) { index, name in
                Button(name) { model.setCover(.gradient(index)) }
            }
            Divider()
            Button {
                isPickingCover = true
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
