import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// История версий страницы: список прошлых версий и как выглядела выбранная.
/// «Вернуть эту версию» откатывает страницу; текущий вид остаётся в истории и в отмене (⌘Z).
struct PageHistorySheet: View {
    let model: PageEditorModel
    let onDone: () -> Void

    @State private var versions: [PageVersionSummary] = []
    @State private var selectedId: UUID?
    @State private var preview: PageVersion?
    @State private var previewBlocks: [Block] = []
    @State private var isLoaded = false
    @State private var confirmsRestore = false
    @Environment(\.lumenTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if isLoaded, versions.isEmpty {
                    ContentUnavailableView(
                        "Прошлых версий пока нет",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Пока вы правите страницу, Lumen запоминает её каждые десять минут. Версии хранятся на этом устройстве.")
                    )
                } else if isCompact {
                    VStack(spacing: 0) {
                        versionList
                            .frame(maxHeight: 220)
                        Divider()
                        previewPane
                    }
                } else {
                    HStack(spacing: 0) {
                        versionList
                            .frame(width: 250)
                        Divider()
                        previewPane
                    }
                }
            }
            .background(ThemedBackground())
            .navigationTitle("История версий")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Вернуть эту версию") { confirmsRestore = true }
                        .disabled(preview == nil)
                }
            }
            .confirmationDialog("Вернуть страницу к этой версии?", isPresented: $confirmsRestore, titleVisibility: .visible) {
                Button("Вернуть") { restore() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Сегодняшний вид страницы останется в истории, а отмена (⌘Z) сразу вернёт его.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
        .keyHintHost()
        .task { await load() }
        .onChange(of: selectedId) { _, id in
            Task { await select(id) }
        }
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var versionList: some View {
        List {
            ForEach(versions) { version in
                Button {
                    selectedId = version.id
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.body.weight(.medium))
                            .foregroundStyle(version.id == selectedId ? theme.onAccent : theme.textPrimary)
                        Text("\(version.createdAt.lumenRelative) · \(BlockSelection.blocksCaption(version.blockCount))")
                            .font(.caption)
                            .foregroundStyle(version.id == selectedId ? theme.onAccent.opacity(0.8) : theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        version.id == selectedId ? theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .keyHint(version.createdAt.formatted(date: .omitted, time: .shortened)) { selectedId = version.id }
            }
        }
        .keyHintClip()
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var previewPane: some View {
        if let preview {
            VersionPreview(title: preview.title, blocks: previewBlocks)
                .id(preview.id)
        } else {
            Color.clear
        }
    }

    private func load() async {
        // Несохранённые правки сначала в базу, чтобы история показала и сегодняшний вид.
        await model.flush()
        versions = (try? await model.database.pageVersions(of: model.pageId)) ?? []
        isLoaded = true
        selectedId = versions.first?.id
    }

    private func select(_ id: UUID?) async {
        guard let id, let version = try? await model.database.pageVersion(id) else {
            preview = nil
            previewBlocks = []
            return
        }
        guard selectedId == id else { return }
        previewBlocks = (try? version.decodedBlocks()) ?? []
        preview = version
    }

    private func restore() {
        guard let preview else { return }
        let blocks = previewBlocks
        Task {
            await model.restoreVersion(title: preview.title, blocks: blocks)
            LumenSounds.play(.restore)
            onDone()
        }
    }
}

/// Страница из истории только для чтения: заголовки, списки, задачи и текст с оформлением,
/// остальное (картинки, таблицы, файлы) одной строкой.
struct VersionPreview: View {
    let title: String
    let blocks: [Block]

    @Environment(\.lumenTheme) private var theme

    private struct Row: Identifiable {
        let block: Block
        let depth: Int
        var id: UUID { block.id }
    }

    private var rows: [Row] {
        let children = Dictionary(grouping: blocks, by: \.parentBlockId).mapValues { siblings in
            siblings.sorted { ($0.sortKey, $0.id.uuidString) < ($1.sortKey, $1.id.uuidString) }
        }
        var result: [Row] = []
        func walk(_ parent: UUID?, depth: Int) {
            for block in children[parent] ?? [] where block.type != .column && block.type != .columnList {
                result.append(Row(block: block, depth: depth))
                walk(block.id, depth: depth + 1)
            }
            // Колонки показываются по очереди, их содержимое на том же уровне.
            for block in children[parent] ?? [] where block.type == .column || block.type == .columnList {
                walk(block.id, depth: depth)
            }
        }
        walk(nil, depth: 0)
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.isEmpty ? "Без названия" : title)
                    .font(.title2.bold())
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 6)
                ForEach(rows) { row in
                    line(row.block)
                        .padding(.leading, CGFloat(row.depth) * 20)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func line(_ block: Block) -> some View {
        let text = RichTextRendering.text(InlineMarkup.normalized(block.content.runs), linkColor: theme.accent, mathSize: 15)
        switch block.type {
        case .heading1:
            text.font(.title3.bold()).foregroundStyle(theme.textPrimary)
        case .heading2:
            text.font(.headline).foregroundStyle(theme.textPrimary)
        case .heading3:
            text.font(.subheadline.bold()).foregroundStyle(theme.textPrimary)
        case .tableOfContents:
            placeholder(block.type, detail: nil)
        case .bulletedList:
            marked("•", text)
        case .numberedList:
            marked("–", text)
        case .todo:
            marked(block.content.isChecked ? "☑︎" : "☐", text.strikethrough(block.content.isChecked))
        case .quote, .excerpt:
            text.italic().foregroundStyle(theme.textPrimary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Capsule().fill(theme.accent).frame(width: 3) }
        case .callout:
            marked("💡", text)
        case .code:
            Text(block.text).font(.callout.monospaced()).foregroundStyle(theme.textPrimary)
        case .equation:
            MathFormula(latex: block.text, fontSize: 17)
        case .toggle:
            marked("▸", text)
        case .divider, .sheetBreak:
            Divider()
        case .paragraph:
            text.foregroundStyle(theme.textPrimary)
        case .table:
            placeholder(block.type, detail: block.content.table.map { "\($0.rowCount) × \($0.columnCount)" })
        case .file, .pdf, .video, .audio:
            placeholder(block.type, detail: block.content.file?.name ?? block.content.bookmark.map { $0.title ?? $0.url })
        case .bookmark:
            placeholder(block.type, detail: block.content.bookmark.map { $0.title ?? $0.url })
        case .synced:
            // Содержимое оригинала стоит в истории его детьми, копия показывает чужую страницу.
            placeholder(block.type, detail: block.content.syncedFrom == nil ? nil : "копия")
        case .page, .database, .image, .drawing, .columnList, .column:
            placeholder(block.type, detail: nil)
        }
    }

    private func marked(_ mark: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(mark).foregroundStyle(theme.accent)
            text.foregroundStyle(theme.textPrimary)
        }
    }

    private func placeholder(_ type: BlockType, detail: String?) -> some View {
        Label(detail.map { "\(type.title): \($0)" } ?? type.title, systemImage: type.symbolName)
            .font(.subheadline)
            .foregroundStyle(theme.textSecondary)
    }
}
