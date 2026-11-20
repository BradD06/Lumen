import LumenCore
import LumenThemes
import SwiftUI

/// Простая таблица на странице. Tab переходит в следующую ячейку (после последней появляется
/// новая строка), Return в ячейку ниже, из последней строки под таблицу. Границу столбца
/// тянут, чтобы поменять ширину; строки и столбцы добавляют кнопками «+» и меню ячейки.
struct TableBlock: View {
    let block: Block
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding

    @State private var availableWidth: CGFloat = 0
    /// Ширины во время перетаскивания границы. В модель пишутся, когда границу отпустили.
    @State private var liveWidths: [Double]?
    @State private var dragStart: [Double]?
    @Environment(\.lumenTheme) private var theme

    /// Место справа под кнопку нового столбца.
    private static let addColumnWidth: CGFloat = 26

    private var table: TableData { block.content.table ?? .empty() }

    var body: some View {
        let table = table
        let widths = liveWidths ?? table.widths(available: Double(max(availableWidth - Self.addColumnWidth - 4, 0)))
        let total = CGFloat(widths.reduce(0, +))
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: total + Self.addColumnWidth > availableWidth + 1) {
                HStack(alignment: .top, spacing: 4) {
                    grid(table, widths: widths)
                    addColumnButton(table)
                }
                // Высота по содержимому: ячейки строки и кнопка столбца тянутся до самой высокой.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            addRowButton(table)
                .frame(width: min(total, max(availableWidth, 1)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Таблица")
    }

    private func grid(_ table: TableData, widths: [Double]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<table.rowCount, id: \.self) { row in
                GridRow {
                    ForEach(0..<table.columnCount, id: \.self) { column in
                        TableCellField(
                            block: block,
                            row: row,
                            column: column,
                            cell: table.cell(row, column),
                            isHeader: table.isHeader(row: row, column: column),
                            model: model,
                            focus: focus
                        )
                        .frame(width: CGFloat(widths.indices.contains(column) ? widths[column] : TableData.defaultColumnWidth))
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.textSecondary.opacity(0.3), lineWidth: 1))
        .overlay(alignment: .topLeading) { resizeHandles(widths) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    /// Границы столбцов, за которые меняют ширину. Лежат на линиях между ячейками,
    /// а не над полями ввода: на Mac поле забрало бы щелчок.
    private func resizeHandles(_ widths: [Double]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<widths.count, id: \.self) { index in
                let edge = widths.prefix(index + 1).reduce(0, +)
                TableColumnBorder()
                    .frame(width: 10)
                    .frame(maxHeight: .infinity)
                    .offset(x: CGFloat(edge) - 5)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? widths
                                dragStart = start
                                guard start.indices.contains(index) else { return }
                                var next = start
                                next[index] = min(
                                    max(start[index] + Double(value.translation.width), TableData.minColumnWidth),
                                    TableData.maxColumnWidth
                                )
                                liveWidths = next
                            }
                            .onEnded { _ in
                                if let liveWidths {
                                    model.setTableColumnWidths(block.id, liveWidths)
                                }
                                liveWidths = nil
                                dragStart = nil
                            }
                    )
                    .onTapGesture(count: 2) {
                        // Двойной щелчок по границе: столбцы снова ровные.
                        model.setTableColumnWidths(block.id, nil)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func addColumnButton(_ table: TableData) -> some View {
        Button {
            LumenSounds.play(.create)
            model.insertTableColumn(block.id, at: table.columnCount, focusRow: 0)
        } label: {
            Image(systemName: "plus")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: Self.addColumnWidth - 4)
                .frame(maxHeight: .infinity)
                .background(theme.textPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Добавить столбец справа")
        .accessibilityLabel("Добавить столбец")
    }

    private func addRowButton(_ table: TableData) -> some View {
        Button {
            LumenSounds.play(.create)
            model.insertTableRow(block.id, at: table.rowCount, focusColumn: 0)
        } label: {
            Label("Строка", systemImage: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(theme.textPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Добавить строку снизу. Или Tab в последней ячейке")
        .accessibilityLabel("Добавить строку")
    }
}

/// Одна ячейка: поле с разметкой, как у блока; вне фокуса поверх лежит оформленный текст.
private struct TableCellField: View {
    let block: Block
    let row: Int
    let column: Int
    let cell: TableCell
    let isHeader: Bool
    let model: PageEditorModel
    var focus: FocusState<EditorFocus?>.Binding

    /// Разметка, которую сейчас набирают: курсор не прыгает, пока ячейка в фокусе.
    @State private var editingSource: String?
    @Environment(\.lumenTheme) private var theme

    private var target: EditorFocus { .cell(block.id, row, column) }
    private var isFocused: Bool { focus.wrappedValue == target }

    private var showsRendered: Bool {
        !isFocused && InlineMarkup.hasFormatting(cell.runs)
    }

    private var font: Font {
        .system(size: 15, weight: isHeader ? .semibold : .regular)
    }

    var body: some View {
        TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(showsRendered ? Color.clear : theme.textPrimary)
            .focused(focus, equals: target)
            // Return на Mac приходит сюда, на iPhone переводом строки в тексте.
            .onSubmit { model.moveTableFocus(block.id, row: row, column: column, direction: .down) }
            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
                let back = press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}")
                model.moveTableFocus(block.id, row: row, column: column, direction: back ? .previous : .next)
                return .handled
            }
            .overlay(alignment: .topLeading) {
                if showsRendered {
                    RichTextRendering.text(InlineMarkup.normalized(cell.runs), linkColor: theme.accent, mathSize: 15)
                        .font(font)
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isHeader ? theme.textPrimary.opacity(0.07) : Color.clear)
            .overlay(Rectangle().stroke(theme.textSecondary.opacity(0.22), lineWidth: 0.5))
            .contentShape(Rectangle())
            // Нажатие на поля ячейки вокруг текста тоже ставит курсор в неё.
            .onTapGesture { focus.wrappedValue = target }
            .contextMenu { TableCellMenu(blockId: block.id, row: row, column: column, model: model) }
            .onChange(of: isFocused) { _, focused in
                if !focused { editingSource = nil }
            }
            .accessibilityLabel("Ячейка \(row + 1), \(column + 1)")
    }

    private var text: Binding<String> {
        Binding(
            get: { editingSource ?? InlineMarkup.source(cell.runs) },
            set: { value in
                if value.contains("\n") {
                    let cleaned = value.replacingOccurrences(of: "\n", with: "")
                    editingSource = cleaned
                    model.updateTableCell(block.id, row: row, column: column, source: cleaned)
                    model.moveTableFocus(block.id, row: row, column: column, direction: .down)
                    return
                }
                editingSource = value
                model.updateTableCell(block.id, row: row, column: column, source: value)
            }
        )
    }
}

/// Меню ячейки по правой кнопке или долгому нажатию.
private struct TableCellMenu: View {
    let blockId: UUID
    let row: Int
    let column: Int
    let model: PageEditorModel

    var body: some View {
        let table = model.table(of: blockId) ?? .empty()
        Button {
            model.insertTableRow(blockId, at: row, focusColumn: column)
        } label: {
            Label("Строка выше", systemImage: "arrow.up.to.line")
        }
        Button {
            model.insertTableRow(blockId, at: row + 1, focusColumn: column)
        } label: {
            Label("Строка ниже", systemImage: "arrow.down.to.line")
        }
        Button {
            model.insertTableColumn(blockId, at: column, focusRow: row)
        } label: {
            Label("Столбец слева", systemImage: "arrow.left.to.line")
        }
        Button {
            model.insertTableColumn(blockId, at: column + 1, focusRow: row)
        } label: {
            Label("Столбец справа", systemImage: "arrow.right.to.line")
        }
        Divider()
        Menu {
            Button("Строку выше") { model.moveTableRow(blockId, row, by: -1) }
                .disabled(row == 0)
            Button("Строку ниже") { model.moveTableRow(blockId, row, by: 1) }
                .disabled(row >= table.rowCount - 1)
            Button("Столбец влево") { model.moveTableColumn(blockId, column, by: -1) }
                .disabled(column == 0)
            Button("Столбец вправо") { model.moveTableColumn(blockId, column, by: 1) }
                .disabled(column >= table.columnCount - 1)
        } label: {
            Label("Переместить", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
        }
        Toggle(isOn: Binding(get: { table.hasHeaderRow }, set: { _ in model.toggleTableHeaderRow(blockId) })) {
            Label("Строка заголовков", systemImage: "rectangle.topthird.inset.filled")
        }
        Toggle(isOn: Binding(get: { table.hasHeaderColumn }, set: { _ in model.toggleTableHeaderColumn(blockId) })) {
            Label("Столбец заголовков", systemImage: "rectangle.leadingthird.inset.filled")
        }
        if table.columnWidths != nil {
            Button {
                model.setTableColumnWidths(blockId, nil)
            } label: {
                Label("Ровные столбцы", systemImage: "rectangle.split.3x1")
            }
        }
        Divider()
        Button(role: .destructive) {
            model.removeTableRow(blockId, at: row)
        } label: {
            Label("Удалить строку", systemImage: "trash")
        }
        .disabled(table.rowCount < 2)
        Button(role: .destructive) {
            model.removeTableColumn(blockId, at: column)
        } label: {
            Label("Удалить столбец", systemImage: "trash")
        }
        .disabled(table.columnCount < 2)
        Button(role: .destructive) {
            model.deleteBlock(blockId)
        } label: {
            Label("Удалить таблицу", systemImage: "tablecells.badge.ellipsis")
        }
    }
}

/// Граница столбца: при наведении видна линия цвета схемы, на Mac курсор «потянуть в стороны».
private struct TableColumnBorder: View {
    @State private var isHovered = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.accent.opacity(isHovered ? 0.8 : 0))
            .frame(width: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(LumenMotion.quick, value: isHovered)
            #if os(macOS)
            .pointerStyle(.columnResize)
            #endif
            .help("Потяните, чтобы поменять ширину столбца. Двойной щелчок: ровные столбцы")
            .accessibilityElement()
            .accessibilityLabel("Граница столбца")
    }
}
