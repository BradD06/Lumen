import SwiftUI

/// Что показывать на экране. Всё, что нужно не каждую минуту, по умолчанию спрятано,
/// а включается в настройках, в разделе «Что показывать на экране».
enum ScreenOptions {
    static let tabStripKey = "screen.tabStrip"
    static let windowButtonsKey = "screen.windowButtons"
    static let saveStatusKey = "screen.saveStatus"
    static let wordCountKey = "screen.wordCount"
    static let breadcrumbsKey = "screen.breadcrumbs"
    static let readerProgressKey = "screen.readerProgress"
    static let gridKey = "library.snapToGrid"

    static let homeReadingKey = "screen.home.reading"
    static let homeTasksKey = "screen.home.tasks"
    static let homeInboxKey = "screen.home.inbox"
    static let homeRecentKey = "screen.home.recent"

    static let sidebarRecentKey = "screen.sidebar.recent"
    static let sidebarFavoritesKey = "screen.sidebar.favorites"
    static let sidebarDatabasesKey = "screen.sidebar.databases"
    static let sidebarFoldersKey = "screen.sidebar.folders"

    /// «Назад / Вперёд» и «Разделить экран» вверху окна. На Mac есть ⌘[ ⌘] ⌘\, поэтому кнопки
    /// спрятаны; на iPad клавиатуры может не быть, там они видны.
    static var windowButtonsDefault: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }
}

/// Когда видна строка вкладок.
enum TabStripMode: String, CaseIterable, Identifiable, Sendable {
    case always
    case multiple
    case never

    var id: Self { self }

    var title: String {
        switch self {
        case .always: "Всегда"
        case .multiple: "Когда их больше одной"
        case .never: "Никогда"
        }
    }

    nonisolated func shows(tabCount: Int) -> Bool {
        switch self {
        case .always: true
        case .multiple: tabCount > 1
        case .never: false
        }
    }
}

/// «Сохранено» над заметкой.
enum SaveStatusMode: String, CaseIterable, Identifiable, Sendable {
    case always
    case briefly
    case never

    var id: Self { self }

    var title: String {
        switch self {
        case .always: "Всегда"
        case .briefly: "Пару секунд после правки"
        case .never: "Никогда"
        }
    }

    /// Сколько «Сохранено» держится после записи в режиме «Пару секунд».
    static let briefDuration: Duration = .seconds(2)
}

/// Полоса прогресса под книгой.
enum ReaderProgressMode: String, CaseIterable, Identifiable, Sendable {
    case always
    case hover

    var id: Self { self }

    var title: String {
        switch self {
        case .always: "Всегда"
        case .hover: "Когда наведена мышь"
        }
    }

    /// На iPhone и iPad без мыши навести нечем, там полоса видна всегда.
    nonisolated func isVisible(isHovered: Bool, hasPointer: Bool) -> Bool {
        switch self {
        case .always: true
        case .hover: isHovered || !hasPointer
        }
    }

    static var defaultMode: ReaderProgressMode {
        #if os(macOS)
        .hover
        #else
        .always
        #endif
    }
}

/// Раздел настроек: что показывать на экране.
struct ScreenOptionsSection: View {
    @AppStorage(ScreenOptions.tabStripKey) private var tabStrip = TabStripMode.multiple
    @AppStorage(ScreenOptions.windowButtonsKey) private var windowButtons = ScreenOptions.windowButtonsDefault
    @AppStorage(ScreenOptions.saveStatusKey) private var saveStatus = SaveStatusMode.briefly
    @AppStorage(ScreenOptions.wordCountKey) private var wordCount = false
    @AppStorage(ScreenOptions.breadcrumbsKey) private var breadcrumbs = false
    @AppStorage(ScreenOptions.readerProgressKey) private var readerProgress = ReaderProgressMode.defaultMode
    @AppStorage(ScreenOptions.gridKey) private var snapToGrid = false

    @AppStorage(ScreenOptions.homeReadingKey) private var homeReading = true
    @AppStorage(ScreenOptions.homeTasksKey) private var homeTasks = true
    @AppStorage(ScreenOptions.homeInboxKey) private var homeInbox = true
    @AppStorage(ScreenOptions.homeRecentKey) private var homeRecent = true

    @AppStorage(ScreenOptions.sidebarRecentKey) private var sidebarRecent = true
    @AppStorage(ScreenOptions.sidebarFavoritesKey) private var sidebarFavorites = true
    @AppStorage(ScreenOptions.sidebarDatabasesKey) private var sidebarDatabases = true
    @AppStorage(ScreenOptions.sidebarFoldersKey) private var sidebarFolders = true

    var body: some View {
        Section {
            Picker("Вкладки", selection: $tabStrip) {
                ForEach(TabStripMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Кнопки «Назад», «Вперёд» и «Разделить экран»", isOn: $windowButtons)
        } header: {
            Text("Окно")
        } footer: {
            Text("Без кнопок работают клавиши: ⌘[ и ⌘] назад и вперёд, ⌘\\ делит экран, ⌘T новая вкладка.")
        }

        Section("Заметка") {
            Picker("«Сохранено»", selection: $saveStatus) {
                ForEach(SaveStatusMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Счётчик слов в углу", isOn: $wordCount)
            Toggle("Путь над заметкой", isOn: $breadcrumbs)
        }

        Section("Экран «Сегодня»") {
            Toggle("Продолжить чтение", isOn: $homeReading)
            Toggle("Задачи на сегодня", isOn: $homeTasks)
            Toggle("Входящие", isOn: $homeInbox)
            Toggle("Недавние заметки", isOn: $homeRecent)
        }

        Section {
            Toggle("Сетка: раскладывать по ячейкам", isOn: $snapToGrid)
            #if os(macOS)
            Picker("Полоса прогресса в книге", selection: $readerProgress) {
                ForEach(ReaderProgressMode.allCases) { Text($0.title).tag($0) }
            }
            #endif
        } header: {
            Text("Библиотека и книги")
        } footer: {
            Text("С сеткой всё в библиотеке встаёт по ячейкам и примагничивается к ним.")
        }

        Section {
            Toggle("Недавние", isOn: $sidebarRecent)
            Toggle("Избранное", isOn: $sidebarFavorites)
            Toggle("Базы данных", isOn: $sidebarDatabases)
            Toggle("Папки", isOn: $sidebarFolders)
        } header: {
            Text("Боковая панель")
        } footer: {
            Text("Видна только в теме «Закат». «Сегодня», «Входящие», «Задачи» и «Библиотека» остаются всегда.")
        }
    }
}
