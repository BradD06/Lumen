import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Путь к странице над заголовком: Библиотека › Учёба › Матанализ. Любой шаг открывается.
struct PageBreadcrumbs: View {
    let database: AppDatabase
    let pageId: UUID
    /// Страница-родитель открывается так же, как ссылка из текста.
    var onOpenPage: (UUID) -> Void

    @State private var crumbs: [Breadcrumb] = []
    @Environment(\.appActions) private var appActions
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.textSecondary.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                    Button {
                        open(crumb)
                    } label: {
                        label(crumb)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CrumbButtonStyle())
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Путь к странице")
        .opacity(crumbs.isEmpty ? 0 : 1)
        .task(id: pageId) { await observe() }
    }

    @ViewBuilder
    private func label(_ crumb: Breadcrumb) -> some View {
        switch crumb {
        case .inbox:
            Label("Входящие", systemImage: "tray")
        case .library:
            Label("Библиотека", systemImage: "books.vertical")
        case .folder(let folder):
            Label {
                Text(folder.displayName)
            } icon: {
                FolderGlyph(color: folder.color, icon: folder.icon)
            }
        case .page(let page):
            PageLabel(page: page)
        }
    }

    private func open(_ crumb: Breadcrumb) {
        LumenSounds.play(.navigate)
        switch crumb {
        case .inbox: appActions.open(.inbox)
        case .library: appActions.open(.library(nil))
        case .folder(let folder): appActions.open(.library(folder.id))
        case .page(let page): onOpenPage(page.id)
        }
    }

    private func observe() async {
        let pageId = pageId
        let observation = ValueObservation.tracking { db in try BreadcrumbQuery.fetch(db, pageId: pageId) }
        do {
            for try await value in observation.values(in: database.reader) {
                crumbs = value
            }
        } catch {
            lumenLog.error("Breadcrumbs observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

private struct CrumbButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        CrumbBody(configuration: configuration)
    }

    private struct CrumbBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false
        @Environment(\.lumenTheme) private var theme

        var body: some View {
            configuration.label
                .background(
                    theme.textPrimary.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .onHover { isHovered = $0 }
        }
    }
}

/// «Сохранено» или «Сохраняется…»: видно, что правки записались.
/// По умолчанию надпись видна, только пока идёт запись, и пару секунд после.
struct SaveStatusLabel: View {
    let hasUnsavedChanges: Bool
    @Environment(\.lumenTheme) private var theme
    @AppStorage(ScreenOptions.saveStatusKey) private var mode = SaveStatusMode.briefly
    /// Правку только что записали: «Сохранено» ещё видно.
    @State private var justSaved = false

    var body: some View {
        label
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: isVisible)
            .task(id: hasUnsavedChanges) {
                guard !hasUnsavedChanges else {
                    justSaved = true
                    return
                }
                try? await Task.sleep(for: SaveStatusMode.briefDuration)
                guard !Task.isCancelled else { return }
                justSaved = false
            }
    }

    private var isVisible: Bool {
        switch mode {
        case .always: true
        case .briefly: hasUnsavedChanges || justSaved
        case .never: false
        }
    }

    private var label: some View {
        Label {
            Text(hasUnsavedChanges ? "Сохраняется…" : "Сохранено")
        } icon: {
            Image(systemName: hasUnsavedChanges ? "circle.dotted" : "checkmark")
                .foregroundStyle(hasUnsavedChanges ? theme.textSecondary : (theme.vividCard(3).colors.last ?? .green))
        }
        .font(.caption)
        .foregroundStyle(theme.textSecondary)
        .animation(.easeInOut(duration: 0.2), value: hasUnsavedChanges)
        .accessibilityIdentifier("save-status")
    }
}

/// Капсула в углу страницы: сколько слов (если включено в настройках) и кнопка режима фокуса.
struct WordCountCapsule: View {
    let words: Int
    let isFocusMode: Bool
    var onToggleFocus: () -> Void

    @Environment(\.lumenTheme) private var theme
    @AppStorage(ScreenOptions.wordCountKey) private var showsCount = false

    var body: some View {
        HStack(spacing: 6) {
            if showsCount {
                Text("\(words) \(Self.wordsNoun(words)) · \(Self.minutes(words))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 8)
            }
            Button(action: onToggleFocus) {
                Label(isFocusMode ? "Выйти из фокуса" : "Фокус", systemImage: "viewfinder")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(theme.textPrimary.opacity(isFocusMode ? 0.18 : 0.1), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textPrimary)
            .help(isFocusMode ? "Вернуть панели (⇧⌘F)" : "Спрятать всё лишнее и писать (⇧⌘F)")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.textPrimary.opacity(0.1)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    /// «слово», «слова», «слов».
    static func wordsNoun(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if (11...14).contains(lastTwo) { return "слов" }
        switch last {
        case 1: return "слово"
        case 2, 3, 4: return "слова"
        default: return "слов"
        }
    }

    /// Время чтения при 180 словах в минуту.
    static func minutes(_ words: Int) -> String {
        let minutes = max(1, Int((Double(words) / 180).rounded(.up)))
        return "\(minutes) мин чтения"
    }
}

extension PageEditorModel {
    /// Слова во всех текстовых блоках страницы.
    var wordCount: Int {
        blocks.reduce(0) { count, block in
            guard block.type.hasText else { return count }
            return count + block.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        }
    }
}

/// iPhone: ряд «Превратить в» над клавиатурой. Текущий тип блока подсвечен.
struct BlockTypeChips: View {
    let current: BlockType
    var onSelect: (BlockType) -> Void

    @Environment(\.lumenTheme) private var theme

    private static let types: [BlockType] = [.paragraph, .heading1, .heading2, .bulletedList, .numberedList, .todo, .quote, .toggle, .code]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.types, id: \.self) { type in
                    let isCurrent = type == current
                    Button {
                        LumenSounds.play(.tap)
                        onSelect(type)
                    } label: {
                        Label(Self.title(type), systemImage: type.symbolName)
                            .font(.subheadline.weight(isCurrent ? .bold : .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(isCurrent ? theme.vividCard(0).foreground : theme.textPrimary)
                            .background(
                                isCurrent ? AnyShapeStyle(theme.textPrimary) : AnyShapeStyle(theme.cardFill),
                                in: Capsule()
                            )
                            .overlay(Capsule().strokeBorder(theme.textPrimary.opacity(isCurrent ? 0 : 0.14)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    /// Короткие подписи, чтобы ряд помещался.
    private static func title(_ type: BlockType) -> String {
        switch type {
        case .paragraph: "Текст"
        case .heading1: "Заголовок"
        case .heading2: "Подзаголовок"
        case .bulletedList: "Список"
        case .numberedList: "Нумерация"
        case .todo: "Задача"
        case .quote: "Цитата"
        case .toggle: "Свернуть"
        case .code: "Код"
        default: type.title
        }
    }
}
