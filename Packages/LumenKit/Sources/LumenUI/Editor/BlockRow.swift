import LumenCore
import LumenThemes
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Один блок страницы: ручка для перетаскивания, маркер (точка, номер, чекбокс) и содержимое.
struct BlockRow: View {
    let block: Block
    let number: Int
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding

    @State private var isHovered = false
    @State private var isDropTarget = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            dragHandle
            VStack(alignment: .leading, spacing: 6) {
                content
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
        .overlay(alignment: .top) {
            if isDropTarget {
                Capsule()
                    .fill(theme.accent)
                    .frame(height: 3)
                    .offset(y: -3)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .dropDestination(for: BlockDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            model.moveBlock(item.blockId, onto: block.id)
            return true
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            if block.type.isConvertible {
                Menu("Превратить в") {
                    ForEach(BlockType.allCases.filter(\.isConvertible)) { type in
                        Button {
                            model.setType(block.id, type)
                        } label: {
                            Label(type.title, systemImage: type.symbolName)
                        }
                    }
                }
            }
            Button {
                model.moveBlock(block.id, by: -1)
            } label: {
                Label("Переместить вверх", systemImage: "arrow.up")
            }
            Button {
                model.moveBlock(block.id, by: 1)
            } label: {
                Label("Переместить вниз", systemImage: "arrow.down")
            }
            Divider()
            Button(role: .destructive) {
                model.deleteBlock(block.id)
            } label: {
                Label("Удалить блок", systemImage: "trash")
            }
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
            .frame(width: 18, height: 24)
            .contentShape(Rectangle())
            .opacity(handleOpacity)
            .draggable(BlockDragItem(blockId: block.id)) {
                Label(dragTitle, systemImage: block.type.symbolName)
                    .padding(8)
                    .lumenCard(padding: 4)
            }
            .help("Перетащите, чтобы переместить блок")
            .accessibilityHidden(true)
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
                Text("•")
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
            field
                .padding(12)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .page:
            PageLinkBlock(page: model.linkedPage(block.content.pageId)) {
                if let pageId = block.content.pageId {
                    model.open(pageId)
                }
            }

        case .image:
            ImageBlock(block: block, model: model)

        case .paragraph, .heading1, .heading2, .heading3:
            field
        }
    }

    private var field: some View {
        TextField(
            placeholder,
            text: Binding(get: { block.text }, set: { model.updateText(block.id, to: $0) }),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(font)
        .foregroundStyle(theme.textPrimary)
        .focused(focus, equals: .block(block.id))
        .onSubmit { model.submit(block.id) }
        .onKeyPress(.delete) {
            model.backspaceInEmptyBlock(block.id) ? .handled : .ignored
        }
        // ⌥⌘↑ и ⌥⌘↓ двигают блок, как в Notion.
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.command), press.modifiers.contains(.option) else { return .ignored }
            model.moveBlock(block.id, by: press.key == .upArrow ? -1 : 1)
            return .handled
        }
    }

    private var placeholder: String {
        switch block.type {
        case .paragraph: isFocused ? "Пишите, / для команд, [[ для ссылки" : ""
        case .heading1: "Заголовок 1"
        case .heading2: "Заголовок 2"
        case .heading3: "Заголовок 3"
        case .bulletedList, .numberedList: "Пункт списка"
        case .todo: "Задача"
        case .quote: "Цитата"
        case .callout: "Выноска"
        case .code: "Код"
        case .divider, .page, .image: ""
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

/// Блок-ссылка на другую страницу или подстраницу.
private struct PageLinkBlock: View {
    let page: Page?
    var onOpen: () -> Void

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
        BlockType.allCases.filter { $0.matches(query) }
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
