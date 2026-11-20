import Foundation
import LumenCore
import LumenStorage
import LumenThemes
@testable import LumenUI
import SwiftUI
import Testing

struct ThemeTests {
    /// Вид один, «Остров»: светлая и тёмная тема, по умолчанию как в системе.
    @Test func islandHasLightAndDarkThemes() {
        #expect(Theme.schemes.map(\.name) == ["Светлая", "Тёмная"])
        #expect(Theme.light.colorScheme == .light)
        #expect(Theme.dark.colorScheme == .dark)
        #expect(EnvironmentValues().lumenTheme == .light)
        #expect(Set(Theme.schemes.map(\.id)).count == Theme.schemes.count)
    }

    @Test func appearanceModeFollowsTheSystem() {
        #expect(AppearanceMode.allCases.map(\.title) == ["Как в системе", "Светлая", "Тёмная"])
        #expect(AppearanceMode.system.theme(system: .light) == .light)
        #expect(AppearanceMode.system.theme(system: .dark) == .dark)
        #expect(AppearanceMode.light.theme(system: .dark) == .light)
        #expect(AppearanceMode.dark.theme(system: .light) == .dark)
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode(rawValue: "study") == nil, "старые схемы «Кабинета» не читаются как режим")
    }

    @Test(arguments: Theme.schemes)
    func everyThemeIsComplete(_ theme: Theme) {
        #expect(theme.backgroundStops.count >= 2)
        #expect(Set(theme.backgroundStops).count == 1, "фон ровный, без пятен")
        #expect(theme.glowStrength == 0)
        #expect(theme.vividCards.count >= 3, "цвета папок берутся по номеру из яркой палитры")
        #expect(!theme.caption.isEmpty)
        #expect(theme.fontDesign == .default)
        // На акценте только значки и короткие жирные подписи: хватает контраста крупного текста.
        #expect(ThemeContrast.ratio(theme.onAccent, theme.accent) >= 3, "\(theme.name): onAccent")
        #expect(ThemeContrast.ratio(theme.onInk, theme.ink) >= 7, "\(theme.name): кнопка плеера")
        #expect(ThemeContrast.ratio(theme.textPrimary, theme.background) >= 7, "\(theme.name): текст")
        #expect(ThemeContrast.ratio(theme.textPrimary, theme.sheet) >= 7, "\(theme.name): текст на листе")
        #expect(ThemeContrast.ratio(theme.textSecondary, theme.sheet) >= 3, "\(theme.name): второй текст")
    }

    @Test func coverTintKeepsTheSheets() {
        let tinted = Theme.dark.tinted(by: Color(hex: 0x3A7BD5))
        #expect(tinted.sheet == Theme.dark.sheet)
        #expect(tinted.textPrimary == Theme.dark.textPrimary)
        #expect(tinted.background != Theme.dark.background)
        #expect(Set(tinted.backgroundStops).count == 1)
    }
}

struct StudyRoomTests {
    @Test func studyLightsTheOpenRoom() {
        #expect(StudyRoom.allCases.map(\.title) == ["Стол", "Полка", "Записки", "Дела", "Архив"])
        #expect(StudyRoom.allCases.allSatisfy { $0.contains($0.item) })
        #expect(StudyRoom.desk.contains(nil))
        #expect(StudyRoom.shelf.contains(.library(UUID())))
        #expect(StudyRoom.archive.item == .trash)
        #expect(!StudyRoom.allCases.contains { $0.contains(.source(UUID(), highlight: nil)) })
        // Каждое открытое место горит не больше чем на одной табличке.
        let places: [SidebarItem?] = [nil, .home, .inbox, .tasks, .library(nil), .reading, .trash, .page(UUID())]
        for place in places {
            #expect(StudyRoom.allCases.filter { $0.contains(place) }.count <= 1)
        }
    }

    @Test func studyPlaquesCountNotesAndArchive() {
        var snapshot = SidebarSnapshot.empty
        snapshot.inboxCount = 3
        snapshot.trashCount = 2
        #expect(StudyRoom.notes.count(in: snapshot) == 3)
        #expect(StudyRoom.archive.count(in: snapshot) == 2)
        #expect(StudyRoom.desk.count(in: snapshot) == 0)
    }
}

struct FolderContrastTests {
    /// Тёмная папка сливалась бы с фоном: каждая папка заметна на фоне темы.
    @Test(arguments: Theme.schemes)
    func everyFolderStandsOutFromTheBackground(_ theme: Theme) {
        guard let background = theme.backgroundStops.first else { return }
        let minimum = ThemeContrast.luminance(background) > 0.5 ? 1.3 : ThemeContrast.minimumRatio
        for index in 0..<(Folder.colorCount - 1) {
            for color in theme.folderCard(index).colors {
                let ratio = ThemeContrast.ratio(color, background)
                #expect(ratio >= minimum - 0.01, "папка \(index): контраст \(ratio)")
            }
        }
    }

    @Test func brightFoldersKeepTheirColor() {
        // Сиреневая папка и так видна на светлом фоне: её цвет не трогают.
        let card = Theme.light.vividCard(0)
        #expect(Theme.light.folderCard(0).colors == card.colors)
    }

    @Test func iconPickerTakesOneSymbol() {
        #expect(IconPicker.firstSymbol("  🚀🔥 ") == "🚀")
        #expect(IconPicker.firstSymbol("👩‍💻 код") == "👩‍💻")
        #expect(IconPicker.firstSymbol("   ") == nil)
    }
}
