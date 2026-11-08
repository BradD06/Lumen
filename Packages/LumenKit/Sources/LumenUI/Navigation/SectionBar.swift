import GRDB
import LumenStorage
import LumenThemes
import SwiftUI

/// Строка разделов сверху для темы «Бумага»: вместо боковой панели, как рубрики в газете.
/// Слева название, дальше разделы, текущий подчёркнут красными чернилами. Справа дата, корзина и настройки.
struct SectionBar: View {
    let database: AppDatabase
    let selection: SidebarItem?
    var onSelect: (SidebarItem) -> Void
    var onSettings: () -> Void

    @Environment(\.lumenTheme) private var theme
    @State private var counts = SidebarSnapshot.empty

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                row(showsDate: true)
                row(showsDate: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    row(showsDate: false)
                }
            }
            .padding(.horizontal, 18)
            // Двойная линейка снизу, как под шапкой газеты.
            VStack(spacing: 2) {
                Rectangle().fill(theme.textPrimary.opacity(0.75)).frame(height: 1.5)
                Rectangle().fill(theme.textPrimary.opacity(0.35)).frame(height: 0.5)
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 4)
        .background(theme.backgroundStops.first ?? .clear)
        .task { await observe() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sectionBar")
    }

    private func row(showsDate: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text("Lumen")
                .font(.title3.weight(.bold).italic())
                .foregroundStyle(theme.textPrimary)
                .fixedSize()
            HStack(spacing: 16) {
                ForEach(PaperSection.allCases) { section in
                    sectionButton(section)
                }
            }
            Spacer(minLength: 12)
            if showsDate {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(Self.dateTitle(context.date))
                        .font(.callout.italic())
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize()
                }
            }
            Button {
                onSelect(.trash)
            } label: {
                Image(systemName: "trash")
                    .overlay(alignment: .topTrailing) {
                        if counts.trashCount > 0 {
                            Circle().fill(theme.accent).frame(width: 5, height: 5).offset(x: 3, y: -2)
                        }
                    }
            }
            .foregroundStyle(selection == .trash ? theme.accent : theme.textSecondary)
            .accessibilityLabel(counts.trashCount > 0 ? "Корзина, \(counts.trashCount)" : "Корзина")
            .help("Корзина")
            .keyHint("Корзина") { onSelect(.trash) }
            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .foregroundStyle(theme.textSecondary)
            .accessibilityLabel("Настройки")
            .help("Настройки: тема, звук, данные, копии и синхронизация")
            .keyHint("Настройки", perform: onSettings)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }

    private func sectionButton(_ section: PaperSection) -> some View {
        let isSelected = section.contains(selection)
        return Button {
            onSelect(section.item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(section.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                if section == .inbox, counts.inboxCount > 0 {
                    Text("\(counts.inboxCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .foregroundStyle(isSelected ? theme.accent : theme.textPrimary.opacity(0.8))
            .fixedSize()
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle().fill(theme.accent).frame(height: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .keyHint(section.title) { onSelect(section.item) }
        .accessibilityIdentifier("section.\(section.rawValue)")
    }

    /// «Суббота, 7 ноября».
    nonisolated static func dateTitle(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                counts = value
            }
        } catch {
            lumenLog.error("Section bar observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Разделы в строке «Бумаги». Книги и страницы ни к одному не относятся: они открыты поверх.
enum PaperSection: String, CaseIterable, Identifiable {
    case home, inbox, tasks, library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Сегодня"
        case .inbox: "Входящие"
        case .tasks: "Задачи"
        case .library: "Библиотека"
        }
    }

    var item: SidebarItem {
        switch self {
        case .home: .home
        case .inbox: .inbox
        case .tasks: .tasks
        case .library: .library(nil)
        }
    }

    /// Подчёркнут ли раздел, когда открыто `selection`.
    func contains(_ selection: SidebarItem?) -> Bool {
        switch (self, selection) {
        case (.home, .home), (.home, nil), (.inbox, .inbox), (.tasks, .tasks), (.library, .library): true
        default: false
        }
    }
}
