import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Книжная полка «Кабинета»: книги стоят корешками, лента-закладка на корешке
/// спускается до того места, докуда дочитано. Нажатие выносит книгу в центр окна, «+» добавляет новую.
struct BookShelf: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void
    var onAdd: () -> Void

    @State private var books: [Source] = []
    /// Книга под мышью: она выдвинута и повёрнута обложкой.
    @State private var hoveredId: UUID?
    @Environment(\.lumenTheme) private var theme
    @Environment(\.bookShowcase) private var showcase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("На полке · лента показывает, докуда дочитано")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(theme.accent.opacity(0.85))
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(books) { book in
                            shelfBook(book)
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
                    .padding(.horizontal, 10)
                    // Место сверху, чтобы вынутая книга не упиралась в край.
                    .padding(.top, 26)
                }
                plank
            }
        }
        .task { await observe() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bookShelf")
    }

    /// Книга на полке. Мышь над корешком: книга выдвигается и поворачивается обложкой.
    /// Нажатие выносит её крупно в центр окна, справа окно со статистикой (`BookShowcase`).
    /// Где витрины нет, нажатие сразу открывает книгу.
    @ViewBuilder
    private func shelfBook(_ book: Source) -> some View {
        let isShown = showcase?.selectedId == book.id
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
                ShelfBook(source: book, attachments: database.attachments, isPulled: hoveredId == book.id)
                    .matchedGeometryEffect(id: book.id, in: showcase.namespace)
            } else {
                ShelfBook(source: book, attachments: database.attachments, isPulled: hoveredId == book.id)
            }
        }
        .buttonStyle(SpineButtonStyle())
        .zIndex(hoveredId == book.id ? 1 : 0)
        .accessibilityLabel(BookSpineStyle.summary(book))
        .accessibilityHint("Показать книгу и статистику чтения")
        .onHover { hovering in
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                if hovering {
                    hoveredId = book.id
                } else if hoveredId == book.id {
                    hoveredId = nil
                }
            }
        }
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
            BookSpine(source: source)
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

/// Корешок книги: цвет, высота и толщина у каждой книги свои, но всегда одни и те же.
struct BookSpine: View {
    let source: Source

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let style = BookSpineStyle(source: source)
        let color = theme.vividCard(style.colorIndex).colors.first ?? theme.accent
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(LinearGradient(
                colors: [color.mix(with: .black, by: 0.35), color.mix(with: .black, by: 0.1), color.mix(with: .black, by: 0.3)],
                startPoint: .leading, endPoint: .trailing
            ))
            // Латунные полоски сверху и снизу, как тиснение на переплёте.
            VStack {
                band
                Spacer()
                band
            }
            .padding(.vertical, 10)
            Text(source.displayTitle)
                .font(.system(size: 11, weight: .semibold, design: .serif))
                .foregroundStyle(theme.accent.mix(with: .white, by: 0.35))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: style.height - 44)
                .rotationEffect(.degrees(90))
                .frame(width: style.width, height: style.height)
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

/// Размеры и цвет корешка из id книги (стабильно между запусками) и длина ленты из прогресса.
struct BookSpineStyle: Equatable {
    var width: CGFloat
    var height: CGFloat
    var colorIndex: Int
    /// Лента от верха корешка до прочитанного места. Нет ленты, пока книгу не открывали.
    var ribbonLength: CGFloat?

    init(source: Source) {
        let seed = Self.seed(source.id)
        height = 128 + CGFloat(seed % 5) * 10
        width = 30 + CGFloat(min(source.displayTitle.count, 36) / 4) + CGFloat(seed / 5 % 3) * 2
        colorIndex = seed / 15 % 5
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
