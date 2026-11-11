import Foundation
import LumenCore
import LumenStorage
import LumenThemes
@testable import LumenUI
import SwiftUI
import Testing

struct ThemeTests {
    /// Вид один, «Кабинет», у него шесть цветовых схем. Основная, «Изумруд», стоит в окружении по умолчанию.
    @Test func emeraldIsTheDefaultScheme() {
        #expect(Theme.study.name == "Изумруд")
        #expect(Theme.study.fontDesign == .serif)
        #expect(Theme.study.colorScheme == .dark)
        #expect(EnvironmentValues().lumenTheme == .study)
        #expect(Theme.schemes.first == .study)
    }

    @Test func sixSchemesWithUniqueIds() {
        #expect(Theme.schemes.map(\.name) == ["Изумруд", "Полночь", "Вишня", "Орех", "Сумерки", "Лён"])
        #expect(Set(Theme.schemes.map(\.id)).count == Theme.schemes.count)
        #expect(Theme.schemes.filter { !$0.isDark }.map(\.id) == ["linen"], "одна светлая схема")
    }

    @Test(arguments: Theme.schemes)
    func everySchemeIsComplete(_ theme: Theme) {
        #expect(theme.backgroundStops.count >= 2)
        #expect(theme.vividCards.count >= 5, "цвета папок берутся по номеру из яркой палитры")
        #expect((0...1).contains(theme.glowStrength))
        #expect(!theme.wallColors.isEmpty, "за стеклом виден шкаф")
        #expect(!theme.caption.isEmpty)
        #expect(theme.fontDesign == .serif)
        // Текст на латунной кнопке читается.
        #expect(ThemeContrast.ratio(theme.onAccent, theme.accent) >= 4.5, "\(theme.name): onAccent")
        #expect(ThemeContrast.ratio(theme.textPrimary, theme.backgroundStops[0]) >= 7, "\(theme.name): текст")
    }

    @Test func unknownSchemeFallsBackToEmerald() {
        #expect(Theme.named("midnight") == .midnight)
        #expect(Theme.named("sunset") == .study, "старые темы удалены")
        #expect(Theme.named("") == .study)
    }
}

struct DaylightScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute))!
    }

    @Test func periodsFollowTheClock() {
        #expect(DaylightSchedule.Period.at(hour: 6) == .night)
        #expect(DaylightSchedule.Period.at(hour: 7) == .day)
        #expect(DaylightSchedule.Period.at(hour: 18) == .day)
        #expect(DaylightSchedule.Period.at(hour: 19) == .evening)
        #expect(DaylightSchedule.Period.at(hour: 22) == .evening)
        #expect(DaylightSchedule.Period.at(hour: 23) == .night)
        #expect(DaylightSchedule.Period.at(hour: 0) == .night)
    }

    @Test func defaultScheduleIsLinenEmeraldMidnight() {
        let schedule = DaylightSchedule()
        #expect(schedule.theme(at: date(hour: 10, minute: 30), calendar: calendar) == .linen)
        #expect(schedule.theme(at: date(hour: 19, minute: 40), calendar: calendar) == .study)
        #expect(schedule.theme(at: date(hour: 23, minute: 15), calendar: calendar) == .midnight)
    }

    @Test func nextChangeIsTheNextPeriodStart() {
        #expect(DaylightSchedule.nextChange(after: date(hour: 10), calendar: calendar) == date(hour: 19))
        #expect(DaylightSchedule.nextChange(after: date(hour: 20), calendar: calendar) == date(hour: 23))
        let morning = calendar.date(byAdding: .day, value: 1, to: date(hour: 7))!
        #expect(DaylightSchedule.nextChange(after: date(hour: 23, minute: 30), calendar: calendar) == morning)
    }
}

struct StudyRoomTests {
    @Test func studyLightsTheOpenRoom() {
        #expect(StudyRoom.allCases.map(\.title) == ["Стол", "Полка", "Доска", "Записки", "Дела", "Архив"])
        #expect(StudyRoom.allCases.allSatisfy { $0.contains($0.item) })
        #expect(StudyRoom.desk.contains(nil))
        #expect(StudyRoom.shelf.contains(.library(UUID())))
        #expect(StudyRoom.archive.item == .trash)
        #expect(StudyRoom.board.item == .board)
        #expect(!StudyRoom.allCases.contains { $0.contains(.source(UUID(), highlight: nil)) })
        // Каждое открытое место горит не больше чем на одной табличке.
        let places: [SidebarItem?] = [nil, .home, .inbox, .tasks, .library(nil), .board, .trash, .page(UUID())]
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
