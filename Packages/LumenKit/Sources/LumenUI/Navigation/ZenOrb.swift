import LumenThemes
import SwiftUI

/// Вся навигация «Дзена» в одной точке внизу окна. Точка медленно дышит в ритме
/// «вдох 4 с, пауза 2 с, выдох 6 с». Нажатие раскрывает тихое меню из слов по обе стороны.
struct ZenOrb: View {
    let selection: SidebarItem?
    var onSelect: (SidebarItem) -> Void
    var onCreate: () -> Void
    var onSearch: () -> Void
    var onBreathe: () -> Void
    var onSettings: () -> Void

    @State private var isOpen = false
    @State private var isHovered = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if isOpen {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        items(ZenMenuItem.left)
                        orb
                        items(ZenMenuItem.right)
                    }
                    // iPhone: места сверху, действия под ними, точка внизу.
                    VStack(spacing: 2) {
                        HStack(spacing: 0) { items(ZenMenuItem.left) }
                        HStack(spacing: 0) { items(ZenMenuItem.right) }
                        orb
                    }
                    VStack(spacing: 2) {
                        items(ZenMenuItem.left + ZenMenuItem.right)
                        orb
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(theme.menuFill)
                        .shadow(color: .black.opacity(theme.shadowOpacity), radius: 18, y: 6)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                orb
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: isOpen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zenOrb")
    }

    /// Сама точка: шалфейный кружок и мягкий ореол, который дышит.
    private var orb: some View {
        Button {
            isOpen.toggle()
        } label: {
            ZStack {
                BreathingHalo(color: theme.accent, size: 46)
                Circle()
                    .fill(RadialGradient(
                        colors: [theme.accent.mix(with: .white, by: 0.35), theme.accent],
                        center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 14
                    ))
                    .frame(width: isHovered || isOpen ? 22 : 18, height: isHovered || isOpen ? 22 : 18)
                    .shadow(color: theme.accent.opacity(0.45), radius: 6)
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .keyboardShortcut(isOpen ? .cancelAction : nil)
        .help(isOpen ? "Спрятать меню" : "Меню: перейти, создать, найти")
        .keyHint(isOpen ? "Спрятать меню" : "Меню") { isOpen.toggle() }
        .accessibilityLabel(isOpen ? "Спрятать меню" : "Меню")
    }

    private func items(_ list: [ZenMenuItem]) -> some View {
        ForEach(list) { item in
            let isCurrent = item.isCurrent(selection)
            Button {
                isOpen = false
                run(item)
            } label: {
                VStack(spacing: 3) {
                    Text(item.title)
                        .font(.callout)
                        .foregroundStyle(isCurrent ? theme.accent : theme.textPrimary.opacity(0.8))
                        .fixedSize()
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 4, height: 4)
                        .opacity(isCurrent ? 1 : 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyHint(item.title) {
                isOpen = false
                run(item)
            }
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityIdentifier("zen.\(item.rawValue)")
        }
    }

    private func run(_ item: ZenMenuItem) {
        switch item {
        case .now: onSelect(.home)
        case .inbox: onSelect(.inbox)
        case .tasks: onSelect(.tasks)
        case .books: onSelect(.library(nil))
        case .create: onCreate()
        case .search: onSearch()
        case .breathe: onBreathe()
        case .settings: onSettings()
        }
    }
}

/// Слова в меню точки. Слева места, справа действия.
enum ZenMenuItem: String, CaseIterable, Identifiable {
    case now, inbox, tasks, books, create, search, breathe, settings

    static let left: [ZenMenuItem] = [.now, .inbox, .tasks, .books]
    static let right: [ZenMenuItem] = [.create, .search, .breathe, .settings]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Сейчас"
        case .inbox: "Входящие"
        case .tasks: "Задачи"
        case .books: "Книги"
        case .create: "Записать"
        case .search: "Найти"
        case .breathe: "Дыхание"
        case .settings: "Настройки"
        }
    }

    func isCurrent(_ selection: SidebarItem?) -> Bool {
        switch (self, selection) {
        case (.now, .home), (.now, nil), (.inbox, .inbox), (.tasks, .tasks), (.books, .library): true
        default: false
        }
    }
}

/// Ритм дыхания «Дзена»: вдох 4 секунды, пауза 2, выдох 6. Один круг 12 секунд.
enum BreathCycle {
    enum Phase: Equatable {
        case inhale, hold, exhale

        var title: String {
            switch self {
            case .inhale: "вдох"
            case .hold: "пауза"
            case .exhale: "выдох"
            }
        }
    }

    static let inhale = 4.0
    static let hold = 2.0
    static let exhale = 6.0
    static let length = inhale + hold + exhale
    /// Минута тишины: пять кругов.
    static let session = length * 5

    /// Фаза и насколько круг «наполнен» (0…1) через `seconds` от начала.
    static func state(at seconds: Double) -> (phase: Phase, fullness: Double) {
        let t = seconds.truncatingRemainder(dividingBy: length)
        if t < inhale { return (.inhale, smooth(t / inhale)) }
        if t < inhale + hold { return (.hold, 1) }
        return (.exhale, 1 - smooth((t - inhale - hold) / exhale))
    }

    /// Плавный разгон и торможение, как у настоящего вдоха.
    private static func smooth(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// Мягкий ореол, который растёт на вдохе и опадает на выдохе.
struct BreathingHalo: View {
    var color: Color
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let fullness = reduceMotion ? 0.5 : BreathCycle.state(at: context.date.timeIntervalSinceReferenceDate).fullness
            Circle()
                .fill(color.opacity(0.10 + 0.12 * fullness))
                .frame(width: size * (0.55 + 0.45 * fullness), height: size * (0.55 + 0.45 * fullness))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Изюминка «Дзена»: минута дыхания на весь экран. Круг растёт на вдохе и опадает на выдохе,
/// под ним подсказка. Через минуту можно вернуться; Esc возвращает сразу.
struct BreathingView: View {
    var onClose: () -> Void

    @State private var start = Date.now
    @Environment(\.lumenTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let isDone = elapsed >= BreathCycle.session
            let state = BreathCycle.state(at: elapsed)
            VStack(spacing: 34) {
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(theme.accent.opacity(0.25), lineWidth: 1)
                        .frame(width: 260, height: 260)
                    Circle()
                        .fill(RadialGradient(
                            colors: [theme.accent.opacity(0.45), theme.accent.opacity(0.12)],
                            center: .center, startRadius: 4, endRadius: 130
                        ))
                        .frame(width: 260, height: 260)
                        .scaleEffect(isDone ? 0.5 : (reduceMotion ? 0.7 : 0.35 + 0.65 * state.fullness))
                }
                Text(isDone ? "Готово. Можно возвращаться" : state.phase.title)
                    .font(.system(size: 30, weight: .light, design: .serif))
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.6), value: state.phase)
                Text(isDone ? " " : Self.remaining(BreathCycle.session - elapsed))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button(isDone ? "Вернуться" : "Хватит", action: onClose)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(theme.accent)
                    .keyboardShortcut(.cancelAction)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ThemedBackground())
        .onAppear { start = .now }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("breathing")
    }

    /// «осталось 0:42».
    nonisolated static func remaining(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return "осталось \(total / 60):\(String(format: "%02d", total % 60))"
    }
}
