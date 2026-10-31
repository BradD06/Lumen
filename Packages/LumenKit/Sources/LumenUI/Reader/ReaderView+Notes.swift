import LumenCore
import LumenReader
import LumenStorage
import LumenThemes
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Заметки рядом с книгой: панель, её шапка и ручка, которой меняют ширину.
extension ReaderView {
    // MARK: Заметки

    func notesPane(_ notes: PageEditorModel) -> some View {
        VStack(spacing: 0) {
            notesHeader(notes, closes: true)
            PageEditorView(model: notes, onOpenPage: openSidePage, onOpenSource: openSource)
                .id(notes.pageId)
        }
        .readerGlassCard(theme)
    }

    /// Шапка панели заметок: какая заметка открыта и кнопка выбрать другую.
    func notesHeader(_ notes: PageEditorModel, closes: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                isPagePickerPresented.toggle()
            } label: {
                HStack(spacing: 7) {
                    if model.showsBookNotes {
                        Image(systemName: "book")
                        Text("Заметки к книге").lineLimit(1)
                    } else {
                        Text(notes.page?.icon ?? "📄")
                        Text(notes.isLoaded ? sideTitle(notes) : "").lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(theme.textSecondary)
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .padding(.leading, 11)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Открыть рядом другую заметку")
            .popover(isPresented: $isPagePickerPresented, arrowEdge: .bottom) {
                SidePagePicker(
                    database: model.database,
                    source: model.source,
                    currentPageId: notes.pageId,
                    bookNotesPageId: model.bookNotesPageId,
                    onOpen: openSidePage,
                    onCreate: {
                        isPagePickerPresented = false
                        Task { await model.createSidePage() }
                    }
                )
                .presentationCompactAdaptation(.sheet)
            }
            Spacer(minLength: 4)
            if model.canLinkPlace {
                headerButton("bookmark", help: "Вставить в заметку ссылку на это место в книге") {
                    model.addPlaceLink()
                }
            }
            if model.showsBookNotes {
                if !model.highlights.isEmpty {
                    Text(Self.highlightsCount(model.highlights.count))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(ReaderStyle.peach)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ReaderStyle.peach.opacity(0.16), in: Capsule())
                }
            } else {
                headerButton("book", help: "Вернуться к заметкам к книге") {
                    LumenSounds.play(.navigate)
                    Task { await model.openBookNotes() }
                }
                headerButton("arrow.up.forward", help: "Открыть заметку целиком") {
                    openPage(notes.pageId)
                }
            }
            if closes {
                headerButton("xmark", help: "Скрыть заметки") { setNotes(false) }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// «1 выделение», «3 выделения», «7 выделений».
    nonisolated static func highlightsCount(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        let word: String
        if mod10 == 1, mod100 != 11 {
            word = "выделение"
        } else if (2...4).contains(mod10), !(12...14).contains(mod100) {
            word = "выделения"
        } else {
            word = "выделений"
        }
        return "\(count) \(word)"
    }

    private func sideTitle(_ notes: PageEditorModel) -> String {
        let title = notes.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Без названия" : title
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Ручка в зазоре между книгой и заметками: тянется, чтобы поменять ширину колонок.
    func splitHandle(totalWidth: CGFloat) -> some View {
        Capsule()
            .fill(theme.textSecondary.opacity(isHandleHovered || dragStartFraction != nil ? 0.6 : 0.22))
            .frame(width: 4, height: 40)
            .frame(width: ReaderStyle.gap)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHandleHovered = hovering }
                #if os(macOS)
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                #endif
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartFraction ?? notesFraction
                        if dragStartFraction == nil { dragStartFraction = start }
                        notesFraction = min(max(start - value.translation.width / max(totalWidth, 1), 0.25), 0.65)
                    }
                    .onEnded { _ in dragStartFraction = nil }
            )
            .accessibilityLabel("Ширина заметок")
    }

    func setNotes(_ isOpen: Bool) {
        LumenSounds.play(isOpen ? .panelOpen : .panelClose)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            showsNotes = isOpen
        }
    }
}
