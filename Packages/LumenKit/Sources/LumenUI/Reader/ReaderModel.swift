import Foundation
import GRDB
import LumenCore
import LumenReader
import LumenStorage
import Observation

/// Состояние открытой книги: какой файл, где читаем, выделения и заметки рядом.
@MainActor
@Observable
final class ReaderModel {
    let database: AppDatabase
    let sourceId: UUID

    enum Content: Equatable {
        case loading
        /// Книга или документ в HTML: выделения и выписки работают.
        case web(PreparedDocument)
        case pdf
        case image(URL)
        /// Системный просмотр, без выделений.
        case quickLook(URL)
        case failed(String)
    }

    /// Как показывать документы Word и PowerPoint: текстом (с выписками) или как в оригинале.
    enum DocumentMode: String, CaseIterable, Identifiable {
        case text
        case original

        var id: String { rawValue }
        var title: String { self == .text ? "Текст" : "Оригинал" }
    }

    /// Выделенный, но ещё не сохранённый текст.
    struct Selection: Equatable {
        var text: String
        var locator: SourceLocator
        var label: String
    }

    private(set) var source: Source?
    private(set) var content: Content = .loading
    private(set) var highlights: [Highlight] = []
    /// Заметка в правой панели: по умолчанию заметки к книге, но можно открыть любую страницу.
    /// В неё же идут выписки.
    private(set) var notes: PageEditorModel?
    /// Страница заметок к этой книге: к ней панель возвращается одной кнопкой.
    private(set) var bookNotesPageId: UUID?
    var documentMode: DocumentMode = .text {
        didSet {
            guard documentMode != oldValue else { return }
            Task { await openContent() }
        }
    }

    /// Открытая глава (или страница PDF) и сколько её прокрутили.
    private(set) var section = 0
    private(set) var sectionProgression = 0.0
    private(set) var pageCount = 0
    var selection: Selection?
    /// Выделение, на которое нажали: для него показываются действия.
    var activeHighlightId: UUID?
    /// Короткое сообщение внизу экрана, например «Выписка добавлена в заметки».
    var toast: String?
    /// Оглавление: из файла, из закладок PDF или из заголовков открытого документа.
    private(set) var toc: [TocEntry] = []
    /// Последний пройденный якорь оглавления в открытой главе.
    private(set) var currentAnchor: String?

    @ObservationIgnored let web = WebReaderController()
    @ObservationIgnored let pdf = PDFReaderController()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pendingReveal: UUID?
    @ObservationIgnored private var hasRestoredPosition = false
    /// Какая глава сейчас загружена в веб-вид.
    @ObservationIgnored private var loadedSection: Int?

    init(database: AppDatabase, sourceId: UUID, highlightId: UUID?) {
        self.database = database
        self.sourceId = sourceId
        self.pendingReveal = highlightId
        web.onEvent = { [weak self] event in self?.handle(event) }
        pdf.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: Загрузка

    func load() async {
        do {
            guard let source = try await database.source(sourceId), !source.isTrashed else {
                content = .failed("Книгу удалили или переместили в корзину.")
                return
            }
            self.source = source
            section = source.locator?.section ?? 0
            sectionProgression = source.locator?.progression ?? 0
            highlights = try await database.reader.read { [sourceId] db in
                try Highlight.filter(Column("sourceId") == sourceId).order(Column("createdAt")).fetchAll(db)
            }
            let page = try await database.notesPage(for: sourceId)
            bookNotesPageId = page.id
            // Последняя открытая рядом страница, если её не удалили. Иначе заметки к книге.
            var sidePageId = page.id
            if let saved = UserDefaults.standard.string(forKey: sidePageKey).flatMap(UUID.init(uuidString:)),
               let savedPage = try await database.page(saved), !savedPage.isTrashed {
                sidePageId = saved
            }
            let notes = PageEditorModel(database: database, pageId: sidePageId)
            // Заметки загружаются сразу: выписку можно сделать, даже пока панель заметок закрыта.
            await notes.load()
            self.notes = notes
            await openContent()
        } catch {
            content = .failed("Не удалось открыть: \(error.localizedDescription)")
        }
    }

    // MARK: Заметка рядом

    private var sidePageKey: String { "reader.sidePage.\(sourceId.uuidString)" }

    /// Открыта ли в панели страница заметок к этой книге.
    var showsBookNotes: Bool { notes?.pageId == bookNotesPageId }

    /// Открывает страницу в правой панели. Выбор запоминается для этой книги.
    func openSidePage(_ pageId: UUID) async {
        guard pageId != notes?.pageId else { return }
        await notes?.flush()
        let model = PageEditorModel(database: database, pageId: pageId)
        await model.load()
        notes = model
        if pageId == bookNotesPageId {
            UserDefaults.standard.removeObject(forKey: sidePageKey)
        } else {
            UserDefaults.standard.set(pageId.uuidString, forKey: sidePageKey)
        }
    }

    func openBookNotes() async {
        if let bookNotesPageId { await openSidePage(bookNotesPageId) }
    }

    /// Новая пустая заметка в папке книги, сразу открытая рядом.
    func createSidePage() async {
        do {
            let page = try await database.createPage(folderId: source?.folderId)
            LumenSounds.play(.create)
            await openSidePage(page.id)
        } catch {
            print("Failed to create a page: \(error)")
        }
    }

    /// Следит за выделениями: их меняют и отсюда, и из списка выделений.
    func observeHighlights() async {
        let sourceId = sourceId
        let observation = ValueObservation.tracking { db in
            try Highlight.filter(Column("sourceId") == sourceId).order(Column("createdAt")).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: database.reader) {
                highlights = value
                paintHighlights()
            }
        } catch {
            print("Highlights observation failed: \(error)")
        }
    }

    var fileURL: URL? {
        source.map { database.attachments.url(for: $0.file) }
    }

    /// Можно ли переключаться между текстом и оригиналом.
    var hasOriginalMode: Bool {
        guard let format = source?.format else { return false }
        return DocumentConverter.canConvert(format) && [.docx, .pptx, .doc, .odt, .rtf].contains(format)
    }

    private func openContent() async {
        guard let source, let url = fileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            content = .failed("Файл книги не найден.")
            return
        }
        loadedSection = nil
        toc = []
        currentAnchor = nil
        if hasOriginalMode, documentMode == .original {
            content = .quickLook(url)
            return
        }
        switch source.format {
        case .pdf:
            guard pdf.load(url) else {
                content = .failed("Файл PDF повреждён.")
                return
            }
            pageCount = pdf.pageCount
            toc = pdf.outline()
            content = .pdf
            paintHighlights()
            restorePosition()
        case .image:
            content = .image(url)
        case let format where DocumentConverter.canConvert(format):
            if case .web = content {} else { content = .loading }
            do {
                let prepared = try await DocumentConverter.prepare(file: url, format: format, cacheKey: source.file)
                toc = Self.toc(for: prepared.document)
                content = .web(prepared)
                section = min(section, max(prepared.document.sections.count - 1, 0))
                restorePosition()
            } catch {
                // То, что не удалось перевести в текст, хотя бы покажет системный просмотр.
                content = .quickLook(url)
            }
        default:
            content = .quickLook(url)
        }
    }

    /// Первое открытие: к выделению из выписки или туда, где остановились.
    private func restorePosition() {
        if case .pdf = content {
            // PDFView переходит к странице только после первой раскладки.
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                restorePositionNow()
            }
        } else {
            restorePositionNow()
        }
    }

    private func restorePositionNow() {
        defer { hasRestoredPosition = true }
        if let id = pendingReveal, let highlight = highlights.first(where: { $0.id == id }) {
            pendingReveal = nil
            reveal(highlight)
            return
        }
        pendingReveal = nil
        switch content {
        case .web(let prepared):
            loadSection(section, in: prepared, progression: sectionProgression)
        case .pdf:
            pdf.go(to: SourceLocator(section: section))
        default:
            break
        }
    }

    // MARK: Навигация

    /// Оглавление книги. Если своего нет, а глав несколько, пунктами становятся главы.
    private static func toc(for document: ReadableDocument) -> [TocEntry] {
        if !document.toc.isEmpty { return document.toc }
        guard document.sections.count > 1 else { return [] }
        return document.sections.enumerated().map { TocEntry(title: $1.title, section: $0) }
    }

    /// Пункт оглавления, в котором сейчас читатель: последний, до которого уже дочитали.
    var currentTocEntry: TocEntry? {
        if case .pdf = content {
            return toc.last { $0.section <= section }
        }
        let passedAnchors: Set<String> = {
            let anchors = sectionAnchors
            guard let currentAnchor, let index = anchors.firstIndex(of: currentAnchor) else { return [] }
            return Set(anchors[...index])
        }()
        return toc.last { entry in
            entry.section < section
                || (entry.section == section && (entry.anchor == nil || passedAnchors.contains(entry.anchor!)))
        }
    }

    /// Якоря оглавления в открытой главе, по порядку.
    private var sectionAnchors: [String] {
        toc.filter { $0.section == section }.compactMap(\.anchor)
    }

    /// Переход по пункту оглавления.
    func open(_ entry: TocEntry) {
        LumenSounds.play(.navigate)
        selection = nil
        activeHighlightId = nil
        switch content {
        case .web(let prepared):
            if entry.section == loadedSection {
                if let anchor = entry.anchor {
                    web.scroll(toAnchor: anchor)
                } else {
                    web.scroll(to: 0)
                }
                currentAnchor = entry.anchor
            } else {
                loadSection(entry.section, in: prepared, progression: 0, anchor: entry.anchor)
            }
            scheduleSave()
        case .pdf:
            pdf.go(to: entry)
        default:
            break
        }
    }

    var sections: [ReadableSection] {
        if case .web(let prepared) = content { return prepared.document.sections }
        return []
    }

    func openSection(_ index: Int) {
        guard case .web(let prepared) = content, prepared.document.sections.indices.contains(index) else { return }
        LumenSounds.play(.navigate)
        loadSection(index, in: prepared, progression: 0)
        scheduleSave()
    }

    private func loadSection(
        _ index: Int,
        in prepared: PreparedDocument,
        progression: Double,
        reveal: UUID? = nil,
        anchor: String? = nil
    ) {
        guard let url = prepared.url(for: index) else { return }
        section = index
        loadedSection = index
        currentAnchor = anchor
        sectionProgression = progression
        selection = nil
        activeHighlightId = nil
        paintHighlights()
        web.setAnchors(sectionAnchors)
        web.load(url, root: prepared.root, progression: progression, reveal: reveal, anchor: anchor)
    }

    func reveal(_ highlight: Highlight) {
        activeHighlightId = nil
        switch content {
        case .web(let prepared):
            if highlight.locator.section == loadedSection {
                web.reveal(highlight.id)
            } else {
                loadSection(highlight.locator.section, in: prepared, progression: highlight.locator.progression, reveal: highlight.id)
            }
        case .pdf:
            pdf.reveal(highlight.id)
        default:
            pendingReveal = highlight.id
        }
    }

    /// Открыть выделение по id, например когда пришли из выписки на другой странице.
    func reveal(id: UUID) {
        if let highlight = highlights.first(where: { $0.id == id }) {
            reveal(highlight)
        } else {
            pendingReveal = id
        }
    }

    /// Сколько прочитано всего, от 0 до 1.
    var progress: Double {
        switch content {
        case .web(let prepared):
            let count = max(prepared.document.sections.count, 1)
            return min((Double(section) + sectionProgression) / Double(count), 1)
        case .pdf:
            return pageCount > 1 ? Double(section) / Double(pageCount - 1) : 1
        default:
            return source?.progress ?? 0
        }
    }

    /// Подпись текущего места: «Стр. 12 из 300», «Глава 3 из 20 · 45%».
    var positionLabel: String {
        switch content {
        case .web(let prepared):
            let count = prepared.document.sections.count
            let percent = Int((progress * 100).rounded())
            return count > 1 ? "Глава \(section + 1) из \(count) · \(percent)%" : "\(percent)%"
        case .pdf:
            return pageCount > 0 ? "Стр. \(section + 1) из \(pageCount)" : ""
        default:
            return ""
        }
    }

    // MARK: События читалки

    private func handle(_ event: WebReaderEvent) {
        switch event {
        case .ready:
            // Своего оглавления нет: собираем его из заголовков документа.
            if case .web(let prepared) = content, prepared.document.toc.isEmpty, prepared.document.sections.count == 1 {
                let section = section
                Task {
                    let headings = await web.headings(section: section)
                    guard !headings.isEmpty else { return }
                    toc = headings
                    web.setAnchors(sectionAnchors)
                }
            }
        case .selection(let text, let raw, let offset, let label, let progression):
            activeHighlightId = nil
            selection = Selection(
                text: text,
                locator: SourceLocator(section: section, progression: progression, text: raw, textOffset: offset),
                label: label ?? webLabel(progression: progression)
            )
        case .selectionCleared:
            selection = nil
        case .scrolled(let progression, let anchor):
            sectionProgression = progression
            currentAnchor = anchor
            scheduleSave()
        case .highlightTapped(let id):
            selection = nil
            activeHighlightId = id
        }
    }

    private func handle(_ event: PDFReaderEvent) {
        switch event {
        case .selection(let text, let locator):
            activeHighlightId = nil
            selection = Selection(text: text, locator: locator, label: "стр. \(locator.section + 1)")
        case .selectionCleared:
            selection = nil
        case .pageChanged(let index, let count):
            section = index
            pageCount = count
            scheduleSave()
        case .highlightTapped(let id):
            selection = nil
            activeHighlightId = id
        }
    }

    /// Подпись места в HTML-книге, если глава сама её не дала (как слайды и страницы комикса).
    private func webLabel(progression: Double) -> String {
        let sections = sections
        if sections.count > 1, sections.indices.contains(section) {
            let title = sections[section].title
            return title.count > 40 ? String(title.prefix(40)) + "…" : title
        }
        return "\(Int((progression * 100).rounded()))%"
    }

    private func scheduleSave() {
        guard hasRestoredPosition else { return }
        saveTask?.cancel()
        let locator = SourceLocator(section: section, progression: sectionProgression)
        let progress = progress
        saveTask = Task { [database, sourceId] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? await database.saveReadingPosition(sourceId, locator: locator, progress: progress)
        }
    }

    // MARK: Выделения и выписки

    private func paintHighlights() {
        switch content {
        case .web:
            web.setHighlights(highlights.filter { $0.locator.section == section }.map { highlight in
                WebHighlight(
                    id: highlight.id,
                    text: highlight.locator.text ?? highlight.text,
                    offset: highlight.locator.textOffset ?? 0,
                    colorHex: highlight.color.hex
                )
            })
        case .pdf:
            pdf.setHighlights(highlights.map { PDFHighlight(id: $0.id, locator: $0.locator, colorHex: $0.color.hex) })
        default:
            break
        }
    }

    /// Сохраняет выделение цветом. Возвращает его, чтобы сразу сделать выписку.
    @discardableResult
    func highlightSelection(_ color: HighlightColor) async -> Highlight? {
        guard let selection else { return nil }
        let highlight = Highlight(
            sourceId: sourceId,
            locator: selection.locator,
            text: selection.text,
            color: color,
            label: selection.label
        )
        do {
            try await database.addHighlight(highlight)
            highlights.append(highlight)
            paintHighlights()
            self.selection = nil
            clearSelection()
            LumenSounds.play(.toggle)
            return highlight
        } catch {
            print("Failed to save highlight: \(error)")
            return nil
        }
    }

    /// Выделение плюс выписка в заметки рядом.
    func excerptSelection(_ color: HighlightColor = .yellow) async {
        guard let highlight = await highlightSelection(color) else { return }
        addExcerpt(highlight)
    }

    /// Выписка из уже сохранённого выделения.
    func addExcerpt(_ highlight: Highlight) {
        guard let notes else { return }
        notes.appendExcerpt(
            text: highlight.text,
            reference: ExcerptReference(sourceId: sourceId, highlightId: highlight.id, label: highlight.label)
        )
        Task { await notes.flush() }
        LumenSounds.play(.create)
        if showsBookNotes {
            showToast("Выписка добавлена в заметки")
        } else {
            let title = notes.title.trimmingCharacters(in: .whitespacesAndNewlines)
            showToast(title.isEmpty ? "Выписка добавлена в заметку" : "Выписка добавлена в «\(title)»")
        }
    }

    func setColor(_ color: HighlightColor, of id: UUID) {
        Task { try? await database.setHighlightColor(id, color: color) }
    }

    func deleteHighlight(_ id: UUID) {
        if activeHighlightId == id { activeHighlightId = nil }
        highlights.removeAll { $0.id == id }
        paintHighlights()
        LumenSounds.play(.trash)
        Task { try? await database.deleteHighlight(id) }
    }

    func clearSelection() {
        selection = nil
        web.clearSelection()
        pdf.clearSelection()
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    /// Записывает место чтения сразу, например когда уходят с экрана.
    func flush() async {
        saveTask?.cancel()
        if hasRestoredPosition {
            try? await database.saveReadingPosition(
                sourceId,
                locator: SourceLocator(section: section, progression: sectionProgression),
                progress: progress
            )
        }
        await notes?.flush()
    }
}
