import Foundation
import LumenStorage
import LumenThemes
@testable import LumenUI
import SwiftUI
import Testing

struct ThemeTests {
    @Test func settingsOfferFiveThemesInOrder() {
        #expect(Theme.all.map(\.name) == ["Закат", "Бумага", "Монохром", "Кабинет", "Дзен"])
        #expect(Set(Theme.all.map(\.id)).count == Theme.all.count, "id тем не повторяются")
    }

    @Test func unknownIdFallsBackToSunset() {
        #expect(Theme.named("paper") == .paper)
        #expect(Theme.named("нет такой") == .sunset)
        #expect(Theme.named("") == .sunset)
    }

    @Test(arguments: Theme.all)
    func everyThemeIsComplete(_ theme: Theme) {
        #expect(!theme.caption.isEmpty)
        #expect(theme.backgroundStops.count >= 2)
        #expect(theme.vividCards.count >= 5, "цвета папок берутся по номеру из яркой палитры")
        #expect((0...1).contains(theme.glowStrength))
        #expect(theme.colorScheme == (theme.isDark ? .dark : .light))
    }

    @Test func lightThemesAreLight() {
        #expect(Theme.paper.colorScheme == .light)
        #expect(Theme.zen.colorScheme == .light)
        #expect(Theme.sunset.colorScheme == .dark)
        #expect(Theme.mono.fontDesign == .monospaced)
    }
}

struct ThemeLayoutTests {
    @Test func eachThemeHasItsOwnLayout() {
        #expect(Theme.mono.layout == .commandLine)
        #expect(Theme.paper.layout == .sectionBar)
        #expect(Theme.study.layout == .rooms)
        #expect(Theme.all.filter { $0.layout.hidesSidebar }.map(\.id) == ["paper", "mono", "study", "zen"])
        #expect(!Theme.sunset.layout.hidesSidebar)
    }

    @Test func paperUnderlinesTheOpenSection() {
        #expect(PaperSection.allCases.map(\.title) == ["Сегодня", "Входящие", "Задачи", "Библиотека"])
        #expect(PaperSection.home.contains(nil))
        #expect(PaperSection.library.contains(.library(UUID())))
        #expect(PaperSection.inbox.contains(.inbox))
        #expect(PaperSection.allCases.allSatisfy { $0.contains($0.item) })
        // Страница или книга открыты поверх разделов: ни один не подчёркнут.
        #expect(!PaperSection.allCases.contains { $0.contains(.page(UUID())) })
        #expect(!PaperSection.allCases.contains { $0.contains(.trash) })
    }

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

    @Test func paperDateLooksLikeANewspaperHeader() {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 7
        components.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(SectionBar.dateTitle(date) == "Суббота, 7 ноября")
    }
}

struct ZenTests {
    @Test func zenHidesEverythingButTheOrb() {
        #expect(Theme.zen.layout == .orb)
        #expect(Theme.zen.layout.hidesSidebar)
        #expect(ZenMenuItem.left + ZenMenuItem.right == ZenMenuItem.allCases)
        #expect(ZenMenuItem.now.isCurrent(nil))
        #expect(ZenMenuItem.books.isCurrent(.library(UUID())))
        #expect(!ZenMenuItem.allCases.contains { $0.isCurrent(.page(UUID())) })
    }

    @Test func breathingFollowsFourTwoSix() {
        #expect(BreathCycle.length == 12)
        #expect(BreathCycle.session == 60)
        #expect(BreathCycle.state(at: 0).phase == .inhale)
        #expect(BreathCycle.state(at: 0).fullness == 0)
        #expect(BreathCycle.state(at: 2).fullness == 0.5)
        #expect(BreathCycle.state(at: 5) == (.hold, 1))
        #expect(BreathCycle.state(at: 9).phase == .exhale)
        #expect(BreathCycle.state(at: 9).fullness == 0.5)
        // Второй круг повторяет первый.
        #expect(BreathCycle.state(at: 14).fullness == BreathCycle.state(at: 2).fullness)
    }

    @Test func breathingCountsDownTheMinute() {
        #expect(BreathingView.remaining(60) == "осталось 1:00")
        #expect(BreathingView.remaining(41.2) == "осталось 0:42")
        #expect(BreathingView.remaining(-3) == "осталось 0:00")
    }

    @Test func zenHomeSpeaksQuietly() {
        #expect(HomeView.waitingThoughts(1) == "1 мысль ждёт во входящих")
        #expect(HomeView.waitingThoughts(3) == "3 мысли ждут во входящих")
        #expect(HomeView.waitingThoughts(11) == "11 мыслей ждут во входящих")
        let evening = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 20))!
        #expect(HomeView.zenMoment(evening) == "СУББОТА · ВЕЧЕР")
    }
}
