import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Связь полки с витриной: общее пространство для перелёта книги и какая книга сейчас вынута.
struct BookShowcaseContext {
    var namespace: Namespace.ID
    var selectedId: UUID?
    var show: @MainActor (Source) -> Void
}

extension EnvironmentValues {
    @Entry var bookShowcase: BookShowcaseContext? = nil
}

extension View {
    /// Экран, на котором стоит полка, показывает поверх себя витрину вынутой книги.
    func bookShowcaseHost(database: AppDatabase, onOpenBook: @escaping (UUID) -> Void) -> some View {
        modifier(BookShowcaseHost(database: database, onOpenBook: onOpenBook))
    }
}

private struct BookShowcaseHost: ViewModifier {
    let database: AppDatabase
    var onOpenBook: (UUID) -> Void

    @Namespace private var namespace
    @State private var selected: Source?
    @Environment(\.appActions) private var appActions

    func body(content: Content) -> some View {
        content
            .environment(\.bookShowcase, BookShowcaseContext(
                namespace: namespace,
                selectedId: selected?.id,
                show: { book in
                    withAnimation(.spring(duration: 0.55, bounce: 0.18)) { selected = book }
                }
            ))
            .overlay {
                if let book = selected {
                    BookShowcase(
                        book: book,
                        database: database,
                        namespace: namespace,
                        onClose: close,
                        onOpenBook: {
                            close()
                            onOpenBook(book.id)
                        },
                        onOpenPage: { id in
                            close()
                            appActions.open(.page(id))
                        },
                        onOpenDashboard: {
                            close()
                            appActions.open(.sourceInfo(book.id))
                        }
                    )
                }
            }
    }

    private func close() {
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) { selected = nil }
    }
}

/// Книга, вынутая с полки: крупная обложка чуть левее центра, справа полупрозрачное окно
/// со статистикой чтения. Вместе они стоят посередине окна. Нажатие на фон или Esc возвращает книгу на полку.
struct BookShowcase: View {
    let book: Source
    let database: AppDatabase
    let namespace: Namespace.ID
    var onClose: () -> Void
    var onOpenBook: () -> Void
    var onOpenPage: (UUID) -> Void
    var onOpenDashboard: () -> Void

    @State private var appeared = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let layout = BookShowcaseLayout(size: geo.size)
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(theme.isDark ? 0.45 : 0.25))
                    .opacity(appeared ? 1 : 0)
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                Group {
                    if layout.isSideBySide {
                        HStack(alignment: .center, spacing: BookShowcaseLayout.gap) {
                            cover(layout)
                            stats
                        }
                    } else {
                        VStack(spacing: 20) {
                            cover(layout)
                            stats
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(20)
                .opacity(appeared ? 1 : 0)
                .accessibilityLabel("Вернуть книгу на полку")
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.05)) { appeared = true }
        }
        .accessibilityIdentifier("bookShowcase")
    }

    /// Крупная обложка. Прилетает с полки и доворачивается лицом.
    private func cover(_ layout: BookShowcaseLayout) -> some View {
        Button(action: onOpenBook) {
            SourceCoverArt(source: book, attachments: database.attachments, width: layout.coverWidth, height: layout.coverHeight)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: book.id, in: namespace)
        .rotation3DEffect(.degrees(appeared ? 0 : 35), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .help("Читать")
        .accessibilityLabel("Читать «\(book.displayTitle)»")
    }

    private var stats: some View {
        BookStatsCard(
            database: database,
            sourceId: book.id,
            onOpenBook: onOpenBook,
            onOpenPage: onOpenPage,
            onOpenDashboard: onOpenDashboard,
            isPanel: true
        )
        .offset(x: appeared ? 0 : 40)
        .opacity(appeared ? 1 : 0)
    }
}

/// Размеры витрины: обложка в пропорциях книги по высоте окна, окно статистики справа.
/// Если рядом не помещаются, обложка меньше и статистика под ней.
struct BookShowcaseLayout: Equatable {
    static let panelWidth: CGFloat = 340
    static let gap: CGFloat = 40

    var coverWidth: CGFloat
    var coverHeight: CGFloat
    var isSideBySide: Bool

    init(size: CGSize) {
        let tall = min(size.height * 0.62, 520)
        let wideEnough = tall * 0.68 + Self.gap + Self.panelWidth + 80 <= size.width
        isSideBySide = wideEnough
        coverHeight = (wideEnough ? max(tall, 200) : min(size.height * 0.34, 300)).rounded()
        coverWidth = (coverHeight * 0.68).rounded()
    }
}
