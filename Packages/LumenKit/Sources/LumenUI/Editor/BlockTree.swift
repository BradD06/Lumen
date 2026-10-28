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

/// Ряд колонок. Между колонками тонкий серый разделитель: потяните его, чтобы поменять ширину.
/// На узком экране iPhone колонки встают друг под другом.
struct ColumnsView: View {
    let row: Block
    let depth: Int
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding

    @State private var totalWidth: CGFloat = 0
    /// Ширины во время перетаскивания разделителя. В модель пишутся, когда разделитель отпустили.
    @State private var liveFractions: [Double]?
    @State private var dragStart: [Double]?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    static let dividerWidth: CGFloat = 16
    /// Отступ между блоками. Если следом идёт ещё один ряд колонок, разделитель дотягивается
    /// через этот отступ до разделителя следующего ряда, и линия не рвётся.
    static let blockSpacing: CGFloat = 6
    /// Самая узкая колонка, доля ширины ряда.
    static let minFraction = 0.12

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        let columns = model.children(of: row.id)
        if isCompact {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(columns) { column in
                    columnContent(column)
                }
            }
        } else {
            let fractions = liveFractions ?? model.columnFractions(row.id)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    columnContent(column)
                        .frame(width: width(of: index, fractions: fractions, count: columns.count), alignment: .topLeading)
                    if index < columns.count - 1 {
                        divider(after: index, count: columns.count)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { totalWidth = $0 }
        }
    }

    private func columnContent(_ column: Block) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.children(of: column.id)) { child in
                BlockTree(block: child, depth: depth, model: model, focus: focus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Сразу под этим рядом стоит ещё один ряд колонок.
    private var joinsNextRow: Bool {
        let siblings = model.children(of: row.parentBlockId)
        guard let index = siblings.firstIndex(where: { $0.id == row.id }), index + 1 < siblings.count else {
            return false
        }
        return siblings[index + 1].type == .columnList
    }

    private func available(count: Int) -> CGFloat {
        max(totalWidth - Self.dividerWidth * CGFloat(count - 1), 0)
    }

    /// Ширина колонки в точках. Пока ширина ряда неизвестна, колонки делят место поровну сами.
    private func width(of index: Int, fractions: [Double], count: Int) -> CGFloat? {
        guard totalWidth > 0, fractions.indices.contains(index) else { return nil }
        return available(count: count) * fractions[index]
    }

    private func divider(after index: Int, count: Int) -> some View {
        ColumnDivider()
            .frame(width: Self.dividerWidth)
            .frame(maxHeight: .infinity)
            .padding(.bottom, joinsNextRow ? -Self.blockSpacing : 0)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? model.columnFractions(row.id)
                        dragStart = start
                        let total = available(count: count)
                        guard total > 0, start.indices.contains(index + 1) else { return }
                        let pair = start[index] + start[index + 1]
                        let delta = Double(value.translation.width / total)
                        let left = min(max(start[index] + delta, Self.minFraction), pair - Self.minFraction)
                        var fractions = start
                        fractions[index] = left
                        fractions[index + 1] = pair - left
                        liveFractions = fractions
                    }
                    .onEnded { _ in
                        if let liveFractions {
                            model.setColumnFractions(row.id, liveFractions)
                        }
                        liveFractions = nil
                        dragStart = nil
                    }
            )
    }
}

/// Тонкая серая линия между колонками. На Mac при наведении курсор меняется на «потянуть в стороны».
private struct ColumnDivider: View {
    @State private var isHovered = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.textSecondary.opacity(isHovered ? 0.45 : 0.18))
            .frame(width: isHovered ? 2 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            #if os(macOS)
            .pointerStyle(.columnResize)
            #endif
            .accessibilityElement()
            .accessibilityLabel("Разделитель колонок")
            .accessibilityIdentifier("column-divider")
    }
}
