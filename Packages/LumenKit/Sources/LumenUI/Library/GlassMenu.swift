import LumenCore
import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Строка или украшение стеклянного меню.
enum GlassMenuEntry {
    case action(GlassMenuAction)
    case divider
    /// Мелкая серая подпись над группой строк.
    case label(String)
    /// Ряд цветов папки: выбранный обведён белым кольцом.
    case swatches(selected: Int, onPick: (Int) -> Void)
}

struct GlassMenuAction {
    var title: String
    var systemImage: String
    /// Подсказка клавиши справа, например «⏎».
    var shortcut: String?
    var isDestructive = false
    var perform: () -> Void
}

/// Контекстное меню библиотеки по макету: тёмное матовое стекло, иконки слева, подсказки
/// клавиш справа, цвет папки рядом кружков вместо подменю. Стрелки двигают подсветку,
/// Return выбирает, Escape закрывает.
struct GlassMenu: View {
    let entries: [GlassMenuEntry]
    var onDismiss: () -> Void

    static let width: CGFloat = 236

    @State private var highlighted: Int?
    @FocusState private var isFocused: Bool
    @Environment(\.lumenTheme) private var theme

    /// Индексы строк-действий: по ним ходят стрелки.
    private var actionIndices: [Int] {
        entries.indices.filter { if case .action = entries[$0] { true } else { false } }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(entries.indices, id: \.self) { index in
                row(index)
            }
        }
        .padding(6)
        .frame(width: Self.width)
        .background {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color(red: 47 / 255, green: 33 / 255, blue: 54 / 255).opacity(0.86))
        }
        .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .overlay(
            // Светлая кромка сверху, как у стекла.
            shape.inset(by: 1).stroke(
                LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)),
                lineWidth: 1
            )
        )
        .clipShape(shape)
        .shadow(color: .black.opacity(0.75), radius: 25, y: 12)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
        .onKeyPress(.return) {
            // Без подсветки Return выбирает первую строку, «Открыть».
            guard let index = highlighted ?? actionIndices.first, case .action(let action) = entries[index] else {
                return .ignored
            }
            choose(action)
            return .handled
        }
        .onKeyPress(.delete) {
            guard let action = destructiveAction else { return .ignored }
            choose(action)
            return .handled
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private func row(_ index: Int) -> some View {
        switch entries[index] {
        case .action(let action):
            Button {
                choose(action)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 16)
                        .foregroundStyle(action.isDestructive ? Self.danger : theme.textPrimary.opacity(0.75))
                    Text(action.title)
                        .font(.system(size: 13))
                        .foregroundStyle(action.isDestructive ? Self.danger : theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let shortcut = action.shortcut {
                        Text(shortcut)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textPrimary.opacity(0.5))
                    }
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.accent.opacity(highlighted == index ? 0.28 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { highlighted = index } else if highlighted == index { highlighted = nil }
            }
        case .divider:
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
        case .label(let text):
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textPrimary.opacity(0.55))
                .padding(.horizontal, 9)
                .padding(.top, 6)
                .padding(.bottom, 2)
        case .swatches(let selected, let onPick):
            HStack(spacing: 7) {
                ForEach(FolderPalette.names.indices, id: \.self) { color in
                    Button {
                        LumenSounds.play(.tap)
                        onPick(color)
                    } label: {
                        FolderSwatch(color: color, isSelected: color == selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(FolderPalette.name(color) + (color == selected ? ", выбран" : ""))
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    private static let danger = Color(hex: 0xFFB3A3)

    private var destructiveAction: GlassMenuAction? {
        for entry in entries {
            if case .action(let action) = entry, action.isDestructive { return action }
        }
        return nil
    }

    private func choose(_ action: GlassMenuAction) {
        LumenSounds.play(.tap)
        onDismiss()
        action.perform()
    }

    private func moveHighlight(by step: Int) {
        let actions = actionIndices
        guard !actions.isEmpty else { return }
        guard let current = highlighted, let position = actions.firstIndex(of: current) else {
            highlighted = step > 0 ? actions.first : actions.last
            return
        }
        highlighted = actions[(position + step + actions.count) % actions.count]
    }
}

/// Квадратик цвета папки в меню.
private struct FolderSwatch: View {
    let color: Int
    let isSelected: Bool

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let fill: AnyShapeStyle = color == Folder.glassColor
            ? AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xFFF3EC).opacity(0.3), Color(hex: 0xFFF3EC).opacity(0.1)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            : AnyShapeStyle(LinearGradient(colors: theme.vividCard(color).colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        shape
            .fill(fill)
            .overlay(shape.inset(by: 0.5).stroke(
                LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center),
                lineWidth: 1
            ))
            .frame(width: 22, height: 22)
            .padding(2)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(hex: 0xFFF3EC), lineWidth: 2)
                }
            }
    }
}

#if os(macOS)
/// Ловит правый щелчок и щелчок с Control поверх SwiftUI-вида, остальные щелчки пропускает
/// насквозь. Точка приходит в координатах вида, начало слева сверху.
struct SecondaryClickCatcher: NSViewRepresentable {
    var onSecondaryClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onSecondaryClick = onSecondaryClick
    }

    final class CatcherView: NSView {
        var onSecondaryClick: ((CGPoint) -> Void)?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, isSecondary(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            report(event)
        }

        override func mouseDown(with event: NSEvent) {
            if isSecondary(event) {
                report(event)
            } else {
                super.mouseDown(with: event)
            }
        }

        private func isSecondary(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }

        private func report(_ event: NSEvent) {
            onSecondaryClick?(convert(event.locationInWindow, from: nil))
        }
    }
}
#endif
