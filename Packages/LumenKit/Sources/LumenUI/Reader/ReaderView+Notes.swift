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

    func notesPane(_ notes: PageEditorModel?) -> some View {
        VStack(spacing: 0) {
            notesHeader(notes, closes: true)
            notesBody(notes)
        }
        .readerGlassCard(theme)
    }

    /// Редактор открытой заметки. Пока к книге не завели ни одной заметки, вместо него
    /// приглашение начать: заметка появится в библиотеке рядом с книгой только после нажатия.
    @ViewBuilder
    func notesBody(_ notes: PageEditorModel?) -> some View {
        if let notes {
            PageEditorView(model: notes, onOpenPage: openSidePage, onOpenSource: openSource)
                .id(notes.pageId)
        } else {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(ReaderStyle.peach)
                Text("Заметок к книге пока нет")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text("Заметка появится там же, где лежит книга, когда вы её начнёте")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: 280)
                Button {
                    LumenSounds.play(.create)
                    Task { await model.ensureNotes() }
                } label: {
                    Label("Начать заметку", systemImage: "plus")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(ReaderStyle.onPeach)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(ReaderStyle.peach, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Шапка панели заметок: какая заметка открыта и кнопка выбрать другую.
    func notesHeader(_ notes: PageEditorModel?, closes: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                isPagePickerPresented.toggle()
            } label: {
                HStack(spacing: 7) {
                    if let notes, !model.showsBookNotes {
                        Text(notes.page?.icon ?? "📄")
                        Text(notes.isLoaded ? sideTitle(notes) : "").lineLimit(1)
                    } else {
                        Image(systemName: "book")
                        Text("Заметки к книге").lineLimit(1)
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
                    currentPageId: notes?.pageId,
                    bookNotesPageId: model.bookNotesPageId,
                    onOpen: openSidePage,
                    onOpenBookNotes: {
                        isPagePickerPresented = false
                        LumenSounds.play(.navigate)
                        Task { await model.openBookNotes() }
                    },
                    onCreate: {
                        isPagePickerPresented = false
                        Task { await model.createSidePage() }
                    }
                )
                .presentationCompactAdaptation(.sheet)
            }
            Spacer(minLength: 4)
            if let notes, notes.isLoaded, !notes.isNotebook, notes.sheetCount > 1 {
                // Листы заметки: номера прокручивают к листу, «+» добавляет новый.
                SheetPager(
                    count: notes.sheetCount,
                    current: notes.visibleSheet,
                    onSelect: { notes.sheetScrollRequest = $0 },
                    onAdd: { notes.addSheet() }
                )
            }
            if let notes, notes.isLoaded, !notes.isNotebook {
                InputModeToggle(isPen: notes.activeDrawingId != nil) { pen in
                    LumenSounds.play(.toggle)
                    if pen { notes.startPenAtEnd() } else { notes.stopDrawing() }
                }
            }
            if model.canLinkPlace {
                headerButton("bookmark", help: "Вставить в заметку ссылку на это место в книге") {
                    Task { await model.addPlaceLink() }
                }
                .contextMenu {
                    Button {
                        model.copyPlaceLink()
                    } label: {
                        Label("Скопировать ссылку на это место", systemImage: "link")
                    }
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
            } else if let notes {
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

    /// Ручка в зазоре между книгой и заметками: тянется, чтобы поменять ширину колонок
    /// (или высоту листов, когда заметки под книгой). Двойной щелчок возвращает как было.
    func splitHandle(axis: PaneArrangement.Axis, length: CGFloat) -> some View {
        PaneDivider(
            axis: axis,
            isActive: isHandleHovered || dragStartFraction != nil,
            label: axis == .stacked ? "Высота заметок" : "Ширина заметок"
        ) { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHandleHovered = hovering }
        }
        .gesture(
            // Сдвиг мыши считается в координатах окна. В своих координатах ручка уезжает
            // вместе с мышью, сдвиг выходил то больше, то меньше, и колонки дёргались туда-сюда.
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartFraction ?? arrangement.fraction(for: axis)
                    if dragStartFraction == nil { dragStartFraction = start }
                    let fraction = PaneArrangement.dragged(
                        from: start,
                        delta: Double(axis == .stacked ? value.translation.height : value.translation.width),
                        length: Double(length),
                        axis: axis,
                        isSwapped: arrangement.isSwapped
                    )
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { dragFraction = fraction }
                }
                .onEnded { _ in
                    if let dragFraction { arrangement.setFraction(dragFraction, for: axis) }
                    dragFraction = nil
                    dragStartFraction = nil
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.snappy) {
                arrangement.setFraction(PaneArrangement().fraction(for: axis), for: axis)
            }
        }
        .help(axis == .stacked
            ? "Потяните, чтобы поменять высоту книги и заметок. Двойной щелчок возвращает как было"
            : "Потяните, чтобы поменять ширину книги и заметок. Двойной щелчок возвращает как было")
    }

    func setNotes(_ isOpen: Bool) {
        LumenSounds.play(isOpen ? .panelOpen : .panelClose)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            showsNotes = isOpen
        }
    }
}

/// «Текст / Пером» в шапке заметок: писать с клавиатуры или рисовать в конце заметки.
private struct InputModeToggle: View {
    let isPen: Bool
    var onChange: (_ pen: Bool) -> Void

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            segment("Текст", "textformat", selected: !isPen) { onChange(false) }
            segment("Пером", "pencil.tip", selected: isPen) { onChange(true) }
        }
        .padding(2)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private func segment(_ title: String, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? ReaderStyle.onPeach : theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(selected ? AnyShapeStyle(ReaderStyle.peach) : AnyShapeStyle(.clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title == "Пером" ? "Рисовать в конце заметки пальцем, пером или мышью" : "Писать текстом")
    }
}
