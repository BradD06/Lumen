import LumenCore
import LumenThemes
import SwiftUI

/// Значение формулы в ячейке: только для чтения, считает его сама база.
struct FormulaValueView: View {
    let value: PropertyValue?

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        switch value {
        case .number(let number)?:
            Text(NumberText.format(number))
                .font(.callout.monospacedDigit())
                .foregroundStyle(theme.textPrimary)
        case .checkbox(let isOn)?:
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(isOn ? theme.accent : theme.textSecondary)
        case .date(let day)?:
            DayLabel(day: day, highlightsOverdue: false)
        case .text(let text)?:
            Text(text)
                .font(.callout)
                .foregroundStyle(text.hasPrefix("⚠︎") ? theme.textSecondary : theme.textPrimary)
                .lineLimit(1)
                .help(text)
        default:
            Text("—")
                .font(.callout)
                .foregroundStyle(theme.textSecondary.opacity(0.6))
        }
    }
}

/// Окно формулы: поле, проверка на первой строке базы, колонки и функции, которые можно вставить.
struct FormulaEditorSheet: View {
    let model: DataTableModel
    let property: PropertyDefinition
    let onDone: () -> Void

    @State private var source = ""
    @State private var didLoad = false
    @Environment(\.lumenTheme) private var theme

    private var table: DataTable? { model.table }
    private var sampleRow: DataRow? { model.visibleRows.first ?? model.snapshot.rows.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Например: {Цена} * {Количество}", text: $source, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(2...6)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    preview
                } footer: {
                    Text("Колонку пишут в фигурных скобках: {Срок}. Текст в кавычках: \"готово\". Формула считается для каждой строки.")
                }

                if let table {
                    Section("Колонки") {
                        ForEach(table.properties.filter { $0.id != property.id }) { other in
                            Button {
                                insert("{\(other.name)}")
                            } label: {
                                Label(other.name, systemImage: other.type.symbolName)
                                    .foregroundStyle(theme.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            insert("{Название}")
                        } label: {
                            Label("Название", systemImage: "textformat")
                                .foregroundStyle(theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Функции") {
                    ForEach(Formula.functions, id: \.syntax) { function in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(function.syntax)
                                .font(.callout.monospaced())
                                .foregroundStyle(theme.textPrimary)
                            Text(function.summary)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .textSelection(.enabled)
                    }
                    Text("Знаки: + − * / % ^, сравнения = ≠ < ≤ > ≥, «и», «или», «не». Дата + 3 даёт дату через три дня, дата − дата даёт число дней.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle("Формула «\(property.name)»")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.updateProperty(property.id) { $0.formula = text.isEmpty ? nil : text }
                        onDone()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
        .keyHintHost()
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            source = property.formula ?? ""
        }
    }

    @ViewBuilder
    private var preview: some View {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let table {
            switch Formula.preview(trimmed, property: property, row: sampleRow, table: table) {
            case .success(let value):
                if let row = sampleRow {
                    let name = row.title.isEmpty ? "Без названия" : row.title
                    Label("«\(name)»: \(value.displayText.isEmpty ? "пусто" : value.displayText)", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(theme.accent)
                } else {
                    Label("Формула верная", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(theme.accent)
                }
            case .failure(let error):
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func insert(_ text: String) {
        if !source.isEmpty, !source.hasSuffix(" "), !source.hasSuffix("(") {
            source += " "
        }
        source += text
    }
}
