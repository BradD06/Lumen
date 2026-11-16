import GRDB
import LumenStorage
import LumenThemes
import SwiftUI

/// Левая панель: узкая колонка со значками. Сверху капсула с разделами (открытый залит
/// светлым, на «Записках» число неразобранных) и поиском, внизу круглая «+», архив и настройки.
struct SideRail: View {
    let database: AppDatabase
    let selection: SidebarItem?
    var onSelect: (SidebarItem) -> Void
    var onSearch: () -> Void
    var onSettings: () -> Void
    var onCreate: (CreateKind) -> Void
    var onQuickNote: () -> Void

    @Environment(\.lumenTheme) private var theme
    @State private var counts = SidebarSnapshot.empty
    /// Светлый кружок переезжает с раздела на раздел, а не гаснет и зажигается.
    @Namespace private var markSpace

    static let width: CGFloat = 76

    /// Разделы в капсуле, сверху вниз. Архив внизу колонки, отдельно.
    private static let rooms: [StudyRoom] = [.desk, .notes, .tasks, .shelf]

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                ForEach(Self.rooms) { room in
                    roomButton(room)
                }
                iconButton("Найти", systemImage: "magnifyingglass", isOn: false, action: onSearch)
                    .help("Поиск и команды (⌘K)")
                    .accessibilityIdentifier("rail.search")
            }
            .animation(LumenMotion.standard, value: selection)
            .padding(6)
            .lumenGlass(Capsule())

            Spacer(minLength: 12)

            createButton
            roomButton(.archive)
                .padding(.top, 4)
            iconButton("Настройки", systemImage: "gearshape", isOn: false, action: onSettings)
                .help("Настройки: тема, обложки, звук, данные, копии и синхронизация")
                .accessibilityIdentifier("rail.settings")
        }
        .buttonStyle(.plain)
        .padding(.vertical, 14)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .task { await observe() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Разделы")
        .accessibilityIdentifier("sideRail")
    }

    private func roomButton(_ room: StudyRoom) -> some View {
        let isOn = room.contains(selection)
        let count = room.count(in: counts)
        return iconButton(room.title, systemImage: room.systemImage, isOn: isOn) {
            onSelect(room.item)
        }
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .contentTransition(.numericText())
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(theme.accent, in: Capsule())
                    .offset(x: 4, y: -2)
                    .allowsHitTesting(false)
            }
        }
        .help(room.hint)
        .accessibilityLabel(count > 0 ? "\(room.title), \(count)" : room.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("room.\(room.rawValue)")
    }

    /// Круглая кнопка со значком. Открытый раздел залит светлым, значок на нём тёмный.
    private func iconButton(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? theme.onAccent : theme.textPrimary.opacity(0.8))
                .frame(width: 44, height: 44)
                .background {
                    if isOn {
                        Circle()
                            .fill(theme.textPrimary)
                            .matchedGeometryEffect(id: "mark", in: markSpace)
                    }
                }
                .contentShape(Circle())
        }
        .accessibilityLabel(title)
        .keyHint(title, perform: action)
    }

    /// Круглая «+»: щелчок создаёт заметку во «Входящих», меню выбирает, что создать.
    private var createButton: some View {
        Menu {
            ForEach(CreateKind.allCases) { kind in
                Button {
                    onCreate(kind)
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 50, height: 50)
                .background(theme.accent, in: Circle())
                .shadow(color: theme.accent.opacity(0.35), radius: 10, y: 4)
                .contentShape(Circle())
        } primaryAction: {
            onQuickNote()
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Новая заметка (⌘N). Удерживайте, чтобы выбрать, что создать")
        .accessibilityLabel("Создать")
        .accessibilityIdentifier("rail.create")
        .keyHint("Создать", perform: onQuickNote)
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetchCounts(db) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) where value != counts {
                withAnimation(LumenMotion.standard) { counts = value }
            }
        } catch {
            lumenLog.error("Side rail observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Разделы приложения. Книги и страницы открыты поверх, ни один раздел тогда не горит.
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

    var systemImage: String {
        switch self {
        case .desk: "sun.max"
        case .shelf: "books.vertical"
        case .notes: "doc.text"
        case .tasks: "checkmark.square"
        case .archive: "archivebox"
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

    /// Горит ли раздел, когда открыто `selection`.
    func contains(_ selection: SidebarItem?) -> Bool {
        switch (self, selection) {
        case (.desk, .home), (.desk, nil), (.shelf, .library), (.shelf, .reading), (.notes, .inbox), (.tasks, .tasks), (.archive, .trash): true
        default: false
        }
    }

    /// Число на значке: неразобранные записки и то, что лежит в архиве.
    func count(in snapshot: SidebarSnapshot) -> Int {
        switch self {
        case .notes: snapshot.inboxCount
        case .archive: snapshot.trashCount
        case .desk, .shelf, .tasks: 0
        }
    }
}
