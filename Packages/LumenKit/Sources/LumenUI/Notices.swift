import LumenCore
import LumenStorage
import LumenThemes
import OSLog
import SwiftUI

/// Журнал приложения. Сообщения видно в «Консоли» на Mac (подсистема io.github.bradd06.lumen),
/// в том числе после сбоя, в отличие от `print`.
let lumenLog = Logger(subsystem: "io.github.bradd06.lumen", category: "app")

/// Короткие плашки внизу окна: «Удалено · Вернуть» и сообщения об ошибках.
/// Одна на всё приложение: плашку может показать любой экран и любая модель.
@MainActor
@Observable
final class NoticeCenter {
    static let shared = NoticeCenter()

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var isError: Bool
        /// Кнопка «Вернуть»: отменяет то, о чём плашка сообщает.
        var undo: (@MainActor () async throws -> Void)?

        static func == (lhs: Notice, rhs: Notice) -> Bool { lhs.id == rhs.id }
    }

    private(set) var current: Notice?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Сколько секунд плашка висит, если её не трогать.
    static let duration: Double = 5

    /// Сообщение, по желанию с кнопкой «Вернуть».
    func show(_ text: String, undo: (@MainActor () async throws -> Void)? = nil) {
        present(Notice(text: text, isError: false, undo: undo))
    }

    /// Что-то не вышло: человек видит короткое объяснение, подробности уходят в журнал.
    func report(_ text: String, _ error: any Error) {
        lumenLog.error("\(text, privacy: .public): \(String(describing: error), privacy: .public)")
        present(Notice(text: text, isError: true, undo: nil))
    }

    /// Выполняет действие и при ошибке показывает плашку `failure`. Возвращает, получилось ли.
    @discardableResult
    func attempt(_ failure: String, _ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            return true
        } catch {
            report(failure, error)
            return false
        }
    }

    /// То же для действия, которое что-то возвращает: при ошибке плашка и `nil`.
    func perform<T>(_ failure: String, _ action: () async throws -> T) async -> T? {
        do {
            return try await action()
        } catch {
            report(failure, error)
            return nil
        }
    }

    func dismiss() {
        hideTask?.cancel()
        current = nil
    }

    /// Нажали «Вернуть»: плашка закрывается, действие отменяется.
    func performUndo() {
        guard let undo = current?.undo else { return }
        dismiss()
        Task {
            if await attempt("Не удалось вернуть", { try await undo() }) {
                LumenSounds.play(.restore)
            }
        }
    }

    private func present(_ notice: Notice) {
        current = notice
        hideTask?.cancel()
        let id = notice.id
        let seconds = Self.duration + (notice.isError ? 2 : 0)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self?.current?.id == id else { return }
            self?.current = nil
        }
    }
}

extension NoticeCenter {
    /// Убирает вещь в корзину и показывает плашку «… в корзине · Вернуть».
    func moveToTrash(_ item: LibraryItemID, in database: AppDatabase) {
        LumenSounds.play(.trash)
        Task {
            let done = await attempt("Не удалось удалить") {
                switch item {
                case .folder(let id): try await database.trashFolder(id)
                case .page(let id): try await database.trashPage(id)
                case .source(let id): try await database.trashSource(id)
                }
            }
            guard done else { return }
            let text = switch item {
            case .folder: "Папка в корзине"
            case .page: "Страница в корзине"
            case .source: "Книга в корзине"
            }
            show(text) {
                switch item {
                case .folder(let id): try await database.restoreFolder(id)
                case .page(let id): try await database.restorePage(id)
                case .source(let id): try await database.restoreSource(id)
                }
            }
        }
    }
}

/// Плашка из `NoticeCenter` поверх экрана. Ставится один раз у корня приложения.
struct NoticeOverlay: ViewModifier {
    /// Отступ снизу: на iPhone плашка не должна закрывать вкладки.
    var bottomPadding: CGFloat = 20
    private var center: NoticeCenter { .shared }

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let notice = center.current {
                NoticeBanner(notice: notice, onUndo: { center.performUndo() }, onClose: { center.dismiss() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(notice.id)
            }
        }
        .animation(.spring(duration: 0.3), value: center.current)
    }
}

extension View {
    /// Показывает плашки «Удалено · Вернуть» и ошибки поверх этого экрана.
    func lumenNotices(bottomPadding: CGFloat = 20) -> some View {
        modifier(NoticeOverlay(bottomPadding: bottomPadding))
    }
}

private struct NoticeBanner: View {
    let notice: NoticeCenter.Notice
    var onUndo: () -> Void
    var onClose: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? Color.orange : theme.accent)
            Text(notice.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(3)
            if notice.undo != nil {
                Button("Вернуть", action: onUndo)
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.accent)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.borderless)
            .help("Закрыть")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .frame(maxWidth: 520)
    }
}
