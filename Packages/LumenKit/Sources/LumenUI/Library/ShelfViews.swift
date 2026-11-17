import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import UniformTypeIdentifiers

// Части комнаты «Полка» вокруг корешков: поиск, выбор вида (корешки, обложки, список),
// книги обложками и строками списка, плитка «Перетащите сюда файл книги».

/// Поле «Книга или автор» над полками.
struct ShelfSearchField: View {
    @Binding var text: String

    @FocusState private var isFocused: Bool
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            TextField("Книга или автор", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
                .focused($isFocused)
                .autocorrectionDisabled()
                #if os(macOS)
                .onExitCommand { clear() }
                #endif
                .accessibilityLabel("Искать на полке")
                .accessibilityIdentifier("shelf-search")
            if !text.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Очистить поиск")
                .accessibilityLabel("Очистить поиск")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .lumenGlass(Capsule())
        .overlay(Capsule().strokeBorder(theme.accent.opacity(isFocused ? 0.6 : 0), lineWidth: 1))
        .keyHint("Искать на полке") { isFocused = true }
        .animation(LumenMotion.quick, value: text.isEmpty)
    }

    private func clear() {
        text = ""
        isFocused = false
    }
}

/// «Корешки · Обложки · Список». Где места мало, остаются одни значки.
struct ShelfDisplayPicker: View {
    let display: ShelfDisplay
    var showsTitles = true
    var onPick: (ShelfDisplay) -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ShelfDisplay.allCases) { option in
                segment(option)
            }
        }
        .padding(3)
        .lumenGlass(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Вид полки")
    }

    private func segment(_ option: ShelfDisplay) -> some View {
        let isOn = option == display
        return Button {
            onPick(option)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.symbolName)
                if showsTitles {
                    Text(option.title)
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, showsTitles ? 12 : 10)
            .frame(minHeight: 30)
            .foregroundStyle(isOn ? theme.onAccent : theme.textPrimary)
            .background {
                if isOn {
                    Capsule().fill(theme.textPrimary)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(option.title)
        .keyHint("Вид: \(option.title)") { onPick(option) }
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("shelf-display-\(option.rawValue)")
    }
}

/// Книга обложкой: картинка, название, автор и сколько прочитано.
/// Мышь над обложкой чуть приподнимает её; нажатие выносит книгу в витрину.
struct ShelfCoverTile: View {
    let book: Source
    let attachments: AttachmentStore
    var highlightCount = 0

    static let width: CGFloat = 116
    static let height: CGFloat = 170

    @State private var isHovered = false
    @Environment(\.bookShowcase) private var showcase
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            art
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            if book.progress > 0 {
                HStack(spacing: 6) {
                    ReadingProgressBar(progress: book.progress)
                    Text(ReadingText.percent(book.progress))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .frame(width: Self.width, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(LumenMotion.quick) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var art: some View {
        if showcase?.selectedId == book.id {
            // Книга сейчас в центре окна: на её месте пусто.
            Color.clear.frame(width: Self.width, height: Self.height)
        } else if let showcase {
            cover.matchedGeometryEffect(id: book.id, in: showcase.namespace)
        } else {
            cover
        }
    }

    private var cover: some View {
        SourceCoverArt(source: book, attachments: attachments, width: Self.width, height: Self.height)
            .overlay(alignment: .bottom) {
                if highlightCount > 0 {
                    SpineCountBadge(count: highlightCount)
                        .padding(.bottom, 8)
                }
            }
            .offset(y: isHovered ? -5 : 0)
            .scaleEffect(isHovered ? 1.03 : 1, anchor: .bottom)
    }
}

/// Книга строкой списка: обложка, название, автор (и полка), сколько выделений, прочитано.
struct ShelfListRow: View {
    let book: Source
    let attachments: AttachmentStore
    var highlightCount = 0
    /// Название полки: показывают, когда книги разных полок идут одним списком (поиск, «Читаю»).
    var shelfName: String?
    var isWide = true

    @State private var isHovered = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            SourceCoverArt(source: book, attachments: attachments, width: 34, height: 50)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isWide {
                if highlightCount > 0 {
                    Label("\(highlightCount)", systemImage: "highlighter")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                        .help("Выделений в книге: \(highlightCount)")
                }
                Text(Self.statusTitle(book))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.accent.opacity(0.12), in: Capsule())
                    .frame(width: 92, alignment: .trailing)
            }
            HStack(spacing: 8) {
                ReadingProgressBar(progress: book.progress)
                    .frame(width: isWide ? 110 : 54)
                Text(ReadingText.percent(book.progress))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.contrast.opacity(isHovered ? 0.07 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(LumenMotion.quick) { isHovered = hovering }
        }
    }

    private var subtitle: String {
        [book.author, shelfName.map { "полка «\($0)»" }]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// «Читаю», «Хочу» или «Прочитано», как кнопки над полками.
    nonisolated static func statusTitle(_ book: Source) -> String {
        ShelfStatus.allCases.first { $0 != .all && $0.contains(book) }?.title ?? ShelfStatus.wanted.title
    }
}

/// Пунктирная плитка в конце полки: сюда бросают файл книги из Finder или «Файлов»,
/// а нажатие открывает окно выбора файла. Книга, которую тащат по этой же полке,
/// над плиткой встаёт последней.
struct ShelfDropTile: View {
    enum Style {
        /// В конце ряда корешков.
        case shelf
        /// Клетка среди обложек.
        case cover
        /// Строка в конце списка.
        case row
    }

    var style: Style
    var title: String
    var help: String
    /// Перетаскивание книг по этой полке (только у корешков).
    var books: ShelfDropDelegate?
    var add: () -> Void
    var onFiles: ([URL]) -> Void

    @State private var isTargeted = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button(action: add) {
            label
                .foregroundStyle(isTargeted ? theme.textPrimary : theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: style == .row ? .infinity : nil)
                .frame(width: width, height: height)
                .background {
                    shape.fill(theme.accent.opacity(isTargeted ? 0.14 : 0.04))
                }
                .overlay {
                    shape.strokeBorder(
                        theme.accent.opacity(isTargeted ? 0.95 : 0.45),
                        style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: [5, 4])
                    )
                }
                .scaleEffect(isTargeted ? 1.03 : 1)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(LumenMotion.quick, value: isTargeted)
        .onDrop(of: ShelfFileDrop.types, delegate: ShelfFileDrop(isTargeted: $isTargeted, books: books, onFiles: onFiles))
        .help(help)
        .keyHint(title, perform: add)
        .accessibilityLabel(title)
        .accessibilityHint("Перетащите сюда файл книги или нажмите, чтобы выбрать его")
        .accessibilityIdentifier("shelf-drop-tile")
    }

    @ViewBuilder
    private var label: some View {
        if style == .row {
            HStack(spacing: 8) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "plus")
                Text(isTargeted ? "Отпустите, и книга встанет на полку" : "Перетащите сюда файл книги или нажмите, чтобы выбрать")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.medium))
        } else {
            VStack(spacing: 6) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.accent)
                Text(isTargeted ? "Отпустите,\nи книга встанет" : "Перетащите сюда\nфайл книги")
                    .font(.caption.weight(.medium))
                    .lineSpacing(1)
            }
            .padding(8)
        }
    }

    private var width: CGFloat? {
        switch style {
        case .shelf: 150
        case .cover: ShelfCoverTile.width
        case .row: nil
        }
    }

    private var height: CGFloat {
        switch style {
        case .shelf: 104
        case .cover: ShelfCoverTile.height
        case .row: 44
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style == .cover ? 10 : 12, style: .continuous)
    }
}

/// Бросок на плитку полки: файлы добавляются книгами, а книга, которую тащат по полке,
/// передаётся полке (`ShelfDropDelegate`) и встаёт в конец.
struct ShelfFileDrop: DropDelegate {
    /// `.data` нужен iPad: файлы из «Файлов» приходят своим типом (PDF, EPUB), без ссылки на файл.
    /// Книги полки приходят текстом, поэтому есть и `.text`.
    static let types: [UTType] = [.fileURL, .data, .text]

    @Binding var isTargeted: Bool
    var books: ShelfDropDelegate?
    var onFiles: ([URL]) -> Void

    /// Тащат книгу с полки, а не файл.
    private func isBook(_ info: DropInfo) -> Bool {
        books?.draggingId != nil && !info.hasItemsConforming(to: [.fileURL])
    }

    /// Файл: ссылка на файл (Finder) или данные, которые не просто текст.
    private func hasFiles(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
            || (info.hasItemsConforming(to: [.data]) && !info.hasItemsConforming(to: [.text]))
    }

    func validateDrop(info: DropInfo) -> Bool {
        isBook(info) || hasFiles(info)
    }

    func dropEntered(info: DropInfo) {
        if isBook(info) {
            _ = books?.hoverAtEnd()
        } else if hasFiles(info) {
            isTargeted = true
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isBook(info) { return books?.hoverAtEnd() }
        return hasFiles(info) ? DropProposal(operation: .copy) : nil
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        if isBook(info) { return books?.dropAtEnd() ?? false }
        guard hasFiles(info) else { return false }
        let providers = info.itemProviders(for: [.fileURL, .data])
        guard !providers.isEmpty else { return false }
        DroppedFiles.load(providers, completion: onFiles)
        return true
    }
}

/// Достаёт файлы из брошенного: ссылку на файл берёт как есть, а данные (iPad) копирует
/// во временную папку, потому что система удаляет свою копию сразу после броска.
enum DroppedFiles {
    @MainActor
    static func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let collector = Collector(expected: providers.count, completion: completion)
        for provider in providers {
            loadOne(provider) { url in
                Task { @MainActor in collector.add(url) }
            }
        }
    }

    private nonisolated static func loadOne(_ provider: NSItemProvider, done: @escaping @Sendable (URL?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                done(url?.isFileURL == true ? url : nil)
            }
            return
        }
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { id in
            guard let type = UTType(id) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .text)
        }) else {
            done(nil)
            return
        }
        let name = provider.suggestedName
        let type = UTType(identifier)
        _ = provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
            guard let url else {
                done(nil)
                return
            }
            done(copyToTemporary(url, suggestedName: name, type: type))
        }
    }

    private nonisolated static func copyToTemporary(_ url: URL, suggestedName: String?, type: UTType?) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumenDrop", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        var name = suggestedName ?? url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.isEmpty ? (type?.preferredFilenameExtension ?? "") : url.pathExtension
        if (name as NSString).pathExtension.isEmpty, !fileExtension.isEmpty {
            name += ".\(fileExtension)"
        }
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    /// Собирает файлы по мере того, как они приходят, и отдаёт все разом.
    @MainActor
    private final class Collector {
        private var expected: Int
        private var urls: [URL] = []
        private let completion: ([URL]) -> Void

        init(expected: Int, completion: @escaping ([URL]) -> Void) {
            self.expected = expected
            self.completion = completion
        }

        func add(_ url: URL?) {
            if let url { urls.append(url) }
            expected -= 1
            if expected == 0, !urls.isEmpty {
                completion(urls)
            }
        }
    }
}
