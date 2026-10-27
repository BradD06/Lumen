import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

enum EditorFocus: Hashable {
    case title
    case block(UUID)
}

/// Редактор страницы. Первая простая версия по плану: каждый блок это отдельное текстовое поле
/// в ленивом стеке. Markdown-сокращения, slash-меню, Return и Backspace работают как в Notion.
struct PageEditorView: View {
    @State private var model: PageEditorModel
    var onClose: () -> Void

    @FocusState private var focus: EditorFocus?
    @Environment(\.lumenTheme) private var theme

    private static let icons = ["📝", "📘", "📚", "🎓", "💡", "✅", "🧠", "🌅", "🗂️", "⭐️"]

    init(database: AppDatabase, pageId: UUID, onClose: @escaping () -> Void) {
        _model = State(initialValue: PageEditorModel(database: database, pageId: pageId))
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
                    .frame(height: 200)
                    .contentShape(Rectangle())
                    .onTapGesture { model.focusEnd() }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ThemedBackground())
        .navigationTitle(model.page?.displayTitle ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
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
}
