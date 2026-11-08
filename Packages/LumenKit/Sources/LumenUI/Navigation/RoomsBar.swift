import GRDB
import LumenStorage
import LumenThemes
import SwiftUI

/// Комнаты сверху для темы «Кабинет»: латунные таблички вместо боковой панели.
/// Стол, полка, записки, дела, архив. Справа поиск «Найти в кабинете…» и настройки.
struct RoomsBar: View {
    let database: AppDatabase
    let selection: SidebarItem?
    var onSelect: (SidebarItem) -> Void
    var onSearch: () -> Void
    var onSettings: () -> Void

    @Environment(\.lumenTheme) private var theme
    @State private var counts = SidebarSnapshot.empty

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                row(wideSearch: true)
                row(wideSearch: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    row(wideSearch: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Rectangle()
                .fill(LinearGradient(colors: [theme.accent.opacity(0), theme.accent.opacity(0.45), theme.accent.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .background(theme.backgroundStops.first ?? .clear)
        .task { await observe() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roomsBar")
    }

    private func row(wideSearch: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(StudyRoom.allCases) { room in
                plaque(room)
            }
            Spacer(minLength: 12)
            Button(action: onSearch) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    if wideSearch {
                        Text("Найти в кабинете…")
                            .italic()
                            .fixedSize()
                        Text("⌘K")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.accent.opacity(0.8))
                    }
                }
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(theme.cardFill, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.accent.opacity(0.3), lineWidth: 1))
                .contentShape(Capsule())
            }
            .accessibilityLabel("Найти в кабинете")
            .help("Поиск и команды (⌘K)")
            .keyHint("Найти", perform: onSearch)
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundStyle(theme.accent.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Настройки")
            .help("Настройки: тема, звук, данные, копии и синхронизация")
            .keyHint("Настройки", perform: onSettings)
        }
        .buttonStyle(.plain)
    }

    /// Латунная табличка с «винтиками» по краям; открытая комната залита латунью.
    private func plaque(_ room: StudyRoom) -> some View {
        let isSelected = room.contains(selection)
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let ink = theme.backgroundStops.last ?? .black
        let count = room.count(in: counts)
        return Button {
            onSelect(room.item)
        } label: {
            HStack(spacing: 6) {
                Text(room.title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(1.6)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isSelected ? ink : theme.accent)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background {
                if isSelected {
                    shape.fill(LinearGradient(
                        colors: [theme.accent.mix(with: .white, by: 0.25), theme.accent, theme.accent.mix(with: .black, by: 0.2)],
                        startPoint: .top, endPoint: .bottom
                    ))
                }
            }
            .overlay(shape.strokeBorder(theme.accent.opacity(isSelected ? 0.9 : 0.5), lineWidth: 1))
            .overlay(shape.inset(by: 2.5).strokeBorder(theme.accent.opacity(isSelected ? 0 : 0.18), lineWidth: 0.5))
            .overlay {
                HStack {
                    screw
                    Spacer()
                    screw
                }
                .padding(.horizontal, 5)
                .foregroundStyle(isSelected ? ink.opacity(0.45) : theme.accent.opacity(0.55))
            }
            .contentShape(shape)
        }
        .keyHint(room.title) { onSelect(room.item) }
        .accessibilityLabel(count > 0 ? "\(room.title), \(count)" : room.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("room.\(room.rawValue)")
        .help(room.hint)
    }

    private var screw: some View {
        Circle().frame(width: 3, height: 3)
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                counts = value
            }
        } catch {
            lumenLog.error("Rooms bar observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Комнаты «Кабинета». Книги и страницы открыты поверх, ни одна табличка тогда не горит.
enum StudyRoom: String, CaseIterable, Identifiable {
    case desk, shelf, notes, tasks, archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desk: "Стол"
        case .shelf: "Полка"
        case .notes: "Записки"
        case .tasks: "Дела"
        case .archive: "Архив"
        }
    }

    var hint: String {
        switch self {
        case .desk: "Стол: что читаю, дела на сегодня, записки"
        case .shelf: "Полка: книги, тетради, страницы и папки"
        case .notes: "Записки: быстрые заметки, которые ещё не разобраны"
        case .tasks: "Дела: задачи, доска и календарь"
        case .archive: "Архив: удалённое, хранится 30 дней"
        }
    }

    var item: SidebarItem {
        switch self {
        case .desk: .home
        case .shelf: .library(nil)
        case .notes: .inbox
        case .tasks: .tasks
        case .archive: .trash
        }
    }

    /// Горит ли табличка, когда открыто `selection`.
    func contains(_ selection: SidebarItem?) -> Bool {
        switch (self, selection) {
        case (.desk, .home), (.desk, nil), (.shelf, .library), (.notes, .inbox), (.tasks, .tasks), (.archive, .trash): true
        default: false
        }
    }

    /// Число на табличке: неразобранные записки и то, что лежит в архиве.
    func count(in snapshot: SidebarSnapshot) -> Int {
        switch self {
        case .notes: snapshot.inboxCount
        case .archive: snapshot.trashCount
        case .desk, .shelf, .tasks: 0
        }
    }
}
