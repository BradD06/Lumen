import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Меню плитки. На Mac правый щелчок открывает стеклянное меню библиотеки,
/// на iPhone и iPad долгое нажатие показывает системное: оно там родное и с превью.
struct LibraryTileMenu<MenuItems: View>: ViewModifier {
    var onSecondaryClick: (CGPoint) -> Void
    @ViewBuilder var menuItems: () -> MenuItems

    func body(content: Content) -> some View {
        #if os(macOS)
        content.overlay(SecondaryClickCatcher(onSecondaryClick: onSecondaryClick))
        #else
        content.contextMenu { menuItems() }
        #endif
    }
}

/// Щелчок выделяет, двойной открывает (на Mac). На iPhone и iPad касание сразу открывает.
struct TileInteraction<DragGestureType: Gesture>: ViewModifier {
    var onSelect: () -> Void
    var onOpen: () -> Void
    var drag: DragGestureType

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .gesture(drag)
            .onTapGesture(count: 2, perform: onOpen)
            .onTapGesture(perform: onSelect)
        #else
        content
            .gesture(drag)
            .onTapGesture(perform: onOpen)
        #endif
    }
}

/// Кнопки шапки библиотеки: стеклянные, главная закатная.
struct LibraryButtonStyle: ButtonStyle {
    var isOn = false
    var isProminent = false
    @Environment(\.lumenTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isProminent ? theme.vividCard(0).foreground : theme.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background {
                if isProminent {
                    shape.fill(LinearGradient(colors: theme.vividCard(0).colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: (theme.vividCard(0).colors.last ?? .clear).opacity(0.6), radius: 9, y: 6)
                } else {
                    shape.fill(isOn ? theme.accent.opacity(0.3) : theme.cardFill)
                }
            }
            .overlay(shape.strokeBorder(isOn ? theme.accent.opacity(0.6) : theme.cardStroke, lineWidth: 1))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(isProminent ? 0.5 : 0.12), .clear], startPoint: .top, endPoint: .center),
                lineWidth: 1
            ))
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.5))
    }
}
