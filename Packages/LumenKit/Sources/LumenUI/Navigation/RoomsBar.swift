import GRDB
import LumenStorage
import LumenThemes
import SwiftUI

/// Комнаты сверху: стеклянная капсула с комнатами вместо боковой панели, открытая комната
/// залита латунью. Стол, полка, записки, дела, архив. Справа поиск «Найти в кабинете…» и настройки.
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
            .padding(.vertical, 8)
            Rectangle()
                .fill(LinearGradient(colors: [theme.accent.opacity(0), theme.accent.opacity(0.35), theme.accent.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .background {
            // Полоса тоже стеклянная: шкаф за ней едва просвечивает.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill((theme.backgroundStops.first ?? .clear).opacity(0.55))
            }
            .ignoresSafeArea(edges: .top)
        }
        .task { await observe() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roomsBar")
    }

    private func row(wideSearch: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(StudyRoom.allCases) { room in
                    plaque(room)
                }
            }
            .padding(3)
            .lumenGlass(Capsule())
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
                .frame(height: 32)
                .lumenGlass(Capsule())
                .contentShape(Capsule())
            }
            .accessibilityLabel("Найти в кабинете")
            .help("Поиск и команды (⌘K)")
            .keyHint("Найти", perform: onSearch)
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundStyle(theme.accent.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .lumenGlass(Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Настройки")
            .help("Настройки: тема, звук, данные, копии и синхронизация")
            .keyHint("Настройки", perform: onSettings)
        }
        .buttonStyle(.plain)
    }

    /// Комната в капсуле. Открытая залита латунью, текст на ней цвета `onAccent`.
    private func plaque(_ room: StudyRoom) -> some View {
        let isSelected = room.contains(selection)
        let shape = Capsule()
        let count = room.count(in: counts)
        return Button {
            onSelect(room.item)
        } label: {
            HStack(spacing: 6) {
                Text(room.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(
                            (isSelected ? theme.onAccent : theme.accent).opacity(0.18),
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(isSelected ? theme.onAccent : theme.textPrimary.opacity(0.82))
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background {
                if isSelected {
                    shape.fill(LinearGradient(
                        colors: [theme.accent.mix(with: .white, by: 0.22), theme.accent, theme.accent.mix(with: .black, by: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .shadow(color: theme.accent.opacity(0.35), radius: 6, y: 2)
                }
            }
            .contentShape(shape)
        }
        .keyHint(room.title) { onSelect(room.item) }
        .accessibilityLabel(count > 0 ? "\(room.title), \(count)" : room.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("room.\(room.rawValue)")
        .help(room.hint)
        .animation(.snappy(duration: 0.2), value: isSelected)
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
