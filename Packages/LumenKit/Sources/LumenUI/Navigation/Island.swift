import GRDB
import LumenStorage
import LumenThemes
import SwiftUI

/// Остров внизу окна на Mac и iPad: стеклянная капсула по центру. Слева четыре раздела
/// (открытый на светлой подложке, на «Записках» число неразобранных), дальше поиск ⌘K,
/// круглая «+» и «Ещё» с архивом и настройками. В режиме фокуса остров уходит.
struct NavigationIsland: View {
    let database: AppDatabase
    let selection: SidebarItem?
    var onSelect: (SidebarItem) -> Void
    var onSearch: () -> Void
    var onSettings: () -> Void
    var onCreate: (CreateKind) -> Void
    var onQuickNote: () -> Void

    @Environment(\.lumenTheme) private var theme
    @State private var counts = SidebarSnapshot.empty
    /// Подложка переезжает с раздела на раздел, а не гаснет и зажигается.
    @Namespace private var markSpace

    static let height: CGFloat = 52

    /// Разделы в острове, слева направо. Архив в «Ещё».
    static let rooms: [StudyRoom] = [.desk, .notes, .tasks, .shelf]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.rooms) { room in
                roomButton(room)
            }
            divider
            searchButton
            createButton
            divider
            moreMenu
        }
        .animation(LumenMotion.standard, value: selection)
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .lumenGlass(Capsule())
        .fixedSize()
        .task { await observe() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Разделы")
        .accessibilityIdentifier("island")
    }

    private var divider: some View {
        Capsule()
            .fill(theme.line)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }

    private func roomButton(_ room: StudyRoom) -> some View {
        let isOn = room.contains(selection)
        let count = room.count(in: counts)
        return Button {
            onSelect(room.item)
        } label: {
            Image(systemName: room.systemImage)
                .font(.system(size: 17, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? theme.textPrimary : theme.textSecondary)
                .frame(width: 40, height: 40)
                .background {
                    if isOn {
                        Circle()
                            .fill(theme.surface2)
                            .matchedGeometryEffect(id: "mark", in: markSpace)
                    }
                }
                .contentShape(Circle())
        }
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                CountBadge(count: count)
                    .offset(x: 2, y: 1)
            }
        }
        .help(room.hint)
        .accessibilityLabel(count > 0 ? "\(room.title), \(count)" : room.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("room.\(room.rawValue)")
        .keyHint(room.title) { onSelect(room.item) }
    }

    /// «Поиск ⌘K»: тихая капсула, на iPad без сочетания клавиш.
    private var searchButton: some View {
        Button(action: onSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                Text("Поиск")
                    .font(.system(size: 14))
                #if os(macOS)
                Text("⌘K")
                    .font(.system(size: 11))
                    .padding(.leading, 14)
                #endif
            }
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(Capsule())
        }
        .help("Поиск и команды (⌘K)")
        .accessibilityLabel("Поиск")
        .accessibilityIdentifier("island.search")
        .keyHint("Поиск", perform: onSearch)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 40, height: 40)
                .background(theme.accent, in: Circle())
                .contentShape(Circle())
        } primaryAction: {
            onQuickNote()
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Новая заметка (⌘N). Удерживайте, чтобы выбрать, что создать")
        .accessibilityLabel("Создать")
        .accessibilityIdentifier("island.create")
        .keyHint("Создать", perform: onQuickNote)
    }

    /// «Ещё»: архив и настройки, которым не нужно место на виду.
    private var moreMenu: some View {
        let archived = StudyRoom.archive.count(in: counts)
        return Menu {
            Button {
                onSelect(StudyRoom.archive.item)
            } label: {
                Label(archived > 0 ? "Архив · \(archived)" : "Архив", systemImage: StudyRoom.archive.systemImage)
            }
            Button(action: onSettings) {
                Label("Настройки", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(StudyRoom.archive.contains(selection) ? theme.textPrimary : theme.textSecondary)
                .frame(width: 40, height: 40)
                .background {
                    if StudyRoom.archive.contains(selection) {
                        Circle()
                            .fill(theme.surface2)
                            .matchedGeometryEffect(id: "mark", in: markSpace)
                    }
                }
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Архив и настройки")
        .accessibilityLabel("Ещё")
        .accessibilityIdentifier("island.more")
        .keyHint("Настройки", perform: onSettings)
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try SidebarSnapshot.fetchCounts(db) }
            .removeDuplicates()
        do {
            for try await value in observation.values(in: database.reader) where value != counts {
                withAnimation(LumenMotion.standard) { counts = value }
            }
        } catch {
            lumenLog.error("Island observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Число на значке раздела: маленькая капсула акцентом.
struct CountBadge: View {
    let count: Int
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9.5, weight: .bold))
            .contentTransition(.numericText())
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background(theme.accent, in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
        case .desk: "house"
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
