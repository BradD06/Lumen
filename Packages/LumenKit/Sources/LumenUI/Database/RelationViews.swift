import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

// MARK: - Значения

/// Связанные строки капсулами с их названиями. Строки в корзине не показываются.
struct RelationChips: View {
    let property: PropertyDefinition
    let value: PropertyValue?
    let relations: RelationContext
    var font: Font = .caption
    /// Сколько капсул показать, остальные числом «+3».
    var limit = 3

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let rows = relations.linkedRows(value, in: property.relation?.targetTableId)
        HStack(spacing: 4) {
            ForEach(rows.prefix(limit)) { row in
                Label(row.page.displayTitle, systemImage: "arrow.up.right")
                    .labelStyle(RelationChipLabelStyle())
                    .font(font)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(theme.accentSoft, in: Capsule())
            }
            if rows.count > limit {
                Text("+\(rows.count - limit)")
                    .font(font)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

private struct RelationChipLabelStyle: LabelStyle {
    func makeBody(configuration: LabelStyleConfiguration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Значение сводки только для чтения: число, дата или текст, процент со знаком «%».
struct RollupValueView: View {
    let property: PropertyDefinition
    let value: PropertyValue?

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        switch value {
        case .number(let number)?:
            Text(RollupText.number(number, property: property))
                .font(.callout.monospacedDigit())
                .foregroundStyle(theme.textPrimary)
        case .date(let day)?:
            DayLabel(day: day, highlightsOverdue: false)
        case .text(let text)?:
            Text(text)
                .font(.callout)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .help(text)
        default:
            Text(property.rollup?.relationPropertyId == nil ? "Не настроено" : "—")
                .font(.callout)
                .foregroundStyle(theme.textSecondary.opacity(0.6))
        }
    }
}

enum RollupText {
    /// Число сводки как его показывают: «67 %» у процента, иначе как обычное число.
    static func number(_ number: Double, property: PropertyDefinition) -> String {
        let text = NumberText.format(number)
        return property.type == .rollup && property.rollup?.function.isPercent == true ? "\(text) %" : text
    }
}

// MARK: - Выбор связанных строк

/// Ячейка связи: капсулы связанных строк, по нажатию окно выбора.
struct RelationCell: View {
    let property: PropertyDefinition
    let value: PropertyValue?
    let relations: RelationContext
    let onChange: (PropertyValue?) -> Void
    var onCreateRow: (@MainActor (UUID, String) async -> UUID?)?
    var onOpenPage: ((UUID) -> Void)?

    @State private var isPicking = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button {
            isPicking = true
        } label: {
            if relations.linkedRows(value, in: property.relation?.targetTableId).isEmpty {
                Text("Пусто")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
            } else {
                RelationChips(property: property, value: value, relations: relations, font: .callout, limit: 2)
            }
        }
        .buttonStyle(.plain)
        .help(relationHelp)
        .popover(isPresented: $isPicking) {
            RelationPicker(
                property: property,
                value: value,
                relations: relations,
                onChange: onChange,
                onCreateRow: onCreateRow,
                onOpenPage: onOpenPage.map { open -> (UUID) -> Void in
                    { id in
                        isPicking = false
                        open(id)
                    }
                }
            )
            .keyHintHost()
            .presentationCompactAdaptation(.popover)
        }
    }

    private var relationHelp: String {
        guard let id = property.relation?.targetTableId else { return "Связь" }
        return "Связь с базой «\(relations.tableTitles[id] ?? "База удалена")»"
    }
}

/// Окно выбора: поиск по строкам связанной базы, отметка галочкой, новая строка по названию.
struct RelationPicker: View {
    let property: PropertyDefinition
    let value: PropertyValue?
    let relations: RelationContext
    let onChange: (PropertyValue?) -> Void
    var onCreateRow: (@MainActor (UUID, String) async -> UUID?)?
    var onOpenPage: ((UUID) -> Void)?

    @State private var query = ""
    /// Отмеченные строки: меняются сразу, не дожидаясь, пока база пришлёт новое значение.
    @State private var selected: [UUID] = []
    @State private var didLoad = false
    @Environment(\.lumenTheme) private var theme

    private var targetTableId: UUID? { property.relation?.targetTableId }

    private var candidates: [DataRow] {
        guard let targetTableId else { return [] }
        let all = relations.rows[targetTableId] ?? []
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matching = trimmed.isEmpty ? all : all.filter { $0.page.displayTitle.localizedCaseInsensitiveContains(trimmed) }
        // Отмеченные сверху, как в Notion.
        let chosen = Set(selected)
        return matching.filter { chosen.contains($0.id) } + matching.filter { !chosen.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: property.type.symbolName)
                    .foregroundStyle(theme.textSecondary)
                Text(targetTableId.flatMap { relations.tableTitles[$0] } ?? "База удалена")
                    .font(.headline)
                    .lineLimit(1)
                if property.relation?.isTwoWay == true {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .help("Двусторонняя связь: та база тоже видит эту строку")
                }
            }
            TextField("Найти или создать строку", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createFromQuery)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(candidates) { row in
                        candidateRow(row)
                    }
                    if canCreate {
                        Button(action: createFromQuery) {
                            Label("Создать «\(query.trimmingCharacters(in: .whitespaces))»", systemImage: "plus")
                                .font(.callout)
                                .foregroundStyle(theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if candidates.isEmpty, !canCreate {
                        Text(targetTableId.flatMap { relations.tables[$0] } == nil
                             ? "Связанная база удалена"
                             : "В той базе пока нет строк")
                            .font(.callout)
                            .foregroundStyle(theme.textSecondary)
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: 320)

            if !selected.isEmpty {
                Button("Убрать все связи", role: .destructive) {
                    selected = []
                    onChange(nil)
                }
                .font(.callout)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selected = value?.pageIds ?? []
        }
    }

    private func candidateRow(_ row: DataRow) -> some View {
        let isOn = selected.contains(row.id)
        return HStack(spacing: 8) {
            Button {
                toggle(row.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? theme.accent : theme.textSecondary)
                    Text(row.page.displayTitle)
                        .font(.callout)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOn, let onOpenPage {
                Button {
                    LumenSounds.play(.navigate)
                    onOpenPage(row.id)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Открыть строку")
            }
        }
        .background(isOn ? theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canCreate: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard onCreateRow != nil, targetTableId.map({ relations.tables[$0] != nil }) == true, !trimmed.isEmpty else { return false }
        let all = targetTableId.flatMap { relations.rows[$0] } ?? []
        return !all.contains { $0.page.displayTitle.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func toggle(_ id: UUID) {
        LumenSounds.play(.tap)
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
        onChange(DataRelation.normalized(selected))
    }

    private func createFromQuery() {
        guard canCreate, let targetTableId, let onCreateRow else { return }
        let title = query.trimmingCharacters(in: .whitespaces)
        query = ""
        Task {
            guard let id = await onCreateRow(targetTableId, title) else { return }
            selected.append(id)
            onChange(DataRelation.normalized(selected))
        }
    }
}

// MARK: - Настройка связи

/// Новая связь: с какой базой и видна ли она там тоже.
struct RelationSetupSheet: View {
    let model: DataTableModel
    let onDone: () -> Void

    @State private var targetId: UUID?
    @State private var twoWay = true
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("База", selection: $targetId) {
                        Text("Выберите базу").tag(UUID?.none)
                        ForEach(model.snapshot.databases) { choice in
                            Text(title(of: choice)).tag(UUID?.some(choice.id))
                        }
                    }
                } footer: {
                    Text("В каждой строке можно будет отметить связанные строки той базы: например, у задачи её проект, у конспекта книги.")
                }
                Section {
                    Toggle("Показать связь и в той базе", isOn: $twoWay)
                } footer: {
                    Text(twoWay
                         ? "В той базе появится обратная колонка: отметили проект у задачи, и у проекта появилась эта задача."
                         : "Связь будет видна только в этой базе.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle("Связь с базой")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        if let targetId {
                            LumenSounds.play(.create)
                            model.addRelation(to: targetId, twoWay: twoWay)
                        }
                        onDone()
                    }
                    .disabled(targetId == nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
        .keyHintHost()
    }

    private func title(of choice: DataTableChoice) -> String {
        let name = (choice.icon.map { "\($0) " } ?? "") + choice.displayTitle
        return choice.id == model.table?.id ? "\(name) (эта же база)" : name
    }
}

// MARK: - Настройка сводки

/// Сводка: по какой связи, какую колонку той базы и что считать.
struct RollupSetupSheet: View {
    let model: DataTableModel
    /// Существующая сводка, которую меняют. `nil` значит новая.
    let property: PropertyDefinition?
    let onDone: () -> Void

    @State private var relationId: UUID?
    /// Колонка той базы. `nil` значит название строки.
    @State private var targetId: UUID?
    @State private var function: RollupFunction = .count
    @State private var didLoad = false
    @Environment(\.lumenTheme) private var theme

    private var relationProperties: [PropertyDefinition] {
        model.table?.properties.filter { $0.type == .relation } ?? []
    }

    private var targetTable: DataTable? {
        guard let id = model.table?.property(relationId)?.relation?.targetTableId else { return nil }
        return model.snapshot.relations.tables[id]
    }

    private var targetProperty: PropertyDefinition? { targetTable?.property(targetId) }

    private var functions: [RollupFunction] {
        RollupFunction.available(for: targetId == nil ? nil : targetProperty?.type)
    }

    var body: some View {
        NavigationStack {
            Form {
                if relationProperties.isEmpty {
                    Section {
                        Text("Сначала добавьте колонку «Связь с базой»: сводка считает по связанным строкам.")
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    Section {
                        Picker("Связь", selection: $relationId) {
                            ForEach(relationProperties) { relation in
                                Text(relation.name).tag(UUID?.some(relation.id))
                            }
                        }
                        Picker("Колонка", selection: $targetId) {
                            Text("Название").tag(UUID?.none)
                            ForEach(targetTable?.properties.filter { $0.type != .rollup } ?? []) { other in
                                Text(other.name).tag(UUID?.some(other.id))
                            }
                        }
                        Picker("Считать", selection: $function) {
                            ForEach(functions) { function in
                                Text(function.title).tag(function)
                            }
                        }
                    } footer: {
                        Text("Например: связь «Задачи», колонка «Статус», «Готово, %» показывает, какая часть задач проекта сделана.")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle(property == nil ? "Новая сводка" : "Сводка «\(property?.name ?? "")»")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", action: save)
                        .disabled(relationId == nil)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onChange(of: relationId) { _, _ in
                if didLoad, targetTable?.property(targetId) == nil { targetId = nil }
            }
            .onChange(of: functions) { _, available in
                if !available.contains(function) { function = .count }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
        .keyHintHost()
        .onAppear {
            guard !didLoad else { return }
            if let config = property?.rollup {
                relationId = config.relationPropertyId
                targetId = config.targetPropertyId
                function = config.function
            } else {
                relationId = relationProperties.first?.id
            }
            didLoad = true
        }
    }

    private func save() {
        let config = RollupConfig(relationPropertyId: relationId, targetPropertyId: targetId, function: function)
        if let property {
            model.updateProperty(property.id) { $0.rollup = config }
        } else {
            let relationName = model.table?.property(relationId)?.name ?? "Связь"
            let column = targetId == nil ? nil : targetProperty?.name
            let name = [relationName, column, function.title.lowercased()].compactMap { $0 }.joined(separator: " · ")
            model.addRollup(config, name: name)
        }
        onDone()
    }
}
