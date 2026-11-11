import LumenThemes
import SwiftUI

/// Настольная лампа, которая стоит на полке главного экрана (и только там).
/// Нажали: комнаты и вкладки уходят, вокруг темнеет, запускается таймер учёбы.
/// Ещё раз нажали, и свет вернулся.
struct ShelfLamp: View {
    private let focus = FocusModeState.shared
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let isLit = focus.isLampLit
        Button { focus.toggleLamp() } label: {
            ZStack(alignment: .top) {
                // Свет из-под абажура падает на полку.
                if isLit {
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [theme.glow.opacity(0.75), theme.glow.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 46
                        ))
                        .frame(width: 96, height: 60)
                        .offset(y: 22)
                        .blur(radius: 6)
                }
                VStack(spacing: 0) {
                    LampShade()
                        .fill(LinearGradient(
                            colors: [theme.accent.mix(with: .white, by: 0.15), theme.accent.mix(with: .black, by: 0.35)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay(LampShade().stroke(theme.accent, lineWidth: 1))
                        .frame(width: 46, height: 24)
                        .overlay(alignment: .bottom) {
                            Circle()
                                .fill(isLit ? Color(hex: 0xFFF3C8) : theme.accent.mix(with: .black, by: 0.5))
                                .frame(width: 9, height: 9)
                                .shadow(color: isLit ? theme.glow : .clear, radius: 8)
                                .offset(y: 4)
                        }
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: 3, height: 34)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [theme.accent.mix(with: .white, by: 0.2), theme.accent.mix(with: .black, by: 0.3)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 34, height: 6)
                }
            }
            .frame(width: 56, height: 70, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isLit ? "Погасить лампу: свет и комнаты вернутся" : "Лампа: режим фокуса и таймер учёбы на \(FocusModeState.studyMinutes) минут")
        .keyHint(isLit ? "Погасить лампу" : "Лампа") { focus.toggleLamp() }
        .accessibilityLabel(isLit ? "Погасить лампу" : "Включить лампу")
        .accessibilityHint("Режим фокуса и таймер учёбы")
        .accessibilityIdentifier("shelfLamp")
    }
}

/// Абажур: трапеция, узкая сверху.
private struct LampShade: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.26, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Пока горит лампа: края окна темнеют, внизу стеклянная капсула с таймером и кнопкой «Погасить».
struct LampLight: View {
    private let focus = FocusModeState.shared
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if focus.isLampLit {
            ZStack(alignment: .bottom) {
                GeometryReader { proxy in
                    let radius = max(proxy.size.width, proxy.size.height) * 0.75
                    RadialGradient(
                        colors: [.clear, .clear, .black.opacity(theme.isDark ? 0.6 : 0.35)],
                        center: .center, startRadius: 0, endRadius: radius
                    )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                timerCapsule
                    .padding(.bottom, 18)
            }
            .transition(.opacity)
        }
    }

    private var timerCapsule: some View {
        HStack(spacing: 14) {
            if let end = focus.timerEnd {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(FocusModeState.remaining(until: end, now: context.date))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .fontDesign(.default)
                }
                Text("фокус · \(FocusModeState.studyMinutes) минут")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            } else {
                Text("Лампа горит")
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            Button("Погасить") { focus.toggleLamp() }
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(theme.accent, in: Capsule())
                .keyHint("Погасить") { focus.toggleLamp() }
        }
        .foregroundStyle(theme.textPrimary)
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(height: 42)
        .lumenGlass(Capsule(), prominent: true)
    }
}
