import GRDB
import LumenStorage
import LumenThemes
import SwiftUI

/// Остров внизу окна на Mac и iPad: стеклянная капсула по центру. У каждой кнопки значок и подпись.
/// Слева четыре раздела: открытый выпрыгивает кружком над капсулой, под кружком в капсуле вырез
/// (на «Записках» число неразобранных переезжает в кружок). Дальше поиск ⌘K, «Создать» и «Ещё»
/// с архивом и настройками. В режиме фокуса остров уходит.
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

    #if os(macOS)
    static let height: CGFloat = 62
    private static let itemWidth: CGFloat = 64
    #else
    static let height: CGFloat = 64
    private static let itemWidth: CGFloat = 66
    #endif
    private static let padding: CGFloat = 16
    private static let dividerWidth: CGFloat = 14

    /// Разделы в острове, слева направо. Архив в «Ещё».
    static let rooms: [StudyRoom] = [.desk, .notes, .tasks, .shelf]

    var body: some View {
        BubbleBar(
            height: Self.height,
            bubbleX: bubbleX,
            bubbleImage: bubbleRoom?.systemImage ?? StudyRoom.desk.systemImage,
            bubbleCount: bubbleRoom.map { Self.rooms.contains($0) ? $0.count(in: counts) : 0 } ?? 0
        ) {
            HStack(spacing: 0) {
                ForEach(Self.rooms) { room in
                    roomButton(room)
                }
                divider
                searchButton
                createButton
                moreMenu
            }
            .padding(.horizontal, Self.padding)
        }
        .animation(LumenMotion.standard, value: selection)
        .buttonStyle(.plain)
        .padding(.top, BubbleMetrics.lift)
        .fixedSize()
        .task { await observe() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Разделы")
        .accessibilityIdentifier("island")
    }

    /// Раздел в кружке: один из четырёх или архив (тогда кружок над «Ещё»).
    private var bubbleRoom: StudyRoom? {
        (Self.rooms + [.archive]).first { $0.contains(selection) }
    }

    /// Центр кружка от левого края капсулы. Кнопки одной ширины, так что считать проще, чем мерить.
    private var bubbleX: CGFloat? {
        guard let room = bubbleRoom else { return nil }
        let slot: CGFloat
        if let index = Self.rooms.firstIndex(of: room) {
            slot = CGFloat(index)
        } else {
            slot = CGFloat(Self.rooms.count + 2) + Self.dividerWidth / Self.itemWidth
        }
        return Self.padding + (slot + 0.5) * Self.itemWidth
    }

    private var divider: some View {
        Capsule()
            .fill(theme.line)
            .frame(width: 1, height: 26)
            .frame(width: Self.dividerWidth)
    }

    private func roomButton(_ room: StudyRoom) -> some View {
        let isOn = room.contains(selection)
        let count = room.count(in: counts)
        return Button {
            onSelect(room.item)
        } label: {
            BubbleBarLabel(
                title: room.title,
                systemImage: room.systemImage,
                isOn: isOn,
                count: count,
                width: Self.itemWidth,
                height: Self.height
            )
        }
        .help(room.hint)
        .accessibilityLabel(count > 0 ? "\(room.title), \(count)" : room.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("room.\(room.rawValue)")
        .keyHint(room.title) { onSelect(room.item) }
    }

    /// «Поиск»: на Mac открывается и по ⌘K.
    private var searchButton: some View {
        Button(action: onSearch) {
            BubbleBarLabel(title: "Поиск", systemImage: "magnifyingglass", width: Self.itemWidth, height: Self.height)
        }
        .help("Поиск и команды (⌘K)")
        .accessibilityLabel("Поиск")
        .accessibilityIdentifier("island.search")
        .keyHint("Поиск", perform: onSearch)
    }

    /// «Создать» акцентом: щелчок создаёт заметку во «Входящих», меню выбирает, что создать.
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
            BubbleBarLabel(title: "Создать", systemImage: "plus", tint: theme.accent, width: Self.itemWidth, height: Self.height)
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
            BubbleBarLabel(
                title: "Ещё",
                systemImage: "ellipsis",
                isOn: StudyRoom.archive.contains(selection),
                width: Self.itemWidth,
                height: Self.height
            )
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
    /// На акцентном кружке цвета меняются местами, иначе значок сливается с ним.
    var onAccent = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9.5, weight: .bold))
            .contentTransition(.numericText())
            .foregroundStyle(onAccent ? theme.accent : theme.onAccent)
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background(onAccent ? theme.sheet : theme.accent, in: Capsule())
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
