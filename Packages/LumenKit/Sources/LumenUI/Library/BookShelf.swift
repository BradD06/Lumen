import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Книжная полка «Кабинета»: книги стоят корешками, лента-закладка на корешке
/// спускается до того места, докуда дочитано. Нажатие выносит книгу в центр окна, «+» добавляет новую.
/// Книги можно перетаскивать в свой порядок, кнопки над полкой сортируют их иначе.
struct BookShelf: View {
    static let sortKey = "shelf.sort"

    let database: AppDatabase
    var onOpen: (UUID) -> Void
    var onAdd: () -> Void

    @State private var books: [Source] = []
    /// Книга под мышью: она выдвинута и повёрнута обложкой.
    @State private var hoveredId: UUID?
    /// Книга, которую тащат по полке.
    @State private var draggingId: UUID?
    /// Порядок, пока книгу тащат и пока база не вернула новый.
    @State private var dragOrder: [UUID]?
    @AppStorage(BookShelf.sortKey) private var sort = ShelfSort.recent
    @Environment(\.lumenTheme) private var theme
    @Environment(\.bookShowcase) private var showcase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    caption("На полке · лента показывает, докуда дочитано")
                    caption("На полке")
                }
                Spacer(minLength: 0)
                ShelfSortPicker(sort: sort, onPick: choose)
                    .layoutPriority(1)
            }
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    let shown = shownBooks
                    HStack(alignment: .bottom, spacing: ShelfLayout.spacing) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, book in
                            shelfBook(book, index: index, count: shown.count)
                        }
                        addSpine
                        if books.isEmpty {
                            Text("Добавьте первую книгу, и она встанет на полку")
                                .font(.callout.italic())
                                .foregroundStyle(theme.textSecondary)
                                .padding(.leading, 12)
                                .padding(.bottom, 16)
                        }
                    }
                    .padding(.horizontal, ShelfLayout.leading)
                    // Место сверху, чтобы вынутая книга не упиралась в край.
                    .padding(.top, 26)
                    .onDrop(of: [.text], delegate: ShelfDropDelegate(
                        draggingId: $draggingId,
                        order: $dragOrder,
                        shown: shown.map(\.id),
                        widths: Dictionary(uniqueKeysWithValues: shown.map { ($0.id, BookSpineStyle(source: $0).width) }),
                        onDrop: arrange
                    ))
                }
                plank
            }
        }
        .task { await observe() }
        .onChange(of: books) {
            // База вернула новый порядок: дальше полка показывает его.
            if draggingId == nil { dragOrder = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bookShelf")
    }

    /// Книга на полке. Мышь над корешком: книга выдвигается и поворачивается обложкой.
    /// Нажатие выносит её крупно в центр окна, справа окно со статистикой (`BookShowcase`).
    /// Где витрины нет, нажатие сразу открывает книгу.
    @ViewBuilder
    private func shelfBook(_ book: Source, index: Int, count: Int) -> some View {
        let isShown = showcase?.selectedId == book.id
        let isDragged = draggingId == book.id && dragOrder != nil
        Button {
            if let showcase {
                hoveredId = nil
                showcase.show(book)
            } else {
                onOpen(book.id)
            }
        } label: {
            if isShown, showcase != nil {
                // Книга сейчас в центре окна: на полке пустое место под неё.
                Color.clear.frame(width: BookSpineStyle(source: book).width, height: BookSpineStyle(source: book).height)
            } else if let showcase {
                ShelfBook(source: book, attachments: database.attachments, isPulled: hoveredId == book.id && !isDragging)
                    .matchedGeometryEffect(id: book.id, in: showcase.namespace)
            } else {
                ShelfBook(source: book, attachments: database.attachments, isPulled: hoveredId == book.id && !isDragging)
            }
        }
        .buttonStyle(SpineButtonStyle())
        // Там, где встанет перетаскиваемая книга, виден её бледный след.
        .opacity(isDragged ? 0.35 : 1)
        .onDrag {
            hoveredId = nil
            draggingId = book.id
            dragOrder = shownBooks.map(\.id)
            return NSItemProvider(object: book.id.uuidString as NSString)
        } preview: {
            BookSpine(source: book, attachments: database.attachments)
        }
        .contextMenu {
            Button("Поставить левее", systemImage: "arrow.left") { nudge(book.id, by: -1) }
                .disabled(index == 0)
            Button("Поставить правее", systemImage: "arrow.right") { nudge(book.id, by: 1) }
                .disabled(index == count - 1)
        }
        .zIndex(hoveredId == book.id ? 1 : 0)
        .accessibilityLabel(BookSpineStyle.summary(book))
        .accessibilityHint("Показать книгу и статистику чтения")
        .onHover { hovering in
            // Пока книгу тащат, книги под мышью не выдвигаются и не поворачиваются.
            if isDragging {
                hoveredId = nil
                return
            }
            // Перетаскивание бросили за полкой: забываем его.
            draggingId = nil
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                if hovering {
                    hoveredId = book.id
                } else if hoveredId == book.id {
                    hoveredId = nil
                }
            }
        }
    }

    /// Книгу сейчас тащат. На Mac это видно по зажатой кнопке мыши: если перетаскивание
    /// бросили за полкой, полка об этом не узнаёт, а кнопка уже отпущена.
    private var isDragging: Bool {
        guard draggingId != nil else { return false }
        #if os(macOS)
        return NSEvent.pressedMouseButtons != 0
        #else
        return dragOrder != nil
        #endif
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.4)
            .lineLimit(1)
            .foregroundStyle(theme.accent.opacity(0.85))
    }

    /// Книги в том порядке, в каком стоят: пока книгу тащат, в порядке перетаскивания.
    private var shownBooks: [Source] {
        let sorted = sort.sorted(books)
        guard let dragOrder else { return sorted }
        let byId = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let placed = dragOrder.compactMap { byId[$0] }
        let placedIds = Set(dragOrder)
        return placed + sorted.filter { !placedIds.contains($0.id) }
    }

    private func choose(_ option: ShelfSort) {
        withAnimation(.snappy) {
            dragOrder = nil
            sort = option
        }
    }

    /// Книгу поставили на новое место: полка переходит на свой порядок и запоминает его.
    private func arrange(_ order: [UUID]) {
        withAnimation(.snappy) {
            dragOrder = order
            sort = .custom
        }
        Task {
            do {
                try await database.arrangeShelf(order)
            } catch {
                lumenLog.error("Shelf arrange failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// «Левее» и «Правее» из меню книги: то же, что перетащить её на одно место.
    private func nudge(_ id: UUID, by step: Int) {
        var order = shownBooks.map(\.id)
        guard let index = order.firstIndex(of: id), order.indices.contains(index + step) else { return }
        order.swapAt(index, index + step)
        arrange(order)
    }

    /// Пустое место на полке с «+»: добавить книгу или файл.
    private var addSpine: some View {
        Button(action: onAdd) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: 34, height: 120)
                .overlay {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .help("Поставить на полку книгу или файл")
        .accessibilityLabel("Добавить книгу")
    }

    /// Доска полки: тёмное дерево с латунной кромкой.
    private var plank: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [theme.accent.mix(with: .black, by: 0.45), theme.accent.mix(with: .black, by: 0.7)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(height: 10)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.accent.opacity(0.7)).frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try ShelfQuery.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                books = value
            }
        } catch {
            lumenLog.error("Shelf observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Книга на полке: корешок, а взятая в руки (`isPulled`) выдвигается вверх
/// и поворачивается обложкой к читателю, как будто её сняли с полки.
struct ShelfBook: View {
    let source: Source
    let attachments: AttachmentStore
    var isPulled: Bool

    var body: some View {
        let style = BookSpineStyle(source: source)
        let coverWidth = style.coverWidth
        ZStack {
            BookSpine(source: source, attachments: attachments)
                .rotation3DEffect(.degrees(isPulled ? -90 : 0), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.6)
                .opacity(isPulled ? 0 : 1)
            SourceCoverArt(source: source, attachments: attachments, width: coverWidth, height: style.height)
                .rotation3DEffect(.degrees(isPulled ? 0 : 90), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
                .opacity(isPulled ? 1 : 0)
                .shadow(color: .black.opacity(isPulled ? 0.45 : 0), radius: 10, y: 8)
        }
        .frame(width: isPulled ? coverWidth : style.width, height: style.height)
        .offset(y: isPulled ? -20 : 0)
        .scaleEffect(isPulled ? 1.04 : 1, anchor: .bottom)
    }
}

/// Корешок книги: высота и толщина у каждой книги свои, но всегда одни и те же.
/// Если у книги есть картинка обложки, корешок сделан из её середины;
/// без картинки он того же цвета, что и нарисованная обложка.
struct BookSpine: View {
    let source: Source
    var attachments: AttachmentStore?

    @Environment(\.lumenTheme) private var theme

    private var hasCoverImage: Bool { source.cover != nil && attachments != nil }

    var body: some View {
        let style = BookSpineStyle(source: source)
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack(alignment: .top) {
            face(style)
                .frame(width: style.width, height: style.height)
                .clipShape(shape)
            // Скруглённый переплёт: края темнее середины.
            shape.fill(LinearGradient(
                colors: [.black.opacity(0.45), .white.opacity(0.08), .black.opacity(0.12), .black.opacity(0.4)],
                startPoint: .leading, endPoint: .trailing
            ))
            // Латунные полоски сверху и снизу, как тиснение на переплёте.
            VStack {
                band
                Spacer()
                band
            }
            .padding(.vertical, 10)
            title(style)
            if let length = style.ribbonLength {
                RibbonShape()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xB23A32), Color(hex: 0x7E221D)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: 6, height: length)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 5)
                    .offset(y: -3)
            }
        }
        .frame(width: style.width, height: style.height)
        .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
    }

    @ViewBuilder
    private func face(_ style: BookSpineStyle) -> some View {
        if let cover = source.cover, let attachments {
            // Середина обложки той же высоты, что корешок: по краю картинки обычно пусто.
            AttachmentImage(name: cover, attachments: attachments, contentMode: .fill)
                .frame(width: style.coverWidth, height: style.height)
                .frame(width: style.width, height: style.height, alignment: .center)
                .clipped()
        } else {
            LinearGradient(colors: coverCard.colors, startPoint: .top, endPoint: .bottom)
        }
    }

    /// Те же цвета, что у нарисованной обложки (`SourceCoverArt`): повернул книгу, цвет тот же.
    private var coverCard: Theme.VividCard { theme.vividCard(Int(source.id.uuid.1)) }

    private func title(_ style: BookSpineStyle) -> some View {
        Text(source.displayTitle)
            .font(.system(size: 11, weight: .semibold, design: .serif))
            .foregroundStyle(hasCoverImage ? .white : coverCard.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            // На картинке обложки название читается на тёмной плашке.
            .background(.black.opacity(hasCoverImage ? 0.5 : 0), in: Capsule())
            .frame(width: style.height - 40)
            .rotationEffect(.degrees(90))
            .frame(width: style.width, height: style.height)
    }

    private var band: some View {
        Rectangle()
            .fill(theme.accent.opacity(0.65))
            .frame(height: 1.5)
            .padding(.horizontal, 3)
    }
}

/// Лента-закладка с вырезом «ласточкин хвост» внизу.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch = min(rect.width * 0.8, rect.height * 0.3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Размеры корешка из id книги (стабильно между запусками) и длина ленты из прогресса.
/// Цвет корешок берёт у обложки.
struct BookSpineStyle: Equatable {
    var width: CGFloat
    var height: CGFloat
    /// Лента от верха корешка до прочитанного места. Нет ленты, пока книгу не открывали.
    var ribbonLength: CGFloat?

    init(source: Source) {
        let seed = Self.seed(source.id)
        height = 128 + CGFloat(seed % 5) * 10
        width = 30 + CGFloat(min(source.displayTitle.count, 36) / 4) + CGFloat(seed / 5 % 3) * 2
        ribbonLength = Self.ribbon(progress: source.progress, opened: source.lastOpenedAt != nil, height: height)
    }

    /// Ширина обложки, когда книгу повернули лицом: пропорции обычной книги.
    var coverWidth: CGFloat { (height * 0.68).rounded() }

    /// Сумма байтов id: в отличие от `hashValue` не меняется между запусками.
    static func seed(_ id: UUID) -> Int {
        withUnsafeBytes(of: id.uuid) { bytes in bytes.reduce(0) { $0 + Int($1) } }
    }

    static func ribbon(progress: Double, opened: Bool, height: CGFloat) -> CGFloat? {
        guard opened else { return nil }
        let share = min(max(progress, 0), 1)
        // Даже только начатая книга показывает кончик ленты, дочитанная свисает до самого низа.
        return max(14, CGFloat(share) * height)
    }

    static func summary(_ source: Source) -> String {
        guard source.lastOpenedAt != nil else { return "\(source.displayTitle), ещё не открывали" }
        return "\(source.displayTitle), прочитано \(Int((source.progress * 100).rounded()))%"
    }
}

/// Корешок чуть выдвигается с полки при нажатии.
private struct SpineButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? -6 : 0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Отступы полки: по ним видно, на какое место встанет перетаскиваемая книга.
enum ShelfLayout {
    nonisolated static let leading: CGFloat = 10
    nonisolated static let spacing: CGFloat = 3

    /// Куда встанет книга, отпущенная в точке `x`, среди остальных книг шириной `widths`.
    /// Считается по полке без перетаскиваемой книги, поэтому место не скачет туда-сюда.
    nonisolated static func insertionIndex(x: CGFloat, widths: [CGFloat]) -> Int {
        var start = leading
        for (index, width) in widths.enumerated() {
            if x < start + width / 2 { return index }
            start += width + spacing
        }
        return widths.count
    }
}

/// Перетаскивание книги по полке: книги расступаются, отпустили на полке, порядок сохраняется.
/// Увели книгу с полки: всё возвращается как было.
struct ShelfDropDelegate: DropDelegate {
    @Binding var draggingId: UUID?
    @Binding var order: [UUID]?
    let shown: [UUID]
    let widths: [UUID: CGFloat]
    var onDrop: ([UUID]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingId != nil && info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        move(to: info.location.x)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingId != nil else { return nil }
        move(to: info.location.x)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.snappy) { order = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggingId != nil else { return false }
        let final = move(to: info.location.x)
        draggingId = nil
        onDrop(final)
        return true
    }

    @discardableResult
    private func move(to x: CGFloat) -> [UUID] {
        let current = order ?? shown
        guard let id = draggingId else { return current }
        var others = current.filter { $0 != id }
        let index = ShelfLayout.insertionIndex(x: x, widths: others.map { widths[$0] ?? 30 })
        others.insert(id, at: min(index, others.count))
        if others != current {
            withAnimation(.snappy) { order = others }
        }
        return others
    }
}

/// Кнопки порядка над полкой; где места мало, они складываются в одно меню.
struct ShelfSortPicker: View {
    let sort: ShelfSort
    var onPick: (ShelfSort) -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(ShelfSort.allCases) { option in
                    capsule(option)
                }
            }
            Menu {
                Picker("Порядок на полке", selection: Binding(get: { sort }, set: onPick)) {
                    ForEach(ShelfSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(sort.title, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .fixedSize()
            .accessibilityIdentifier("shelf-sort-menu")
        }
    }

    private func capsule(_ option: ShelfSort) -> some View {
        let isOn = option == sort
        return Button {
            onPick(option)
        } label: {
            Text(option.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(isOn ? theme.textPrimary : theme.textSecondary)
                .background(Capsule().fill(theme.accent.opacity(isOn ? 0.24 : 0)))
                .overlay(Capsule().strokeBorder(theme.accent.opacity(isOn ? 0.65 : 0.25), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(option.hint)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("shelf-sort-\(option.rawValue)")
    }
}

extension ShelfSort {
    var title: String {
        switch self {
        case .custom: "Свой"
        case .recent: "Недавние"
        case .title: "Название"
        case .author: "Автор"
        case .progress: "Прочитано"
        case .added: "Новые"
        }
    }

    var hint: String {
        switch self {
        case .custom: "Как расставили сами: перетащите книгу на новое место"
        case .recent: "Что читали недавно, слева"
        case .title: "По названию, от А до Я"
        case .author: "По автору, от А до Я"
        case .progress: "Больше всего прочитано, слева"
        case .added: "Недавно добавленные, слева"
        }
    }
}
