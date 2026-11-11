import LumenCore
import LumenThemes
import SwiftUI

/// Лист заметки: бумага пропорций A4 с полями, внизу название и номер листа.
/// Лист не короче A4 при своей ширине; если текста больше, чем помещается, он вытягивается,
/// а внутри видна просьба разложить лишнее по листам.
struct SheetPaper<Content: View, MenuItems: View>: View {
    let number: Int
    let title: String
    var isPinned = false
    /// Лист заполнен: внизу подпись «лист заполнен».
    var isFull = false
    var isCompact = false
    @ViewBuilder var content: Content
    @ViewBuilder var menu: MenuItems

    @State private var width = CGFloat(NoteSheets.width)
    @Environment(\.lumenTheme) private var theme

    /// Поля листа: на узком листе (iPhone, панель рядом с книгой) уже, как у уменьшенного A4.
    private var margin: CGFloat {
        isCompact ? 14 : max(16, min(CGFloat(NoteSheets.margin), width * 0.07))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 18)
            footer
        }
        .padding(.horizontal, margin)
        .padding(.top, margin)
        .padding(.bottom, max(margin * 0.5, 10))
        .frame(maxWidth: .infinity, minHeight: width * 297 / 210, alignment: .topLeading)
        .background(paper)
        .overlay(alignment: .topTrailing) {
            if isPinned {
                pin.offset(x: -22, y: -7)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Лист \(number)")
        .accessibilityIdentifier("note-sheet-\(number)")
    }

    private var paper: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return shape
            .fill(theme.cardFill)
            .overlay(shape.fill(theme.contrast.opacity(0.035)))
            .overlay(shape.strokeBorder(theme.cardStroke, lineWidth: 1))
            .shadow(color: .black.opacity(theme.shadowOpacity * 0.9), radius: 18, y: 12)
    }

    /// Внизу листа, как в тетради: название заметки, «лист заполнен» и номер листа с меню листа.
    private var footer: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 8)
            if isFull {
                Text("лист заполнен")
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
            }
            SwiftUI.Menu {
                menu
            } label: {
                HStack(spacing: 3) {
                    if isPinned {
                        Image(systemName: "pin.fill").font(.caption2)
                    }
                    Text("\(number)").monospacedDigit().fontWeight(.semibold)
                    Image(systemName: "ellipsis").font(.caption2)
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.contrast.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Лист \(number): приколоть к полке, переставить, удалить")
            .accessibilityLabel("Меню листа \(number)")
        }
        .font(.caption)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.contrast.opacity(0.1)).frame(height: 1)
        }
    }

    /// Латунная кнопка, которой лист приколот к полке.
    private var pin: some View {
        Circle()
            .fill(RadialGradient(
                colors: [theme.accent.mix(with: .white, by: 0.45), theme.accent.mix(with: .black, by: 0.35)],
                center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 9
            ))
            .frame(width: 14, height: 14)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 2)
            .accessibilityLabel("Приколот к полке")
    }
}

/// Под последним листом: «Добавить лист» и подсказка, куда он ляжет.
struct AddSheetBar: View {
    let sheetCount: Int
    let isLastFull: Bool
    var onAdd: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Button(action: add) {
                Label("Добавить лист", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(theme.accent.opacity(isLastFull ? 0.22 : 0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.accent.opacity(0.45), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyHint("Добавить лист", perform: add)
            .accessibilityIdentifier("add-sheet")
            Text(hint)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var hint: String {
        if isLastFull {
            return "Лист закончился. Новый лист ляжет в эту же заметку, после листа \(sheetCount)."
        }
        if sheetCount == 1 {
            return "Когда листов станет два, заметка встанет на полку папкой с листами."
        }
        return "Новый лист ляжет после листа \(sheetCount)."
    }

    private func add() {
        LumenSounds.play(.addSheet)
        onAdd()
    }
}

/// Миниатюры листов слева от заметки на широком экране: нажатие прокручивает к листу.
struct SheetRail: View {
    let count: Int
    let current: Int
    let pinned: Int?
    var onSelect: (Int) -> Void
    var onAdd: () -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                Text("Листы")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.textSecondary)
                ForEach(0..<count, id: \.self) { index in
                    thumb(index)
                }
                Button(action: onAdd) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: 46, height: 65)
                        .overlay {
                            Image(systemName: "plus").foregroundStyle(theme.accent)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Добавить лист")
                .accessibilityLabel("Добавить лист")
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
        }
        .frame(width: 74)
        .fixedSize(horizontal: false, vertical: true)
        .lumenCard(padding: 0)
    }

    private func thumb(_ index: Int) -> some View {
        let isCurrent = index == current
        return Button {
            onSelect(index)
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.contrast.opacity(isCurrent ? 0.14 : 0.07))
                    .frame(width: 46, height: 65)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(0..<6, id: \.self) { line in
                                Capsule()
                                    .fill(theme.contrast.opacity(0.18))
                                    .frame(width: line % 3 == 0 ? 22 : 32, height: 2)
                            }
                        }
                        .padding(7)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(theme.accent.opacity(isCurrent ? 0.9 : 0), lineWidth: 1.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if pinned == index {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.accent)
                                .padding(3)
                        }
                    }
                Text("\(index + 1)")
                    .font(.caption2.weight(isCurrent ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? theme.accent : theme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Лист \(index + 1)")
        .accessibilityLabel("Лист \(index + 1)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Номера листов в шапке панели заметок рядом с книгой: «1 2 3 +».
struct SheetPager: View {
    let count: Int
    let current: Int
    var onSelect: (Int) -> Void
    var onAdd: () -> Void

    @Environment(\.lumenTheme) private var theme

    /// Сколько номеров помещается: дальше вместо них «3 / 12».
    private static let maxNumbers = 5

    var body: some View {
        HStack(spacing: 3) {
            if count <= Self.maxNumbers {
                ForEach(0..<count, id: \.self) { index in
                    number(index)
                }
            } else {
                Button {
                    onSelect(max(current - 1, 0))
                } label: {
                    Image(systemName: "chevron.left").font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .disabled(current == 0)
                .accessibilityLabel("Лист выше")
                Text("\(current + 1) / \(count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                Button {
                    onSelect(min(current + 1, count - 1))
                } label: {
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .disabled(current >= count - 1)
                .accessibilityLabel("Лист ниже")
            }
            Button {
                LumenSounds.play(.addSheet)
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 24, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.textSecondary.opacity(0.35)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Добавить лист")
            .accessibilityLabel("Добавить лист")
        }
        .foregroundStyle(theme.textSecondary)
    }

    private func number(_ index: Int) -> some View {
        let isCurrent = index == current
        return Button {
            onSelect(index)
        } label: {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? theme.textPrimary : theme.textSecondary)
                .frame(minWidth: 24, minHeight: 24)
                .background(theme.accent.opacity(isCurrent ? 0.22 : 0), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.textSecondary.opacity(isCurrent ? 0 : 0.35)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Лист \(index + 1)")
        .accessibilityLabel("Лист \(index + 1)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Куда прокрутить заметку, когда её открывают с полки: на приколотый лист.
@MainActor
enum SheetJump {
    private static var pending: [UUID: Int] = [:]

    static func request(_ pageId: UUID, sheet: Int) {
        pending[pageId] = sheet
    }

    static func take(_ pageId: UUID) -> Int? {
        pending.removeValue(forKey: pageId)
    }
}
