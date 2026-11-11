import Foundation
import LumenCore
import LumenStorage
import LumenThemes
@testable import LumenUI
import SwiftUI
import Testing

struct ThemeTests {
    /// Тема одна, «Кабинет»: она же стоит в окружении по умолчанию.
    @Test func studyIsTheOnlyTheme() {
        #expect(Theme.study.name == "Кабинет")
        #expect(Theme.study.fontDesign == .serif)
        #expect(Theme.study.colorScheme == .dark)
        #expect(EnvironmentValues().lumenTheme == .study)
    }

    @Test func studyIsComplete() {
        let theme = Theme.study
        #expect(theme.backgroundStops.count >= 2)
        #expect(theme.vividCards.count >= 5, "цвета папок берутся по номеру из яркой палитры")
        #expect((0...1).contains(theme.glowStrength))
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
        let places: [SidebarItem?] = [nil, .home, .inbox, .tasks, .library(nil), .trash, .page(UUID())]
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
    /// Тёмная папка сливалась бы с фоном: каждая папка заметна на зелёной стене кабинета.
    @Test func everyFolderStandsOutFromTheBackground() {
        let theme = Theme.study
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
        // Пергаментная папка и так видна: её цвет не трогают.
        let card = Theme.study.vividCard(0)
        #expect(Theme.study.folderCard(0).colors == card.colors)
    }

    @Test func iconPickerTakesOneSymbol() {
        #expect(IconPicker.firstSymbol("  🚀🔥 ") == "🚀")
        #expect(IconPicker.firstSymbol("👩‍💻 код") == "👩‍💻")
        #expect(IconPicker.firstSymbol("   ") == nil)
    }
}
