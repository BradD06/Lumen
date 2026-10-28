import LumenCore
import LumenThemes
import SwiftUI

/// Блок вместе с вложенными блоками. Ряд колонок рисуется отдельно, колонки стоят рядом.
struct BlockTree: View {
    let block: Block
    let depth: Int
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if block.type == .columnList {
            ColumnsView(row: block, depth: depth, model: model, focus: focus)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                BlockRow(
                    block: block,
                    number: block.type == .numberedList ? model.listNumber(for: block.id) : 1,
                    depth: depth,
                    model: model,
                    focus: focus
                )
                if showsChildren {
                    let children = model.children(of: block.id)
                    if !children.isEmpty || block.type == .toggle {
                        VStack(alignment: .leading, spacing: 6) {
                            if children.isEmpty {
                                emptyTogglePlaceholder
                            }
                            ForEach(children) { child in
                                BlockTree(block: child, depth: depth + 1, model: model, focus: focus)
                            }
                        }
                        .padding(.leading, 26)
                    }
                }
            }
        }
    }

    private var showsChildren: Bool {
        block.type != .toggle || !block.content.isCollapsed
    }

    private var emptyTogglePlaceholder: some View {
        Button {
            model.addFirstChild(to: block.id)
        } label: {
            Text("Пусто. Нажмите, чтобы добавить блок внутрь")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .padding(.leading, 22)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

/// Ряд колонок. На узком экране iPhone колонки встают друг под другом.
struct ColumnsView: View {
    let row: Block
    let depth: Int
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        let layout = isCompact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
        layout {
            ForEach(model.children(of: row.id)) { column in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.children(of: column.id)) { child in
                        BlockTree(block: child, depth: depth, model: model, focus: focus)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}
