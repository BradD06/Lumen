import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Заметки на полке «Кабинета». Заметка из нескольких листов стоит рядом с книгами
/// папкой-регистратором: чем больше листов, тем она толще. Одиночные листы лежат стопкой
/// в стеклянном лотке в конце полки. Приколотый лист висит под доской на латунной кнопке.

/// Бумага листов на полке: светлая, в цвет латуни темы, чтобы её было видно в любой схеме.
enum ShelfPaper {
    static func fill(_ theme: Theme) -> Color { theme.accent.mix(with: .white, by: 0.8) }
    static func ink(_ theme: Theme) -> Color { theme.accent.mix(with: .black, by: 0.82) }
}

/// Действия с заметкой на полке: открыть, приколоть, переставить, убрать.
@MainActor
struct ShelfNoteActions {
    let database: AppDatabase
    var open: (UUID) -> Void

    /// Открывает заметку; если указан лист, заметка прокрутится к нему.
    func show(_ note: ShelfNote, sheet: Int? = nil) {
        if let sheet { SheetJump.request(note.id, sheet: sheet) }
        LumenSounds.play(.navigate)
        open(note.id)
    }

    func pin(_ note: ShelfNote, sheet: Int?) {
        let database = database
        Task {
            await NoticeCenter.shared.attempt("Не удалось приколоть лист к полке") {
                try await database.setShelfPin(note.id, sheet: sheet)
            }
        }
    }

    func move(_ note: ShelfNote, to shelf: Folder?) {
        let database = database
        Task {
            await NoticeCenter.shared.attempt("Не удалось переставить заметку") {
                try await database.movePage(note.id, toFolder: shelf?.id)
            }
            LumenSounds.play(.dropIntoFolder)
        }
    }

    func trash(_ note: ShelfNote) {
        NoticeCenter.shared.moveToTrash(.page(note.id), in: database)
    }
}

/// Меню заметки на полке.
struct ShelfNoteMenu: View {
    let note: ShelfNote
    let others: [ShelfGroup]
    let actions: ShelfNoteActions

    var body: some View {
        Button("Открыть", systemImage: "doc.text") { actions.show(note) }
        if note.shelfPin != nil {
            Button("Открепить от полки", systemImage: "pin.slash") { actions.pin(note, sheet: nil) }
        } else {
            Button(note.isFolder ? "Приколоть первый лист к полке" : "Приколоть к полке", systemImage: "pin") {
                LumenSounds.play(.toggle)
                actions.pin(note, sheet: 0)
            }
        }
        if !others.isEmpty {
            Menu("Переставить на полку", systemImage: "books.vertical") {
                ForEach(others) { target in
                    Button(target.shelf?.displayName ?? "Общая полка") { actions.move(note, to: target.shelf) }
                }
            }
        }
        Divider()
        Button("Убрать в корзину", systemImage: "trash", role: .destructive) { actions.trash(note) }
    }
}

/// Папка-регистратор с листами заметки: окошко с названием вдоль корешка, число листов, кольцо.
struct SheetBinder: View {
    let note: ShelfNote

    @Environment(\.lumenTheme) private var theme

    static let height: CGFloat = 150

    /// Толщина по числу листов: от тонкой папки на два листа до пухлой на сорок.
    static func width(sheets: Int) -> CGFloat {
        26 + CGFloat(min(max(sheets, 2), 40) - 2) * 0.9
    }

    var body: some View {
        let width = Self.width(sheets: note.sheetCount)
        let card = theme.vividCard(Int(note.id.uuid.2))
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(LinearGradient(colors: card.colors, startPoint: .top, endPoint: .bottom))
            // Мраморный картон: светлые и тёмные пятна.
            shape.fill(.black.opacity(0.12)).mask(Marble())
            shape.fill(LinearGradient(
                colors: [.black.opacity(0.35), .white.opacity(0.1), .black.opacity(0.05), .black.opacity(0.35)],
                startPoint: .leading, endPoint: .trailing
            ))
            VStack(spacing: 6) {
                Circle()
                    .fill(theme.accent.mix(with: .white, by: 0.3))
                    .frame(width: 5, height: 5)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                    .padding(.top, 6)
                // Окошко с названием вдоль корешка.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ShelfPaper.fill(theme))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                    .frame(width: max(width - 10, 16), height: 78)
                    .overlay {
                        Text(note.displayTitle)
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .foregroundStyle(ShelfPaper.ink(theme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: 72)
                            .rotationEffect(.degrees(90))
                    }
                Text("\(note.sheetCount) л.")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(card.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                // Кольцо, за которое папку снимают с полки.
                Circle()
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .frame(width: min(width * 0.62, 22), height: min(width * 0.62, 22))
                    .padding(.bottom, 12)
            }
        }
        .frame(width: width, height: Self.height)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Папка «\(note.displayTitle)», \(ShelfNote.sheetsLabel(note.sheetCount))")
    }
}

/// Пятна мраморного картона: всегда одни и те же.
private struct Marble: View {
    var body: some View {
        Canvas { context, size in
            var seed = 7
            for _ in 0..<14 {
                seed = (seed * 1_103 + 12_345) % 65_536
                let x = CGFloat(seed % 100) / 100 * size.width
                let y = CGFloat(seed / 100 % 100) / 100 * size.height
                let radius = CGFloat(3 + seed % 6)
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(.black))
            }
        }
    }
}

/// Стеклянный лоток в конце полки: одиночные листы лежат в нём стопкой, сверху последний.
/// Нажатие показывает список листов.
struct SheetTray: View {
    let notes: [ShelfNote]
    let others: [ShelfGroup]
    let actions: ShelfNoteActions

    @State private var isOpen = false
    @Environment(\.lumenTheme) private var theme

    private var newest: ShelfNote? { notes.max { $0.updatedAt < $1.updatedAt } }

    var body: some View {
        Button {
            LumenSounds.play(.tap)
            isOpen = true
        } label: {
            tray
        }
        .buttonStyle(.plain)
        .help("Одиночные листы: \(notes.count)")
        .keyHint("Лоток с листами") { isOpen = true }
        .accessibilityLabel("Лоток с одиночными листами, \(ShelfNote.sheetsLabel(notes.count))")
        .accessibilityIdentifier("sheet-tray")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            list
                .keyHintHost()
                .presentationCompactAdaptation(.popover)
        }
    }

    private var tray: some View {
        ZStack(alignment: .bottom) {
            // Стопка листов: нижние чуть повёрнуты, верхний с названием.
            ForEach(0..<min(notes.count, 3), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ShelfPaper.fill(theme))
                    .frame(width: 118, height: 8)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -1.5 : 1.2))
                    .offset(y: -26 - CGFloat(index) * 4)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
            if let newest {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ShelfPaper.fill(theme))
                    .frame(width: 122, height: 30)
                    .overlay(alignment: .leading) {
                        Text(newest.displayTitle)
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .italic()
                            .foregroundStyle(ShelfPaper.ink(theme))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                    }
                    .rotation3DEffect(.degrees(40), axis: (x: 1, y: 0, z: 0), anchor: .bottom)
                    .offset(y: -36)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(
                    colors: [theme.accent.opacity(0.45), theme.accent.opacity(0.2)],
                    startPoint: .top, endPoint: .bottom
                ))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.accent.opacity(0.6), lineWidth: 1))
                .frame(width: 140, height: 28)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 5)
        }
        .frame(width: 150, height: 82, alignment: .bottom)
        .overlay(alignment: .topTrailing) {
            Text(ShelfNote.sheetsLabel(notes.count))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.accent.opacity(0.85), in: Capsule())
                .offset(x: 6, y: -4)
        }
        .contentShape(Rectangle())
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Одиночные листы")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(notes.sorted { $0.updatedAt > $1.updatedAt }) { note in
                        Button {
                            isOpen = false
                            actions.show(note)
                        } label: {
                            HStack(spacing: 8) {
                                Text(note.icon ?? (note.isNotebook ? "✍️" : "📄"))
                                Text(note.displayTitle)
                                    .lineLimit(1)
                                    .foregroundStyle(theme.textPrimary)
                                Spacer(minLength: 8)
                                if note.shelfPin != nil {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyHint(note.displayTitle) {
                            isOpen = false
                            actions.show(note)
                        }
                        .contextMenu {
                            ShelfNoteMenu(note: note, others: others, actions: actions)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .keyHintClip()
            .frame(maxHeight: 360)
        }
        .frame(width: 280)
    }
}

/// Листы, приколотые к краю полки: висят под доской, как записки.
struct PinnedSheetsRow: View {
    let notes: [ShelfNote]
    let others: [ShelfGroup]
    let actions: ShelfNoteActions

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 26) {
                ForEach(notes) { note in
                    pinned(note)
                }
            }
            .padding(.horizontal, ShelfLayout.leading + 30)
            .padding(.top, 2)
            .padding(.bottom, 14)
        }
        .keyHintClip()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Приколотые листы")
    }

    private func pinned(_ note: ShelfNote) -> some View {
        let tilt = BookSpineStyle.seed(note.id) % 2 == 0 ? -3.0 : 2.5
        let sheet = note.pinnedSheet ?? 0
        return Button {
            actions.show(note, sheet: sheet)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(ShelfPaper.ink(theme))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if note.isFolder {
                    Text("лист \(sheet + 1) из \(note.sheetCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ShelfPaper.ink(theme).opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .frame(width: 116, height: 86, alignment: .topLeading)
            .background(ShelfPaper.fill(theme), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay(alignment: .top) {
                Circle()
                    .fill(RadialGradient(
                        colors: [theme.accent.mix(with: .white, by: 0.45), theme.accent.mix(with: .black, by: 0.35)],
                        center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 8
                    ))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
                    .offset(y: -5)
            }
            .shadow(color: .black.opacity(0.4), radius: 8, y: 6)
            .rotationEffect(.degrees(tilt), anchor: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Открыть «\(note.displayTitle)»")
        .keyHint(note.displayTitle) { actions.show(note, sheet: sheet) }
        .contextMenu {
            ShelfNoteMenu(note: note, others: others, actions: actions)
        }
        .accessibilityLabel("Приколотый лист «\(note.displayTitle)»")
    }
}
