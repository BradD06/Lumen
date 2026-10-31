import LumenCore
import LumenReader
import LumenStorage
import LumenThemes
import SwiftUI

/// Лист с книгой: сама книга, полоса глав внизу, масштаб PDF и нижняя панель на iPhone.
extension ReaderView {
    // MARK: Книга

    private var isWebContent: Bool {
        if case .web = model.content { return true }
        return false
    }

    /// Темы страницы работают для книг в HTML и для PDF.
    var hasPageThemes: Bool {
        isWebContent || model.content == .pdf
    }

    /// Цвет листа, на котором лежит книга.
    private var sheetColors: [Color] {
        switch model.content {
        case .web:
            return appearance.palette.sheetColors
        case .pdf:
            let backdrop = Color(hex: appearance.palette.pdfStyle.backdrop)
            return [backdrop, backdrop]
        default:
            return [theme.cardFill.opacity(0.7), theme.cardFill.opacity(0.5)]
        }
    }

    /// Цвет подписей поверх листа: тёмный на светлой бумаге, светлый ночью.
    var ink: Color {
        if case .web = model.content { return appearance.palette.ink }
        if model.content == .pdf, appearance.palette != .original { return appearance.palette.ink }
        return theme.textPrimary
    }

    /// Полоса глав стоит под текстом, а не поверх него, поэтому никогда не закрывает строки.
    /// Поверх книги всплывают только временные плашки: выделение, уведомление.
    func readerPane(tocOverlay: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    document
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 10) {
                        if let toast = model.toast {
                            Label(toast, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if model.selection != nil {
                            SelectionBar(model: model, isCompact: isCompact)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if let id = model.activeHighlightId, let highlight = model.highlights.first(where: { $0.id == id }) {
                            HighlightBar(model: model, highlight: highlight, isCompact: isCompact)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, isCompact ? 10 : 18)
                    .padding(.bottom, isCompact ? 10 : 16)
                    .animation(.spring(duration: 0.3), value: model.selection)
                    .animation(.spring(duration: 0.3), value: model.activeHighlightId)
                    .animation(.spring(duration: 0.3), value: model.toast)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .readerSheet(sheetColors, radius: isCompact ? 30 : ReaderStyle.sheetRadius)
            .overlay(alignment: .leading) {
                // На узком окне содержание плавает над книгой и не сдвигает текст.
                if tocOverlay, showsToc, !model.toc.isEmpty, !isCompact {
                    tableOfContents
                        .frame(width: 280)
                        .frame(maxHeight: .infinity)
                        .padding(12)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            if isCompact {
                dock
            }
        }
    }

    var tableOfContents: some View {
        TableOfContents(model: model) {
            LumenSounds.play(.panelClose)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { showsToc = false }
        }
    }

    @ViewBuilder
    private var document: some View {
        switch model.content {
        case .loading:
            ProgressView("Открываю…")
                .tint(ReaderStyle.peach)
        case .web:
            WebReaderView(controller: model.web)
        case .pdf:
            PDFReaderView(controller: model.pdf)
        case .image:
            if let source = model.source {
                ScrollView([.horizontal, .vertical]) {
                    AttachmentImage(name: source.file, attachments: model.database.attachments)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(24)
                }
            }
        case .quickLook(let url):
            QuickLookView(url: url)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не открывается", systemImage: "book.closed")
            } description: {
                Text(message)
            } actions: {
                Button("В библиотеку", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderStyle.peachDeep)
            }
        }
    }

    /// Мягкая полоса внизу листа, под текстом: главы, прогресс и место в книге.
    /// На iPhone без названия главы, чтобы влезли стрелки.
    @ViewBuilder
    private var footer: some View {
        let sections = model.sections
        switch model.content {
        case .web, .pdf:
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            HStack(spacing: 12) {
                if sections.count > 1 {
                    Button {
                        model.openSection(model.section - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(SheetRoundButtonStyle(ink: ink))
                    .disabled(model.section == 0)
                    .help("Предыдущая глава")
                }
                if !isCompact, let title = model.currentTocEntry?.title {
                    Text(title)
                        .lineLimit(1)
                        .frame(maxWidth: 170, alignment: .leading)
                }
                SoftProgressTrack(progress: model.progress, marks: sections.count <= 30 ? sections.count : 0, ink: ink)
                    .frame(minWidth: 80)
                Text(model.positionLabel)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                if model.content == .pdf {
                    zoomControls
                }
                if sections.count > 1 {
                    Button {
                        model.openSection(model.section + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(SheetRoundButtonStyle(ink: ink))
                    .disabled(model.section >= sections.count - 1)
                    .help("Следующая глава")
                }
            }
            .font(.system(size: isCompact ? 12 : 13, weight: .bold, design: .rounded))
            .foregroundStyle(ink.opacity(0.68))
            .padding(.horizontal, isCompact ? 8 : 12)
            .padding(.vertical, isCompact ? 7 : 10)
            .background(ink.opacity(0.07), in: shape)
            .frame(maxWidth: 680)
            .padding(.horizontal, isCompact ? 10 : 18)
            .padding(.top, 6)
            .padding(.bottom, isCompact ? 10 : 16)
        default:
            EmptyView()
        }
    }

    /// Масштаб PDF: мельче, по ширине, крупнее и замок, который фиксирует масштаб для этой книги.
    /// На iPhone только проценты и замок: приближают там щипком.
    private var zoomControls: some View {
        HStack(spacing: 6) {
            if !isCompact {
                Button {
                    model.zoom(in: false)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(SheetRoundButtonStyle(ink: ink))
                .keyboardShortcut("-", modifiers: .command)
                .help("Мельче (⌘−)")
            }
            Button {
                model.zoomToFit()
            } label: {
                Text(ReaderModel.percent(model.pdfScale))
                    .monospacedDigit()
                    .frame(minWidth: 40)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("0", modifiers: .command)
            .help("По ширине окна (⌘0)")
            if !isCompact {
                Button {
                    model.zoom(in: true)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(SheetRoundButtonStyle(ink: ink))
                .keyboardShortcut("=", modifiers: .command)
                .help("Крупнее (⌘+)")
            }
            Button {
                model.toggleZoomLock()
            } label: {
                Image(systemName: model.isZoomLocked ? "lock.fill" : "lock.open")
            }
            .buttonStyle(SheetRoundButtonStyle(ink: model.isZoomLocked ? ReaderStyle.peachDeep : ink))
            .help(model.isZoomLocked ? "Масштаб зафиксирован. Нажмите, чтобы отпустить" : "Зафиксировать масштаб для этой книги")
            .accessibilityLabel(model.isZoomLocked ? "Отпустить масштаб" : "Зафиксировать масштаб")
        }
    }

    /// Нижняя панель на iPhone: всё под большим пальцем.
    private var dock: some View {
        HStack(spacing: 0) {
            Button {
                toggleToc()
            } label: {
                Label("Содержание", systemImage: "list.bullet.indent")
            }
            .disabled(model.toc.isEmpty)
            Spacer(minLength: 0)
            Button {
                isAppearancePresented = true
            } label: {
                Label("Оформление", systemImage: "textformat.size")
            }
            .disabled(!hasPageThemes)
            .popover(isPresented: $isAppearancePresented) { appearancePanel }
            Spacer(minLength: 0)
            ProgressRing(progress: model.progress)
            Spacer(minLength: 0)
            Button {
                showsHighlights = true
            } label: {
                Label("Выделения", systemImage: "highlighter")
            }
            .popover(isPresented: $showsHighlights) { highlightsList }
            Spacer(minLength: 0)
            Button {
                toggleNotes()
            } label: {
                Label("Заметки", systemImage: "note.text")
            }
        }
        .buttonStyle(ReaderRoundButtonStyle(size: 44, tint: theme.textPrimary))
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 10)
        .frame(height: 60)
        .frame(maxWidth: 440)
        .background(theme.cardFill.opacity(0.55), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
            lineWidth: 1
        ))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
    }

    var appearancePanel: some View {
        ReaderAppearancePanel(paletteRaw: $paletteRaw, fontSize: $fontSize, typefaceRaw: $typefaceRaw, showsTextOptions: isWebContent)
            .presentationDetents([.height(isWebContent ? 340 : 190)])
            .presentationCornerRadius(34)
            .presentationCompactAdaptation(.sheet)
    }

    var highlightsList: some View {
        HighlightsList(model: model) { showsHighlights = false }
            .frame(minWidth: 320, minHeight: 360)
            .presentationCornerRadius(34)
            .presentationCompactAdaptation(.sheet)
    }
}
