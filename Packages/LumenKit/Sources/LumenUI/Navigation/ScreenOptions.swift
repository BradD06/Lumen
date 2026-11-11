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

    /// «Назад / Вперёд» и «Разделить экран» вверху окна. Видны везде: по ним ходят мышью
    /// и на Mac, а ⌘[ ⌘] ⌘\ знают не все. Спрятать можно в настройках.
    static let windowButtonsDefault = true
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
            .keyHint("Вкладки") { tabStrip = tabStrip.cycled }
            Toggle("Кнопки «Назад», «Вперёд» и «Разделить экран»", isOn: $windowButtons)
                .keyHint("Кнопки «Назад», «Вперёд» и «Разделить экран»") { windowButtons.toggle() }
        } header: {
            Text("Окно")
        } footer: {
            Text("Без кнопок работают клавиши: ⌘[ и ⌘] назад и вперёд, ⌘\\ делит экран, ⌘T новая вкладка.")
        }

        Section("Заметка") {
            Picker("«Сохранено»", selection: $saveStatus) {
                ForEach(SaveStatusMode.allCases) { Text($0.title).tag($0) }
            }
            .keyHint("«Сохранено»") { saveStatus = saveStatus.cycled }
            Toggle("Счётчик слов в углу", isOn: $wordCount)
                .keyHint("Счётчик слов в углу") { wordCount.toggle() }
            Toggle("Путь над заметкой", isOn: $breadcrumbs)
                .keyHint("Путь над заметкой") { breadcrumbs.toggle() }
        }

        Section("Экран «Сегодня»") {
            Toggle("Продолжить чтение", isOn: $homeReading)
                .keyHint("Продолжить чтение") { homeReading.toggle() }
            Toggle("Задачи на сегодня", isOn: $homeTasks)
                .keyHint("Задачи на сегодня") { homeTasks.toggle() }
            Toggle("Входящие", isOn: $homeInbox)
                .keyHint("Входящие") { homeInbox.toggle() }
            Toggle("Недавние заметки", isOn: $homeRecent)
                .keyHint("Недавние заметки") { homeRecent.toggle() }
        }

        Section {
            Toggle("Сетка: раскладывать по ячейкам", isOn: $snapToGrid)
                .keyHint("Сетка: раскладывать по ячейкам") { snapToGrid.toggle() }
            #if os(macOS)
            Picker("Полоса прогресса в книге", selection: $readerProgress) {
                ForEach(ReaderProgressMode.allCases) { Text($0.title).tag($0) }
            }
            .keyHint("Полоса прогресса в книге") { readerProgress = readerProgress.cycled }
            #endif
        } header: {
            Text("Библиотека и книги")
        } footer: {
            Text("С сеткой всё в библиотеке встаёт по ячейкам и примагничивается к ним.")
        }

        Section {
            Toggle("Недавние", isOn: $sidebarRecent)
                .keyHint("Недавние") { sidebarRecent.toggle() }
            Toggle("Избранное", isOn: $sidebarFavorites)
                .keyHint("Избранное") { sidebarFavorites.toggle() }
            Toggle("Базы данных", isOn: $sidebarDatabases)
                .keyHint("Базы данных") { sidebarDatabases.toggle() }
            Toggle("Папки", isOn: $sidebarFolders)
                .keyHint("Папки") { sidebarFolders.toggle() }
        } header: {
            Text("Боковая панель")
        } footer: {
            Text("Видна только в теме «Закат». «Сегодня», «Входящие», «Задачи» и «Библиотека» остаются всегда.")
        }
    }
}

extension CaseIterable where Self: Equatable {
    /// Следующий вариант по кругу: так буква ⌘J переключает выбор в настройках.
    var cycled: Self {
        let all = Array(Self.allCases)
        guard let index = all.firstIndex(of: self) else { return self }
        return all[(index + 1) % all.count]
    }
}
