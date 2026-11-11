import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Комната «Доска»: пробковая доска, на которой книги, папки и листы приколоты кнопками,
/// а ссылки между ними натянуты красной ниткой. Нажали на карточку, и горят её нитки;
/// потянули нитку от кнопки к другой карточке, и в заметке появилась ссылка.
struct LinkBoardView: View {
    let database: AppDatabase

    @State private var model: LinkBoardModel
    @State private var isPicking = false
    @Environment(\.lumenTheme) private var theme
    @Environment(\.appActions) private var appActions
    @Environment(\.workspaceActions) private var workspaceActions

    init(database: AppDatabase) {
        self.database = database
        _model = State(initialValue: LinkBoardModel(database: database))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
            board
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(ThemedBackground())
        .navigationTitle("Доска связей")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isPicking) {
            BoardPinPicker(snapshot: model.snapshot) { items in
                isPicking = false
                model.pin(items)
            } onCancel: {
                isPicking = false
            }
        }
        .task { await model.observe() }
    }

    // MARK: Шапка

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                titleBlock
                Spacer(minLength: 12)
                controls
            }
            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                controls
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Доска связей")
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Потяните нитку от кнопки к другой карточке, и в заметке появится ссылка")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            chip("Всё", isOn: !model.onlyTheme) {
                withAnimation(LumenMotion.standard) { model.onlyTheme = false }
            }
            chip("Только эта тема", isOn: model.onlyTheme) {
                withAnimation(LumenMotion.standard) { model.onlyTheme = true }
            }
            .disabled(model.selection == nil)
            .help(model.selection == nil ? "Сначала нажмите на карточку" : "Показать только то, что связано с выбранной карточкой")

            Button {
                isPicking = true
            } label: {
                Label("Приколоть…", systemImage: "pin")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .foregroundStyle(theme.onAccent)
                    .background(theme.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyHint("Приколоть") { isPicking = true }
            .accessibilityIdentifier("board.pin")

            let linkedCount = model.snapshot.unpinnedLinkedItems.count
            Menu {
                Button {
                    model.pinAllLinked()
                } label: {
                    Label("Приколоть всё, что связано (\(linkedCount))", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(linkedCount == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Ещё")
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .foregroundStyle(isOn ? theme.accent : theme.textSecondary)
                .background(theme.cardFill.opacity(isOn ? 1 : 0.5), in: Capsule())
                .overlay(Capsule().strokeBorder(theme.accent.opacity(isOn ? 0.6 : 0.2), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyHint(title, perform: action)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Доска

    private var board: some View {
        let frame = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                let size = model.canvasSize(minimum: proxy.size)
                ZStack(alignment: .topLeading) {
                    CorkSurface()
                        .frame(width: size.width, height: size.height)
                        .onTapGesture { model.clearSelection() }
                    ForEach(model.snapshot.pins) { pin in
                        card(pin)
                    }
                    BoardThreads(lines: threadLines, draft: draftLine)
                        .frame(width: size.width, height: size.height)
                    ForEach(model.snapshot.pins) { pin in
                        pinHead(pin)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .coordinateSpace(.named(BoardSpace.name))
            }
            .scrollIndicators(.automatic)
            .keyHintClip()
        }
        .clipShape(frame)
        // Деревянная рамка с латунным отливом темы.
        .overlay(frame.strokeBorder(theme.accent.mix(with: Color(hex: 0x3A2618), by: 0.55), lineWidth: 10))
        .overlay(frame.inset(by: 10).strokeBorder(theme.contrast.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 14)
        .overlay {
            if model.isLoaded, model.snapshot.pins.isEmpty {
                emptyState
            }
        }
        .overlay(alignment: .bottom) {
            if let selection = model.selection {
                selectionBar(selection)
                    .padding(.bottom, 22)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var threadLines: [BoardThreadLine] {
        let visible = model.visibleItems
        var lines: [BoardThreadLine] = []
        for thread in model.snapshot.threads {
            if let visible, !(visible.contains(thread.a) && visible.contains(thread.b)) { continue }
            guard let a = pinPoint(thread.a), let b = pinPoint(thread.b) else { continue }
            let emphasis: BoardThreadLine.Emphasis
            if let selection = model.selection {
                emphasis = thread.touches(selection) ? .strong : .faint
            } else {
                emphasis = .normal
            }
            lines.append(BoardThreadLine(id: thread.id, from: a, to: b, emphasis: emphasis, isContainment: thread.isContainmentOnly))
        }
        return lines
    }

    private var draftLine: BoardThreadDraftLine? {
        guard let draft = model.draft, let from = pinPoint(draft.from) else { return nil }
        let to = draft.target.flatMap { pinPoint($0) } ?? draft.point
        return BoardThreadDraftLine(from: from, to: to, hasTarget: draft.target != nil)
    }

    private func pinPoint(_ item: LibraryItemID) -> CGPoint? {
        guard let pin = model.snapshot.pins.first(where: { $0.item == item }) else { return nil }
        return BoardCardMetrics.pinPoint(center: model.point(of: pin), kind: pin.kind)
    }

    @ViewBuilder
    private func card(_ pin: BoardPin) -> some View {
        let item = pin.item
        let isMoving = model.moving?.item == item
        if let content = BoardCardContent(pin: pin, snapshot: model.snapshot) {
            BoardCard(
                content: content,
                attachments: database.attachments,
                isSelected: model.selection == item,
                isDimmed: model.isDimmed(item),
                threadCount: model.selection == item ? model.threadCount(of: item) : nil
            )
            .rotationEffect(.degrees(isMoving ? 0 : BoardCardMetrics.tilt(pin.id)))
            .scaleEffect(isMoving ? 1.05 : 1)
            // Карточку берут в руку плавно: выпрямляется и чуть подрастает.
            .animation(LumenMotion.quick, value: isMoving)
            .contentShape(Rectangle())
            .gesture(moveGesture(item))
            .onTapGesture(count: 2) { open(item) }
            .onTapGesture { model.toggleSelection(item) }
            .contextMenu { menu(for: item) }
            .opacity(model.isVisible(item) ? 1 : 0)
            .allowsHitTesting(model.isVisible(item))
            .position(model.point(of: pin))
            .zIndex(isMoving ? 2 : model.selection == item ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(content.caption): \(content.title)")
            .accessibilityValue(BoardCard.threadText(model.threadCount(of: item)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.toggleSelection(item) }
            .accessibilityAction(named: "Открыть") { open(item) }
            .accessibilityAction(named: "Снять с доски") { model.unpin(item) }
            .accessibilityIdentifier("board.card")
        }
    }

    @ViewBuilder
    private func pinHead(_ pin: BoardPin) -> some View {
        let item = pin.item
        if model.isVisible(item) {
            BoardPinHead(isActive: model.draft?.from == item || model.draft?.target == item)
                .position(BoardCardMetrics.pinPoint(center: model.point(of: pin), kind: pin.kind))
                .gesture(threadGesture(item))
                .help("Потяните к другой карточке, чтобы связать")
                .accessibilityHidden(true)
        }
    }

    private func moveGesture(_ item: LibraryItemID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(BoardSpace.name))
            .onChanged { value in model.drag(item, by: value.translation) }
            .onEnded { _ in model.endDrag(item) }
    }

    private func threadGesture(_ item: LibraryItemID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BoardSpace.name))
            .onChanged { value in model.drawThread(from: item, to: value.location) }
            .onEnded { _ in model.finishThread() }
    }

    // MARK: Действия

    private func open(_ item: LibraryItemID) {
        LumenSounds.play(.navigate)
        appActions.open(sidebarItem(item))
    }

    private func sidebarItem(_ item: LibraryItemID) -> SidebarItem {
        switch item {
        case .page(let id): .page(id)
        case .source(let id): .source(id, highlight: nil)
        case .folder(let id): .library(id)
        }
    }

    @ViewBuilder
    private func menu(for item: LibraryItemID) -> some View {
        Button {
            open(item)
        } label: {
            Label("Открыть", systemImage: "arrow.up.forward.square")
        }
        if let workspaceActions {
            Button {
                workspaceActions.openBeside(sidebarItem(item))
            } label: {
                Label("Открыть рядом", systemImage: "rectangle.split.2x1")
            }
        }
        Button {
            model.pinRelated(of: item)
        } label: {
            Label("Приколоть связанное", systemImage: "point.3.connected.trianglepath.dotted")
        }
        Divider()
        Button(role: .destructive) {
            model.unpin(item)
        } label: {
            Label("Снять с доски", systemImage: "pin.slash")
        }
    }

    /// Выбранная карточка: что это, сколько у неё ниток и что с ней сделать.
    private func selectionBar(_ item: LibraryItemID) -> some View {
        let count = model.threadCount(of: item)
        let toPin = model.relatedToPinCount(of: item)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title(of: item))
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(BoardCard.threadText(count))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 8)
            if toPin > 0 {
                barButton("Приколоть связанное (\(toPin))", systemImage: "point.3.connected.trianglepath.dotted") {
                    model.pinRelated(of: item)
                }
            }
            barButton("Открыть", systemImage: "arrow.up.forward.square") { open(item) }
            barButton("Снять", systemImage: "pin.slash") { model.unpin(item) }
            Button {
                model.clearSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Снять выбор")
            .keyHint("Снять выбор") { model.clearSelection() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 640)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }

    private func barButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ViewThatFits {
                Label(title, systemImage: systemImage)
                Image(systemName: systemImage)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(theme.cardFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .keyHint(title, perform: action)
    }

    /// Пустая доска: что на ней будет и как начать.
    private var emptyState: some View {
        let linkedCount = model.snapshot.unpinnedLinkedItems.count
        return VStack(spacing: 14) {
            Image(systemName: "pin.fill")
                .font(.system(size: 30))
                .foregroundStyle(theme.accent)
            Text("Доска пока пустая")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Приколите книги, папки и листы. Ссылки между ними натянутся красной ниткой, и станет видно, как темы связаны.")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                if linkedCount > 0 {
                    Button {
                        model.pinAllLinked()
                    } label: {
                        Label("Приколоть всё, что связано (\(linkedCount))", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyHint("Приколоть всё") { model.pinAllLinked() }
                }
                Button {
                    isPicking = true
                } label: {
                    Label("Выбрать, что приколоть", systemImage: "pin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .keyHint("Выбрать") { isPicking = true }
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        .padding(24)
    }
}
