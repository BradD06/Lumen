import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

extension EnvironmentValues {
    /// Оригиналы синхронных блоков, внутри которых сейчас рисуется блок. Копия, что попала
    /// внутрь своего же оригинала, не рисует его снова, иначе вышла бы бесконечная матрёшка.
    @Entry var syncedChain: Set<UUID> = []
}

/// Рамка синхронного блока: оригинал и копии выглядят одинаково.
struct SyncedFrame: View {
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(theme.accent.opacity(0.55), lineWidth: 1.5)
            .padding(-6)
            .allowsHitTesting(false)
    }
}

/// Строка над содержимым оригинала: подпись и «Скопировать», чтобы вставить его на другую страницу.
struct SyncedOriginalHeader: View {
    let block: Block
    let model: PageEditorModel

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Label("Синхронный блок", systemImage: BlockType.synced.symbolName)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.accent)
            Spacer(minLength: 8)
            Button {
                model.copySyncedBlock(block.id)
            } label: {
                Label("Скопировать", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.textSecondary)
            .help("Вставьте на другой странице: правки будут видны в обоих местах")
            .keyHint("Скопировать синхронный блок") { model.copySyncedBlock(block.id) }
        }
        .frame(minHeight: 22)
    }
}

/// Копия синхронного блока: показывает и правит детей оригинала. Если оригинал на этой странице
/// или открыт в другой панели, правки идут через его редактор, иначе через свою модель страницы.
struct SyncedCopyView: View {
    let block: Block
    let model: PageEditorModel

    @State private var source: PageEditorModel?
    @State private var ownsSource = false
    @State private var isResolved = false
    @FocusState private var focus: EditorFocus?
    @Environment(\.syncedChain) private var chain
    @Environment(\.lumenTheme) private var theme

    private var reference: SyncedReference? { block.content.syncedFrom }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
        .padding(.vertical, 2)
        .overlay { SyncedFrame() }
        .task(id: reference) { await resolve() }
        .onChange(of: source?.focusRequest) { _, request in
            // Своя модель: её Return и вставки двигают курсор здесь. Чужим управляет её редактор.
            guard ownsSource, let request, let source else { return }
            source.focusRequest = nil
            focus = .block(request)
        }
        .onChange(of: focus) { _, newFocus in
            guard ownsSource, let source else { return }
            if case .block(let id) = newFocus {
                source.focusedBlockId = id
            } else {
                source.focusedBlockId = nil
            }
        }
        .onDisappear {
            guard ownsSource, let source else { return }
            Task { await source.flush() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(headerTitle, systemImage: BlockType.synced.symbolName)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let reference, reference.pageId != model.pageId {
                Button {
                    model.open(reference.pageId)
                } label: {
                    Label("Оригинал", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.textSecondary)
                .help("Открыть страницу, где лежит оригинал")
                .keyHint("Открыть оригинал") { model.open(reference.pageId) }
            }
        }
        .frame(minHeight: 22)
    }

    private var headerTitle: String {
        guard let source, source.pageId != model.pageId else { return "Синхронный блок" }
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Синхронный блок из «\(title.isEmpty ? "Без названия" : title)»"
    }

    @ViewBuilder
    private var content: some View {
        if let reference, chain.contains(reference.blockId) {
            notice("Копия стоит внутри своего же оригинала и не показывает его ещё раз.")
        } else if !isResolved {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 32)
        } else if let reference, let source, let original = source.findBlock(reference.blockId), original.isSyncedOriginal {
            let children = source.children(of: original.id)
            VStack(alignment: .leading, spacing: 6) {
                if children.isEmpty {
                    Button {
                        source.addFirstChild(to: original.id)
                    } label: {
                        Text("Пусто. Нажмите, чтобы добавить блок")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(children) { child in
                    BlockTree(block: child, depth: 0, model: source, focus: $focus)
                }
            }
            .environment(\.syncedChain, chain.union([original.id]))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                notice("Оригинал этого блока удалён или больше не синхронный.")
                Button(role: .destructive) {
                    model.deleteBlock(block.id)
                } label: {
                    Label("Убрать копию", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    /// Чей редактор правит оригинал: этой же страницы, открытой в другой панели или свой.
    private func resolve() async {
        guard var reference else { return }
        let pageId = await model.syncedSourcePage(reference)
        if pageId != reference.pageId {
            // Оригинал перенесли на другую страницу: копия запоминает, где он теперь.
            reference.pageId = pageId
            model.updateSyncedReference(block.id, to: reference)
            return
        }
        if reference.pageId == model.pageId {
            source = model
            ownsSource = false
        } else if let open = OpenPageEditors.shared.model(for: reference.pageId) {
            source = open
            ownsSource = false
        } else if source?.pageId != reference.pageId || !ownsSource {
            // Страницы оригинала нет: своя модель создала бы на ней пустой блок.
            guard (try? await model.database.page(reference.pageId)) != nil else {
                source = nil
                isResolved = true
                return
            }
            let loaded = PageEditorModel(database: model.database, pageId: reference.pageId)
            await loaded.load()
            source = loaded
            ownsSource = true
        }
        isResolved = true
    }
}
