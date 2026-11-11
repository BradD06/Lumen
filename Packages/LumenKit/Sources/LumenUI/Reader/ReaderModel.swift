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

    /// Как показывать документы Word и PowerPoint, а также PDF: текстом (как книгу, с любым размером
    /// шрифта) или как в оригинале.
    enum DocumentMode: String, CaseIterable, Identifiable {
        case text
        case original

        var id: String { rawValue }
        var title: String { self == .text ? "Текст" : "Оригинал" }
        var systemImage: String { self == .text ? "text.alignleft" : "doc.richtext" }
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
    /// В неё же идут выписки. `nil`, пока к книге не завели ни одной заметки: заметка
    /// создаётся, только когда её впервые открывают (или делают первую выписку), а не при открытии книги.
    private(set) var notes: PageEditorModel?
    /// Страница заметок к этой книге: к ней панель возвращается одной кнопкой. `nil`, пока её не завели.
    private(set) var bookNotesPageId: UUID?
    /// Страница, открытая рядом с книгой во второй половине разделённого экрана (слева или справа).
    /// Пока она есть, выписки и ссылки на места идут в неё, а не в заметки в панели читалки.
    var besidePageId: UUID?
    var documentMode: DocumentMode = .text {
        didSet {
            guard documentMode != oldValue, let source = self.source else { return }
            if source.format == .pdf {
                // Место чтения у PDF всегда хранится страницей, поэтому переходит в другой вид как есть.
                savedLocator = readingLocator
                UserDefaults.standard.set(documentMode.rawValue, forKey: pdfModeKey)
            }
            Task { await openContent() }
        }
    }

    /// Открытая глава (или страница PDF) и сколько её прокрутили.
    private(set) var section = 0
    private(set) var sectionProgression = 0.0
    /// Сколько символов главы стоит до первой строки на экране: по нему глава открывается точно там же.
    private(set) var sectionTextOffset: Int?
    private(set) var pageCount = 0
    /// Масштаб PDF и зафиксирован ли он. Фиксация запоминается для каждой книги на этом устройстве.
    private(set) var pdfScale = 1.0
    private(set) var isZoomLocked = false
    /// PDF без белых полей: текст крупнее при той же ширине экрана. Запоминается для каждой книги.
    var cropsMargins = true {
        didSet {
            guard cropsMargins != oldValue else { return }
            UserDefaults.standard.set(cropsMargins, forKey: cropKey)
            applyPDFLayout()
        }
    }
    /// PDF в две колонки читается по колонкам: левая по ширине экрана, под ней правая.
    var splitsColumns = false {
        didSet {
            guard splitsColumns != oldValue else { return }
            UserDefaults.standard.set(splitsColumns, forKey: columnsKey)
            applyPDFLayout()
        }
    }
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
    /// Ищет в оригинале PDF то, что выделили в режиме «Текст»: так выделение видно в обоих видах.
    @ObservationIgnored private var textFinder: PDFTextFinder?
    /// Где у страниц PDF поля и колонки. Ищется один раз в фоне и потом берётся из кэша.
    @ObservationIgnored private var pdfLayout: PDFBookLayout?
    @ObservationIgnored private var layoutTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Заметки к книге, которые сейчас создаются: два быстрых нажатия не заведут две заметки.
    @ObservationIgnored private var creatingNotes: Task<PageEditorModel?, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pendingReveal: UUID?
    @ObservationIgnored private var hasRestoredPosition = false
    /// Где остановились в прошлый раз.
    @ObservationIgnored private var savedLocator: SourceLocator?
    /// Какая глава сейчас загружена в веб-вид.
    @ObservationIgnored private var loadedSection: Int?
    /// Время чтения за этот раз: растёт, пока человек листает, выделяет и пишет.
    @ObservationIgnored private(set) var readingSession: ReadingSession?
    @ObservationIgnored private var lastActivity: Date?
    /// Дольше этого без единого действия считается, что книгу отложили.
    static let idleLimit: TimeInterval = 300

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
            if source.format == .pdf {
                // Источник ещё не задан, поэтому смена вида здесь ничего не открывает.
                documentMode = UserDefaults.standard.string(forKey: pdfModeKey).flatMap(DocumentMode.init(rawValue:)) ?? .original
                cropsMargins = UserDefaults.standard.object(forKey: cropKey) as? Bool ?? true
                splitsColumns = UserDefaults.standard.bool(forKey: columnsKey)
            }
            self.source = source
            savedLocator = source.locator
            section = source.locator?.section ?? 0
            sectionProgression = source.locator?.progression ?? 0
            sectionTextOffset = source.locator?.textOffset
            highlights = try await database.reader.read { [sourceId] db in
                try Highlight
                    .filter(Column("sourceId") == sourceId && Column("deletedAt") == nil)
                    .order(Column("createdAt"))
                    .fetchAll(db)
            }
            // Заметки к книге только ищутся: если их ещё нет, они появятся при первом открытии.
            bookNotesPageId = try await database.bookNotesPage(for: sourceId)?.id
            // Последняя открытая рядом страница, если её не удалили. Иначе заметки к книге.
            var sidePageId = bookNotesPageId
            if let saved = UserDefaults.standard.string(forKey: sidePageKey).flatMap(UUID.init(uuidString:)),
               let savedPage = try await database.page(saved), !savedPage.isTrashed {
                sidePageId = saved
            }
            if let sidePageId {
                let notes = PageEditorModel(database: database, pageId: sidePageId)
                attach(notes)
                // Заметки загружаются сразу: выписку можно сделать, даже пока панель заметок закрыта.
                await notes.load()
                self.notes = notes
            }
            await openContent()
            noteActivity()
        } catch {
            content = .failed("Не удалось открыть: \(error.localizedDescription)")
        }
    }

    // MARK: Заметка рядом

    private var sidePageKey: String { "reader.sidePage.\(sourceId.uuidString)" }

    /// Открыта ли в панели страница заметок к этой книге. Пока заметок нет, панель ждёт именно их.
    var showsBookNotes: Bool { notes?.pageId == bookNotesPageId }

    /// Открывает редактор заметок: если рядом ещё ничего не открыто, заводит заметки к книге.
    /// Они ложатся туда же, где книга: в её папку или в корень библиотеки, рядом с ней на холсте.
    @discardableResult
    func ensureNotes() async -> PageEditorModel? {
        if let notes { return notes }
        guard source != nil else { return nil }
        if let creatingNotes { return await creatingNotes.value }
        let task = Task { () -> PageEditorModel? in
            do {
                let page = try await database.notesPage(for: sourceId)
                bookNotesPageId = page.id
                let model = PageEditorModel(database: database, pageId: page.id)
                attach(model)
                await model.load()
                notes = model
                return model
            } catch {
                NoticeCenter.shared.report("Не удалось создать заметки к книге", error)
                return nil
            }
        }
        creatingNotes = task
        let model = await task.value
        creatingNotes = nil
        return model
    }

    /// Открывает страницу в правой панели. Выбор запоминается для этой книги.
    func openSidePage(_ pageId: UUID) async {
        guard pageId != notes?.pageId else { return }
        await notes?.flush()
        let model = PageEditorModel(database: database, pageId: pageId)
        attach(model)
        await model.load()
        notes = model
        if pageId == bookNotesPageId {
            UserDefaults.standard.removeObject(forKey: sidePageKey)
        } else {
            UserDefaults.standard.set(pageId.uuidString, forKey: sidePageKey)
        }
    }

    /// Ссылки на места этой книги в заметке рядом прокручивают книгу, а не открывают её заново.
    private func attach(_ notes: PageEditorModel) {
        notes.openPlaceInReader = { [weak self] reference in
            guard let self, reference.sourceId == sourceId, let locator = reference.locator else { return false }
            LumenSounds.play(.navigate)
            go(to: locator)
            return true
        }
    }

    /// Возвращает панель к заметкам к книге. Если их ещё нет, заводит.
    func openBookNotes() async {
        if let bookNotesPageId {
            await openSidePage(bookNotesPageId)
            return
        }
        do {
            let page = try await database.notesPage(for: sourceId)
            bookNotesPageId = page.id
            await openSidePage(page.id)
        } catch {
            NoticeCenter.shared.report("Не удалось создать заметки к книге", error)
        }
    }

    /// Новая пустая заметка в папке книги, рядом с книгой на холсте, сразу открытая в панели.
    func createSidePage() async {
        do {
            let page = try await database.createPage(besideSource: sourceId)
            LumenSounds.play(.create)
            await openSidePage(page.id)
        } catch {
            NoticeCenter.shared.report("Не удалось создать страницу", error)
        }
    }

    /// Следит за выделениями: их меняют и отсюда, и из списка выделений.
    func observeHighlights() async {
        let sourceId = sourceId
        let observation = ValueObservation.tracking { db in
            try Highlight
                .filter(Column("sourceId") == sourceId && Column("deletedAt") == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
        }
        do {
            for try await value in observation.values(in: database.reader) {
                highlights = value
                paintHighlights()
            }
        } catch {
            lumenLog.error("Highlights observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    var fileURL: URL? {
        source.map { database.attachments.url(for: $0.file) }
    }

    /// Можно ли переключаться между текстом и оригиналом.
    var hasOriginalMode: Bool {
        guard let format = source?.format else { return false }
        if format == .pdf { return true }
        return DocumentConverter.canConvert(format) && [.docx, .pptx, .doc, .odt, .rtf].contains(format)
    }

    /// Вид PDF (текст или оригинал) запоминается для каждой книги.
    private var pdfModeKey: String { "reader.pdfMode.\(sourceId.uuidString)" }

    /// PDF, открытый в режиме «Текст»: как места текста связаны со страницами.
    private var pdfText: PDFTextIndex? {
        guard source?.format == .pdf, case .web(let prepared) = content else { return nil }
        return prepared.document.pdfText
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
        if hasOriginalMode, documentMode == .original, source.format != .pdf {
            content = .quickLook(url)
            return
        }
        switch source.format {
        case .pdf where documentMode == .text:
            if case .web = content {} else { content = .loading }
            do {
                let prepared = try await DocumentConverter.preparePDFText(file: url, cacheKey: source.file)
                // Пока текст готовился, могли вернуться к оригиналу.
                guard documentMode == .text else { return }
                if let index = prepared.document.pdfText {
                    let place = index.place(of: savedLocator ?? SourceLocator(section: 0))
                    section = place.section
                    sectionProgression = 0
                    sectionTextOffset = place.offset
                    pageCount = index.pageCount
                }
                toc = Self.toc(for: prepared.document)
                content = .web(prepared)
                section = min(section, max(prepared.document.sections.count - 1, 0))
                restorePosition()
            } catch {
                showToast((error as? ReaderError) == .noText
                    ? "В этом PDF нет текста, только картинки страниц"
                    : "Не получилось достать текст из PDF")
                documentMode = .original
            }
        case .pdf:
            let savedScale = UserDefaults.standard.object(forKey: zoomKey) as? Double
            isZoomLocked = savedScale != nil
            pdf.setZoom(locked: savedScale, factor: UserDefaults.standard.object(forKey: zoomFactorKey) as? Double)
            if pdfLayout == nil { pdfLayout = PDFLayoutAnalyzer.cachedLayout(cacheKey: source.file) }
            guard pdf.load(url, layout: pdfLayout, options: pdfLayoutOptions) else {
                content = .failed("Файл PDF повреждён.")
                return
            }
            if pdfLayoutOptions != .original, pdfLayout == nil { findPDFLayout() }
            pageCount = pdf.pageCount
            pdfScale = pdf.scale
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
            loadSection(section, in: prepared, progression: sectionProgression, offset: sectionTextOffset)
        case .pdf:
            // Масштаб ставится до перехода: точка на странице зависит от него.
            pdf.refreshZoom()
            pdf.go(to: savedLocator ?? SourceLocator(section: section))
            section = pdf.currentPageIndex
            pdfScale = pdf.scale
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

    /// `progression` 1 открывает главу с конца: так листают назад из начала следующей.
    func openSection(_ index: Int, progression: Double = 0) {
        guard case .web(let prepared) = content, prepared.document.sections.indices.contains(index) else { return }
        LumenSounds.play(.navigate)
        loadSection(index, in: prepared, progression: progression)
        scheduleSave()
    }

    private func loadSection(
        _ index: Int,
        in prepared: PreparedDocument,
        progression: Double,
        offset: Int? = nil,
        reveal: UUID? = nil,
        anchor: String? = nil
    ) {
        guard let url = prepared.url(for: index) else { return }
        section = index
        loadedSection = index
        currentAnchor = anchor
        sectionProgression = progression
        sectionTextOffset = offset
        selection = nil
        activeHighlightId = nil
        paintHighlights()
        web.setAnchors(sectionAnchors)
        web.load(url, root: prepared.root, progression: progression, offset: offset, reveal: reveal, anchor: anchor)
    }

    func reveal(_ highlight: Highlight) {
        activeHighlightId = nil
        switch content {
        case .web(let prepared):
            let place = webPlace(highlight.locator)
            if place.section == loadedSection {
                web.reveal(highlight.id)
            } else {
                loadSection(place.section, in: prepared, progression: place.progression, reveal: highlight.id)
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

    /// Переход к месту из ссылки на место.
    func go(to locator: SourceLocator) {
        selection = nil
        activeHighlightId = nil
        switch content {
        case .web(let prepared):
            let place = webPlace(locator)
            guard prepared.document.sections.indices.contains(place.section) else { return }
            if place.section == loadedSection, let offset = place.offset {
                web.scroll(toOffset: offset)
                sectionTextOffset = offset
            } else if place.section == loadedSection {
                web.scroll(to: place.progression)
            } else {
                loadSection(place.section, in: prepared, progression: place.progression, offset: place.offset)
            }
            sectionProgression = place.progression
            scheduleSave()
        case .pdf:
            pdf.go(to: locator)
            scheduleSave()
        default:
            break
        }
    }

    /// Глава и место в ней для места книги. У PDF в режиме «Текст» место хранится страницей
    /// и символом от её начала, а глава находится по ним.
    private func webPlace(_ locator: SourceLocator) -> (section: Int, offset: Int?, progression: Double) {
        guard let index = pdfText else { return (locator.section, locator.textOffset, locator.progression) }
        let place = index.place(of: locator)
        return (place.section, place.offset, 0)
    }

    /// Сквозной номер символа вверху экрана в режиме «Текст» у PDF.
    private func pdfTextPosition(_ index: PDFTextIndex) -> Int {
        if let offset = sectionTextOffset { return index.global(section: section, offset: offset) }
        let start = index.global(section: section, offset: 0)
        let end = section + 1 < index.sections.count ? index.sections[section + 1] : index.length
        return start + Int(Double(max(end - start, 0)) * sectionProgression)
    }

    /// Куда класть выписки: в заметку, открытую рядом с книгой в разделённом экране, а если
    /// её нет (или там рукописная тетрадь, куда текст не вставить), в заметку в панели читалки.
    /// Заметка рядом берётся из её же открытого редактора, чтобы выписка сразу появилась на экране.
    func excerptTarget() async -> PageEditorModel? {
        if let besidePageId,
           let beside = OpenPageEditors.shared.model(for: besidePageId),
           beside.isLoaded, !beside.isNotebook {
            return beside
        }
        return await ensureNotes()
    }

    /// Ссылка на место, где сейчас читают, в заметку рядом. Без выделения текста.
    func addPlaceLink() async {
        guard let reference = currentPlace, let notes = await excerptTarget() else { return }
        notes.appendPlaceLink(reference)
        Task { await notes.flush() }
        LumenSounds.play(.tape)
        if notes.pageId == bookNotesPageId {
            showToast("Ссылка на место добавлена в заметки")
        } else {
            let title = notes.title.trimmingCharacters(in: .whitespacesAndNewlines)
            showToast(title.isEmpty ? "Ссылка на место добавлена в заметку" : "Ссылка добавлена в «\(title)»")
        }
    }

    /// Ссылка `lumen://` на это место в буфер обмена: её можно вставить в другое приложение.
    func copyPlaceLink() {
        guard let reference = currentPlace else { return }
        copyLink(reference.link)
        showToast("Ссылка на это место скопирована")
    }

    /// Место, где сейчас читают, с подписью. У системного просмотра места нет.
    private var currentPlace: ExcerptReference? {
        let locator = readingLocator
        let label: String
        switch content {
        case .pdf:
            label = "стр. \(locator.section + 1)"
        case .web:
            label = pdfText != nil ? "стр. \(locator.section + 1)" : webLabel(progression: locator.progression)
        default:
            return nil
        }
        return ExcerptReference(sourceId: sourceId, locator: locator, label: label)
    }

    /// Можно ли сослаться на место: у системного просмотра места нет.
    var canLinkPlace: Bool {
        switch content {
        case .web, .pdf: true
        default: false
        }
    }

    /// Сколько прочитано всего, от 0 до 1.
    var progress: Double {
        switch content {
        case .web(let prepared):
            if let index = pdfText {
                let page = index.page(at: pdfTextPosition(index))
                return index.pageCount > 1 ? Double(page) / Double(index.pageCount - 1) : 1
            }
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
            if let index = pdfText {
                return "Стр. \(index.page(at: pdfTextPosition(index)) + 1) из \(index.pageCount)"
            }
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
            noteActivity()
            activeHighlightId = nil
            if let index = pdfText {
                selection = pdfTextSelection(text: text, raw: raw, offset: offset, index: index)
                return
            }
            selection = Selection(
                text: text,
                locator: SourceLocator(section: section, progression: progression, text: raw, textOffset: offset),
                label: label ?? webLabel(progression: progression)
            )
        case .selectionCleared:
            selection = nil
        case .scrolled(let progression, let anchor, let offset):
            sectionProgression = progression
            sectionTextOffset = offset
            currentAnchor = anchor
            scheduleSave()
        case .highlightTapped(let id):
            selection = nil
            activeHighlightId = id
        case .turnedPastEdge(let forward):
            if forward {
                openSection(section + 1)
            } else {
                openSection(section - 1, progression: 1)
            }
        }
    }

    private func handle(_ event: PDFReaderEvent) {
        // В режиме «Текст» вид PDF спрятан, его события места чтения не меняют.
        guard content == .pdf else { return }
        switch event {
        case .selection(let text, let locator):
            noteActivity()
            activeHighlightId = nil
            selection = Selection(text: text, locator: locator, label: "стр. \(locator.section + 1)")
        case .selectionCleared:
            selection = nil
        case .pageChanged(let index, let count):
            pageCount = count
            // Пока PDF только открылся, он стоит на первой странице: это ещё не место чтения.
            guard hasRestoredPosition else { return }
            section = index
            scheduleSave()
        case .moved:
            guard hasRestoredPosition else { return }
            scheduleSave()
        case .scaleChanged(let scale):
            pdfScale = scale
        case .zoomedByHand:
            rememberZoom()
        case .highlightTapped(let id):
            selection = nil
            activeHighlightId = id
        }
    }

    /// Выделение в режиме «Текст» у PDF запоминается страницей PDF и прямоугольниками строк в ней,
    /// поэтому его видно и в оригинале, а выписка открывает книгу в любом виде.
    private func pdfTextSelection(text: String, raw: String, offset: Int, index: PDFTextIndex) -> Selection {
        let global = index.global(section: section, offset: offset)
        let page = index.page(at: global)
        if textFinder == nil, let url = fileURL { textFinder = PDFTextFinder(url: url) }
        let rects = textFinder?.rects(of: text, page: page, fraction: index.fraction(of: global, onPage: page))
        let locator = SourceLocator(
            section: page,
            progression: index.pageCount > 1 ? Double(page) / Double(index.pageCount - 1) : 0,
            text: raw,
            textOffset: global - index.global(page: page),
            rects: rects
        )
        return Selection(text: text, locator: locator, label: "стр. \(page + 1)")
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

    /// Место чтения для сохранения: у PDF вместе с точкой на странице, у книги со строкой вверху экрана.
    private var readingLocator: SourceLocator {
        switch content {
        case .pdf:
            return pdf.readingLocator
        case .web:
            if let index = pdfText {
                let global = pdfTextPosition(index)
                let page = index.page(at: global)
                return SourceLocator(
                    section: page,
                    progression: index.pageCount > 1 ? Double(page) / Double(index.pageCount - 1) : 0,
                    textOffset: global - index.global(page: page)
                )
            }
            return SourceLocator(section: section, progression: sectionProgression, textOffset: sectionTextOffset)
        default:
            return savedLocator ?? SourceLocator(section: section, progression: sectionProgression)
        }
    }

    // MARK: Масштаб PDF

    private var zoomKey: String { "reader.pdfZoom.\(sourceId.uuidString)" }
    /// Свободный масштаб книги, во сколько раз крупнее, чем «по ширине».
    private var zoomFactorKey: String { "reader.pdfZoomFactor.\(sourceId.uuidString)" }
    private var cropKey: String { "reader.pdfCrop.\(sourceId.uuidString)" }
    private var columnsKey: String { "reader.pdfColumns.\(sourceId.uuidString)" }

    private var pdfLayoutOptions: PDFLayoutOptions {
        PDFLayoutOptions(cropsMargins: cropsMargins, splitsColumns: splitsColumns)
    }

    /// Поля или колонки включили или выключили: страницы перекладываются, место чтения остаётся.
    private func applyPDFLayout() {
        guard content == .pdf else { return }
        if pdfLayoutOptions != .original, pdfLayout == nil {
            findPDFLayout()
            return
        }
        pdf.setLayout(pdfLayout, options: pdfLayoutOptions)
        if splitsColumns, pdfLayout?.hasColumns == false { showToast("Колонок в этой книге не нашлось") }
    }

    /// Разбирает страницы книги в фоне. У большой книги со сканами это занимает время,
    /// поэтому до конца разбора страницы показаны как есть.
    private func findPDFLayout() {
        guard layoutTask == nil, let source, let url = fileURL else { return }
        layoutTask = Task { [weak self] in
            let layout = await PDFLayoutAnalyzer.layout(of: url, cacheKey: source.file)
            guard let self else { return }
            self.layoutTask = nil
            self.pdfLayout = layout
            guard self.content == .pdf, self.pdfLayoutOptions != .original else { return }
            self.pdf.setLayout(layout, options: self.pdfLayoutOptions)
            if self.splitsColumns, layout?.hasColumns == false { self.showToast("Колонок в этой книге не нашлось") }
        }
    }

    func zoom(in larger: Bool) {
        pdf.zoom(by: larger ? 1.2 : 1 / 1.2)
        rememberZoom()
    }

    func zoomToFit() {
        pdf.zoomToFit()
        rememberZoom()
    }

    /// Фиксирует нынешний масштаб или отпускает его.
    func toggleZoomLock() {
        isZoomLocked.toggle()
        pdf.lockZoom(at: isZoomLocked ? pdf.scale : nil)
        rememberZoom()
        LumenSounds.play(.toggle)
        showToast(isZoomLocked ? "Масштаб \(Self.percent(pdf.scale)) зафиксирован" : "Масштаб снова свободный")
    }

    private func rememberZoom() {
        pdfScale = pdf.scale
        let defaults = UserDefaults.standard
        if isZoomLocked, let scale = pdf.lockedScale {
            defaults.set(scale, forKey: zoomKey)
        } else {
            defaults.removeObject(forKey: zoomKey)
        }
        if !isZoomLocked, let factor = pdf.zoomFactor {
            defaults.set(factor, forKey: zoomFactorKey)
        } else {
            defaults.removeObject(forKey: zoomFactorKey)
        }
    }

    static func percent(_ scale: Double) -> String {
        "\(Int((scale * 100).rounded()))%"
    }

    private func scheduleSave() {
        noteActivity()
        guard hasRestoredPosition else { return }
        saveTask?.cancel()
        let locator = readingLocator
        let progress = progress
        let session = readingSession
        saveTask = Task { [database, sourceId] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? await database.saveReadingPosition(sourceId, locator: locator, progress: progress)
            if let session, session.seconds >= 1 { try? await database.saveReadingSession(session) }
        }
    }

    // MARK: Время чтения

    /// Человек что-то сделал в книге. Время с прошлого действия засчитывается, если не было
    /// долгого перерыва; после перерыва счёт просто продолжается с этого момента.
    func noteActivity(at now: Date = Date()) {
        guard source != nil else { return }
        if var session = readingSession {
            if let lastActivity, now.timeIntervalSince(lastActivity) <= Self.idleLimit {
                session.seconds += max(now.timeIntervalSince(lastActivity), 0)
                session.endedAt = now
                readingSession = session
            }
        } else {
            readingSession = ReadingSession(sourceId: sourceId, startedAt: now, endedAt: now, seconds: 0)
        }
        lastActivity = now
    }

    // MARK: Выделения и выписки

    private func paintHighlights() {
        if let index = pdfText {
            paintPDFTextHighlights(index)
            return
        }
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

    /// Выделения на страницах, которые задевают открытую главу. Выделение из оригинала хранит текст
    /// строками страницы, а в режиме «Текст» строки склеены, поэтому текст склеивается так же.
    private func paintPDFTextHighlights(_ index: PDFTextIndex) {
        let section = section
        web.setHighlights(highlights.compactMap { highlight in
            guard index.page(highlight.locator.section, overlaps: section) else { return nil }
            let place = index.place(of: highlight.locator)
            let text = highlight.locator.textOffset == nil
                ? PDFTextIndex.reflow(highlight.locator.text ?? highlight.text)
                : (highlight.locator.text ?? highlight.text)
            return WebHighlight(id: highlight.id, text: text, offset: place.section == section ? place.offset : 0, colorHex: highlight.color.hex)
        })
    }

    /// Сохраняет выделение цветом. Возвращает его, чтобы сразу сделать выписку.
    @discardableResult
    func highlightSelection(_ color: HighlightColor) async -> Highlight? {
        guard let selection else { return nil }
        // То же место уже выделено: новое выделение поверх не нужно, только цвет.
        if let existing = highlights.first(where: { $0.matches(selection.locator, text: selection.text) }) {
            if existing.color != color { setColor(color, of: existing.id) }
            self.selection = nil
            clearSelection()
            return existing
        }
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
            NoticeCenter.shared.report("Не удалось сохранить выделение", error)
            return nil
        }
    }

    /// Выделение и ссылка `lumen://` на него в буфер обмена.
    func copySelectionLink() async {
        guard let highlight = await highlightSelection(.yellow) else { return }
        copyLink(ExcerptReference(sourceId: sourceId, highlightId: highlight.id, label: highlight.label).link)
        showToast("Ссылка на цитату скопирована")
    }

    /// Выделение плюс выписка в заметки рядом.
    func excerptSelection(_ color: HighlightColor = .yellow) async {
        guard let highlight = await highlightSelection(color) else { return }
        await addExcerpt(highlight)
    }

    /// Выписка из уже сохранённого выделения. Если заметок к книге ещё нет, они заводятся.
    func addExcerpt(_ highlight: Highlight) async {
        guard let notes = await excerptTarget() else { return }
        notes.appendExcerpt(
            text: highlight.text,
            reference: ExcerptReference(sourceId: sourceId, highlightId: highlight.id, label: highlight.label)
        )
        Task { await notes.flush() }
        LumenSounds.play(.create)
        if notes.pageId == bookNotesPageId {
            showToast("Выписка добавлена в заметки")
        } else {
            let title = notes.title.trimmingCharacters(in: .whitespacesAndNewlines)
            showToast(title.isEmpty ? "Выписка добавлена в заметку" : "Выписка добавлена в «\(title)»")
        }
    }

    func setColor(_ color: HighlightColor, of id: UUID) {
        Task {
            await NoticeCenter.shared.attempt("Не удалось поменять цвет выделения") {
                try await database.setHighlightColor(id, color: color)
            }
        }
    }

    func deleteHighlight(_ id: UUID) {
        if activeHighlightId == id { activeHighlightId = nil }
        let deleted = highlights.first { $0.id == id }
        highlights.removeAll { $0.id == id }
        paintHighlights()
        LumenSounds.play(.trash)
        let database = database
        Task {
            let done = await NoticeCenter.shared.attempt("Не удалось удалить выделение") {
                try await database.deleteHighlight(id)
            }
            guard done, let deleted else { return }
            // «Вернуть» кладёт то же выделение обратно: выписки из него снова открывают книгу.
            NoticeCenter.shared.show("Выделение удалено") {
                try await database.addHighlight(deleted)
            }
        }
    }

    /// Комментарий к выделению: показывается в списке выделений, на странице книги и находится поиском.
    func setNote(_ note: String, of id: UUID) {
        let database = database
        Task {
            await NoticeCenter.shared.attempt("Не удалось сохранить комментарий") {
                try await database.setHighlightNote(id, note: note)
            }
        }
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
        noteActivity()
        if let readingSession, readingSession.seconds >= 1 {
            try? await database.saveReadingSession(readingSession)
        }
        if hasRestoredPosition {
            try? await database.saveReadingPosition(sourceId, locator: readingLocator, progress: progress)
        }
        await notes?.flush()
    }
}

private extension Highlight {
    /// Совпадает ли выделение с только что выделенным местом.
    func matches(_ other: SourceLocator, text: String) -> Bool {
        self.text == text
            && locator.section == other.section
            && locator.textOffset == other.textOffset
            && locator.rects?.first?.page == other.rects?.first?.page
    }
}

extension ReaderModel {
    /// Стрелки на клавиатуре: экран текста (на краю главы соседняя глава) или страница PDF.
    func turnPage(forward: Bool) {
        switch content {
        case .web: web.turn(forward: forward)
        case .pdf: pdf.step(forward: forward)
        default: break
        }
    }
}
