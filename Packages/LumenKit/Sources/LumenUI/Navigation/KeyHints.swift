import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Клавиатура вместо мыши: ⌘J ставит на всё, что можно нажать, короткие буквы.
/// Набрали буквы, и это нажалось; с ⇧ открывается меню этого места, если оно есть.
/// Esc убирает буквы. Подходит и русская раскладка: важна клавиша, а не буква на ней.
@MainActor
@Observable
final class KeyHintCenter {
    struct Target {
        var frame: CGRect
        var title: String
        var action: @MainActor () -> Void
        /// Меню места (как правый щелчок): ⇧ с буквой.
        var secondary: (@MainActor () -> Void)?
        /// Слой: если открыто что-то поверх экрана (витрина книги, меню), подписывается только оно.
        var layer: Int
        /// Видимая часть списка, в котором лежит место: прокрученное за край не подписывается.
        var clip: CGRect
    }

    struct Labeled: Identifiable {
        var id: UUID
        var label: String
        var frame: CGRect
        var title: String
        var hasMenu: Bool
    }

    /// Буквы видны.
    private(set) var isActive = false
    /// Что уже набрали.
    private(set) var typed = ""
    /// Подписанные места, пока буквы видны.
    private(set) var labeled: [Labeled] = []

    /// Всё, что сейчас можно нажать. Меняется постоянно (прокрутка, раскладка), поэтому не наблюдается.
    @ObservationIgnored private var targets: [UUID: Target] = [:]
    /// Окно в тех же координатах, что и места: что за его краем, не подписывается.
    @ObservationIgnored var bounds: CGRect = .null

    func register(_ id: UUID, frame: CGRect, title: String, layer: Int, clip: CGRect, action: @escaping @MainActor () -> Void, secondary: (@MainActor () -> Void)?) {
        targets[id] = Target(frame: frame, title: title, action: action, secondary: secondary, layer: layer, clip: clip)
    }

    func updateAction(_ id: UUID, title: String, action: @escaping @MainActor () -> Void, secondary: (@MainActor () -> Void)?) {
        targets[id]?.title = title
        targets[id]?.action = action
        targets[id]?.secondary = secondary
    }

    func unregister(_ id: UUID) {
        targets[id] = nil
    }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    /// Ставит буквы на всё, что видно в окне.
    func activate() {
        let top = targets.values.map(\.layer).max() ?? 0
        let visible = targets
            .filter { _, target in
                guard target.layer == top else { return false }
                let frame = target.frame
                // Буква встаёт в левый верхний угол: он и должен быть виден.
                let corner = CGPoint(x: frame.minX + 6, y: frame.minY + 6)
                return frame.width > 2 && frame.height > 2
                    && (bounds.isNull || bounds.contains(corner))
                    && (target.clip.isNull || target.clip.contains(corner))
            }
            .sorted { a, b in Self.readingOrder(a.value.frame, b.value.frame) }
        let labels = Self.labels(count: visible.count)
        labeled = zip(visible, labels).map { pair, label in
            Labeled(id: pair.key, label: label, frame: pair.value.frame, title: pair.value.title, hasMenu: pair.value.secondary != nil)
        }
        typed = ""
        isActive = !labeled.isEmpty
        if labeled.isEmpty {
            NoticeCenter.shared.show("Здесь нечего нажать")
        }
    }

    func deactivate() {
        isActive = false
        typed = ""
        labeled = []
    }

    /// Набрали клавишу (`shifted`: с ⇧, тогда открывается меню места). Возвращает `true`, если клавиша наша.
    @discardableResult
    func type(_ character: Character, shifted: Bool = false) -> Bool {
        guard isActive, let letter = Self.latin(character) else { return false }
        let next = typed + String(letter)
        guard labeled.contains(where: { $0.label.hasPrefix(next) }) else { return true }
        if let match = labeled.first(where: { $0.label == next }) {
            let target = targets[match.id]
            let action = shifted ? (target?.secondary ?? target?.action) : target?.action
            deactivate()
            LumenSounds.play(.navigate)
            action?()
        } else {
            typed = next
        }
        return true
    }

    func deleteBackward() {
        guard isActive else { return }
        if typed.isEmpty {
            deactivate()
        } else {
            typed.removeLast()
        }
    }

    // MARK: Чистая логика

    /// Буквы для подписей: сначала домашний ряд. Хватает одной буквы, пока мест не больше 26,
    /// дальше у всех по две, чтобы ни одна подпись не была началом другой.
    nonisolated static let alphabet = Array("asdfjklghqweruiotypzxcvnmb")

    nonisolated static func labels(count: Int) -> [String] {
        guard count > 0 else { return [] }
        if count <= alphabet.count {
            return alphabet.prefix(count).map { String($0) }
        }
        var result: [String] = []
        outer: for first in alphabet {
            for second in alphabet {
                result.append(String([first, second]))
                if result.count == count { break outer }
            }
        }
        return result
    }

    /// Сверху вниз, слева направо; то, что почти на одной высоте, считается одной строкой.
    nonisolated static func readingOrder(_ a: CGRect, _ b: CGRect) -> Bool {
        let rowA = (a.minY / 24).rounded(.down)
        let rowB = (b.minY / 24).rounded(.down)
        if rowA != rowB { return rowA < rowB }
        return a.minX < b.minX
    }

    /// Буква латиницы на той же клавише: в русской раскладке «ф» это «a».
    nonisolated static func latin(_ character: Character) -> Character? {
        let lower = Character(character.lowercased())
        if alphabet.contains(lower) { return lower }
        let russian: [Character: Character] = [
            "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p",
            "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k", "д": "l",
            "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m",
        ]
        return russian[lower]
    }
}

extension EnvironmentValues {
    @Entry var keyHints: KeyHintCenter?
    /// Что открыто поверх экрана, ставит слой выше: тогда буквы только у него.
    @Entry var keyHintLayer = 0
    /// Видимая часть ближайшего списка (`keyHintClip()`), в координатах окна.
    @Entry var keyHintClip = CGRect.null
}

extension View {
    /// Место, которое можно нажать с клавиатуры: по ⌘J на нём появляется буква.
    /// `secondary`: меню этого места, открывается ⇧ с буквой.
    func keyHint(
        _ title: String,
        secondary: (@MainActor () -> Void)? = nil,
        perform action: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(KeyHintModifier(title: title, action: action, secondary: secondary))
    }
}

private struct KeyHintModifier: ViewModifier {
    let title: String
    let action: @MainActor () -> Void
    let secondary: (@MainActor () -> Void)?

    @Environment(\.keyHints) private var center
    @Environment(\.keyHintLayer) private var layer
    @Environment(\.keyHintClip) private var clip
    @State private var id = UUID()

    func body(content: Content) -> some View {
        // Действие обновляется при каждой перерисовке: в нём могут быть свежие данные строки.
        center?.updateAction(id, title: title, action: action, secondary: secondary)
        return content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                center?.register(id, frame: frame, title: title, layer: layer, clip: clip, action: action, secondary: secondary)
            }
            .onDisappear { center?.unregister(id) }
    }
}

/// Буквы поверх окна, пока включён режим подсказок, и приём клавиш.
struct KeyHintOverlay: View {
    let center: KeyHintCenter

    @Environment(\.lumenTheme) private var theme
    #if os(macOS)
    @State private var monitor: Any?
    #else
    @FocusState private var isFocused: Bool
    #endif

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            if center.isActive {
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(theme.isDark ? 0.25 : 0.08)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { center.deactivate() }
                    ForEach(center.labeled) { item in
                        if item.label.hasPrefix(center.typed) {
                            badge(item)
                                .position(
                                    x: item.frame.minX - origin.x + 10,
                                    y: item.frame.minY - origin.y + 10
                                )
                        }
                    }
                    footer
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 8)
                }
                .transition(.opacity)
                #if os(iOS)
                .focusable()
                .focused($isFocused)
                .onAppear { isFocused = true }
                .onKeyPress(phases: .down) { press in
                    if press.key == .escape {
                        center.deactivate()
                    } else if press.key == .delete {
                        center.deleteBackward()
                    } else if let character = press.characters.first {
                        center.type(character, shifted: press.modifiers.contains(.shift))
                    }
                    return .handled
                }
                #endif
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { center.bounds = $0 }
        .allowsHitTesting(center.isActive)
        .animation(.easeOut(duration: 0.12), value: center.isActive)
        #if os(macOS)
        .onChange(of: center.isActive) { _, active in
            if active { installMonitor() } else { removeMonitor() }
        }
        .onDisappear(perform: removeMonitor)
        #endif
        .accessibilityHidden(!center.isActive)
    }

    private func badge(_ item: KeyHintCenter.Labeled) -> some View {
        let typedCount = center.typed.count
        return HStack(spacing: 0) {
            Text(item.label.prefix(typedCount))
                .opacity(0.45)
            Text(item.label.dropFirst(typedCount))
            if item.hasMenu {
                // Точка: у места есть меню, его открывает ⇧ с буквой.
                Text("·").opacity(0.6)
            }
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .textCase(.uppercase)
        .foregroundStyle(theme.isDark ? Color.black : Color.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .fixedSize()
        .accessibilityLabel("\(item.label): \(item.title)")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ShortcutHint(text: "a…z")
            Text("нажать")
            ShortcutHint(text: "⇧ буква")
            Text("меню")
            ShortcutHint(text: "esc")
            Text("выйти")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.menuFill, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.cardStroke))
    }

    #if os(macOS)
    /// Пока буквы видны, клавиши идут сюда, а не в текст под ними.
    private func installMonitor() {
        guard monitor == nil else { return }
        let center = center
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard center.isActive else { return event }
                let flags = event.modifierFlags.intersection([.command, .control, .option])
                // ⌘J ещё раз: выйти. Остальные сочетания с ⌘ работают как обычно.
                if !flags.isEmpty {
                    if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "j" || event.keyCode == 38 {
                        center.deactivate()
                        return nil
                    }
                    return event
                }
                switch event.keyCode {
                case 53: center.deactivate()
                case 51: center.deleteBackward()
                default:
                    if let character = event.charactersIgnoringModifiers?.first {
                        center.type(character, shifted: event.modifierFlags.contains(.shift))
                    }
                }
                return nil
            }
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    #endif
}

extension View {
    /// Список с прокруткой: то, что уехало за его край, по ⌘J не подписывается.
    func keyHintClip() -> some View {
        modifier(KeyHintClip())
    }
}

private struct KeyHintClip: ViewModifier {
    @State private var rect = CGRect.null

    func body(content: Content) -> some View {
        content
            .environment(\.keyHintClip, rect)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect = $0 }
    }
}

extension View {
    /// Окно (или лист поверх него), в котором работает ⌘J. `center` даёт окно, которому нужен доступ
    /// к буквам из своих команд; листы заводят свой.
    func keyHintHost(_ center: KeyHintCenter? = nil) -> some View {
        modifier(KeyHintHost(external: center))
    }
}

private struct KeyHintHost: ViewModifier {
    let external: KeyHintCenter?
    @State private var own = KeyHintCenter()

    func body(content: Content) -> some View {
        let center = external ?? own
        content
            .overlay {
                KeyHintOverlay(center: center)
                    .ignoresSafeArea()
            }
            .environment(\.keyHints, center)
            .background {
                Button("Нажать с клавиатуры") { center.toggle() }
                    .keyboardShortcut("j", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
    }
}
