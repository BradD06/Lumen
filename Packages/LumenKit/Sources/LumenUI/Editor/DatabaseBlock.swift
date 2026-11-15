import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

extension PageEditorModel {
    /// Новая база прямо на странице: она живёт подстраницей этой страницы, а блок её показывает.
    func createInlineDatabase(in id: UUID) async {
        do {
            let table = try await database.createDataTable(title: "Новая база", icon: "🗂️", parentId: pageId)
            attachDatabase(id, databasePageId: table.pageId)
        } catch {
            NoticeCenter.shared.report("Не удалось создать базу", error)
        }
    }

    /// Показать в блоке «Задачи». База задач заводится, если её ещё нет.
    func attachTasksDatabase(_ id: UUID) async {
        do {
            let table = try await database.tasksDataTable()
            attachDatabase(id, databasePageId: table.pageId)
        } catch {
            NoticeCenter.shared.report("Не удалось открыть задачи", error)
        }
    }

    /// Блок показывает базу со страницы `databasePageId`.
    func attachDatabase(_ id: UUID, databasePageId: UUID) {
        guard let block = findBlock(id), block.type == .database, block.content.pageId != databasePageId else { return }
        recordUndo()
        update(id) { $0.content.pageId = databasePageId }
    }
}

/// Блок «База данных»: таблица, доска, календарь или список из базы прямо на странице.
/// Пока база не выбрана, блок предлагает создать новую или показать существующую.
struct DatabaseBlock: View {
    let block: Block
    let model: PageEditorModel

    var body: some View {
        if let databasePageId = block.content.pageId {
            EmbeddedDataTable(database: model.database, pageId: databasePageId) { model.open($0) }
                .id(databasePageId)
        } else {
            DatabaseBlockPicker(block: block, model: model)
        }
    }
}

private struct EmbeddedDataTable: View {
    @State private var table: DataTableModel
    var onOpenPage: (UUID) -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.lumenTheme) private var theme

    init(database: AppDatabase, pageId: UUID, onOpenPage: @escaping (UUID) -> Void) {
        _table = State(initialValue: DataTableModel(database: database, pageId: pageId))
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        Group {
            if table.isLoaded, table.table == nil || table.page?.isTrashed == true {
                Label("База удалена", systemImage: "tablecells.badge.ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DataTableBody(
                    model: table,
                    isCompact: isCompact,
                    isEmbedded: true,
                    onOpenPage: onOpenPage,
                    onOpenFull: { onOpenPage(table.pageId) }
                )
            }
        }
        .lumenCard(padding: 14)
        .task { await table.observe() }
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }
}

/// Выбор базы для блока: новая, «Задачи» или любая из уже созданных.
private struct DatabaseBlockPicker: View {
    let block: Block
    let model: PageEditorModel

    @State private var databases: [Page] = []
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("База данных на странице", systemImage: BlockType.database.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 8) {
                Button {
                    LumenSounds.play(.create)
                    Task { await model.createInlineDatabase(in: block.id) }
                } label: {
                    Label("Новая база", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await model.attachTasksDatabase(block.id) }
                } label: {
                    Label("Задачи", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
                if !databases.isEmpty {
                    Menu {
                        ForEach(databases) { page in
                            Button {
                                model.attachDatabase(block.id, databasePageId: page.id)
                            } label: {
                                PageLabel(page: page)
                            }
                        }
                    } label: {
                        Label("Существующая", systemImage: "square.stack")
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
        }
        .lumenCard(padding: 14)
        .task {
            let reader = model.database.reader
            databases = (try? await reader.read { db in try DataTableListQuery.fetch(db) }) ?? []
        }
    }
}
