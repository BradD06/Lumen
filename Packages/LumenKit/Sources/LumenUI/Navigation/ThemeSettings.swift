import LumenThemes
import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Применяет оформление «Кабинета»: цвета, тёмный режим, шрифт с засечками.
    /// Вешается один раз на корень окна, всё внутри (и листы) берёт тему из окружения.
    public func lumenThemed() -> some View {
        modifier(LumenThemeHost())
    }
}

extension View {
    /// Верхняя полоса окна (заголовок, кнопки) в цвет кабинета, а не системная серая.
    func themedToolbar() -> some View {
        modifier(ThemedToolbar())
    }
}

private struct ThemedToolbar: ViewModifier {
    @Environment(\.lumenTheme) private var theme

    func body(content: Content) -> some View {
        let fill = theme.backgroundStops.first ?? .clear
        #if os(macOS)
        content
            .toolbarBackground(fill, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbarColorScheme(theme.colorScheme, for: .windowToolbar)
        #else
        content
            .toolbarBackground(fill, for: .navigationBar, .tabBar)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar, .tabBar)
        #endif
    }
}

private struct LumenThemeHost: ViewModifier {
    @AppStorage(Theme.storageKey) private var schemeID = Theme.study.id
    @AppStorage(DaylightSchedule.enabledKey) private var followsDaylight = false
    @AppStorage(DaylightSchedule.dayKey) private var dayID = Theme.linen.id
    @AppStorage(DaylightSchedule.eveningKey) private var eveningID = Theme.study.id
    @AppStorage(DaylightSchedule.nightKey) private var nightID = Theme.midnight.id
    /// Текущее время для «света по времени суток»; обновляется, когда меняется часть суток.
    @State private var now = Date()

    private var theme: Theme {
        guard followsDaylight else { return Theme.named(schemeID) }
        return DaylightSchedule(dayID: dayID, eveningID: eveningID, nightID: nightID).theme(at: now)
    }

    func body(content: Content) -> some View {
        let theme = self.theme
        return content
            .environment(\.lumenTheme, theme)
            .fontDesign(theme.fontDesign)
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
            #if os(macOS)
            .background(WindowChrome(color: theme.backgroundStops.first ?? .clear))
            #endif
            .task { AppIcon.resetToPrimary() }
            .task(id: followsDaylight) {
                guard followsDaylight else { return }
                while !Task.isCancelled {
                    now = Date()
                    // Спим до смены части суток, но не дольше 15 минут: компьютер мог уснуть.
                    let wait = min(DaylightSchedule.nextChange(after: now).timeIntervalSince(now) + 1, 15 * 60)
                    try? await Task.sleep(for: .seconds(max(wait, 1)))
                }
            }
    }
}

/// Раздел «Оформление» в Настройках: шесть цветовых схем и «свет по времени суток».
struct AppearanceSection: View {
    @AppStorage(Theme.storageKey) private var schemeID = Theme.study.id
    @AppStorage(DaylightSchedule.enabledKey) private var followsDaylight = false
    @AppStorage(DaylightSchedule.dayKey) private var dayID = Theme.linen.id
    @AppStorage(DaylightSchedule.eveningKey) private var eveningID = Theme.study.id
    @AppStorage(DaylightSchedule.nightKey) private var nightID = Theme.midnight.id

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(Theme.schemes) { scheme in
                    SchemeSwatch(scheme: scheme, isSelected: !followsDaylight && scheme.id == schemeID) {
                        schemeID = scheme.id
                        followsDaylight = false
                    }
                    .keyHint("Схема \(scheme.name)") {
                        schemeID = scheme.id
                        followsDaylight = false
                    }
                }
            }
            .padding(.vertical, 4)
            Toggle("Менять по времени суток", isOn: $followsDaylight)
                .keyHint("По времени суток") { followsDaylight.toggle() }
            if followsDaylight {
                schemePicker(.day, selection: $dayID)
                schemePicker(.evening, selection: $eveningID)
                schemePicker(.night, selection: $nightID)
            }
        } header: {
            Text("Оформление")
        } footer: {
            Text(followsDaylight
                ? "День с 7:00, вечер с 19:00, ночь с 23:00."
                : "Можно включить смену схемы по времени суток: например, днём светлый «Лён», а ночью «Полночь».")
        }
    }

    private func schemePicker(_ period: DaylightSchedule.Period, selection: Binding<String>) -> some View {
        Picker(period.title, selection: selection) {
            ForEach(Theme.schemes) { scheme in
                Text(scheme.name).tag(scheme.id)
            }
        }
    }
}

/// Плитка схемы: кусочек её фона, полка из трёх корешков и латунная полоска.
private struct SchemeSwatch: View {
    @Environment(\.lumenTheme) private var current
    let scheme: Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: scheme.backgroundStops, startPoint: .top, endPoint: .bottom)
                    RadialGradient(
                        colors: [scheme.glow.opacity(scheme.glowStrength), .clear],
                        center: .topTrailing, startRadius: 0, endRadius: 70
                    )
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(scheme.wallColors.prefix(4).enumerated()), id: \.offset) { index, color in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(color)
                                .frame(width: 9, height: CGFloat(30 + (index * 7) % 12))
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.bottom, 6)
                    Rectangle()
                        .fill(scheme.accent.opacity(0.8))
                        .frame(height: 3)
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(scheme.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(current.textPrimary)
                Text(scheme.caption)
                    .font(.caption2)
                    .foregroundStyle(current.textSecondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? current.accent : current.cardStroke, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Схема \(scheme.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Раньше значок менялся вместе с темой. Тем больше нет, и значок «Кабинета» стал основным:
/// на iPhone и iPad снимаем запасной значок, если его когда-то поставили.
@MainActor
enum AppIcon {
    static func resetToPrimary() {
        #if os(iOS)
        let application = UIApplication.shared
        guard application.supportsAlternateIcons, application.alternateIconName != nil else { return }
        Task {
            try? await application.setAlternateIconName(nil)
        }
        #endif
    }
}
