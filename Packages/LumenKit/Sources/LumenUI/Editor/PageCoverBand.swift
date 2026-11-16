import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Обложка над листами заметки: лист лежит на её нижнем крае. Справа сверху кнопки
/// «Ракурс», «Сменить» и «Убрать». В режиме ракурса картинку тянут мышью или пальцем
/// (щипком или ползунком меняют размер), внизу выбирают высоту полосы и жмут «Готово».
struct PageCoverBand<ChangeMenu: View>: View {
    let model: PageEditorModel
    let cover: PageCover
    let scroll: PageScrollOffset
    @Binding var isAdjusting: Bool
    /// Кнопки над обложкой. В неактивной панели разделённого экрана их нет.
    var showsControls: Bool
    var isCompact: Bool
    @ViewBuilder var changeMenu: () -> ChangeMenu

    @Environment(\.lumenTheme) private var theme
    /// Сколько картинки скрыто: его читает только перетаскивание, поэтому не `@State`-значение.
    @State private var layoutBox = GeometryBox<CoverLayout?>(nil)
    /// Можно ли двигать картинку: меняется, только когда ответ другой.
    @State private var canMove = false
    /// Ракурс в начале жеста: от него считается сдвиг.
    @State private var gestureStart: CoverCrop?
    /// Увеличение в начале щипка.
    @State private var zoomStart: Double?

    private var crop: CoverCrop { model.page?.pageCoverCrop ?? CoverCrop() }

    private var isImage: Bool {
        if case .image = cover { return true }
        return false
    }

    #if os(macOS)
    /// Над картинкой, которую можно тянуть, курсор-ладонь.
    private var grabPointer: PointerStyle? {
        guard isAdjusting, isImage, canMove else { return nil }
        return gestureStart == nil ? PointerStyle.grabIdle : PointerStyle.grabActive
    }
    #endif

    var body: some View {
        ScrolledPageCover(
            scroll: scroll,
            cover: cover,
            attachments: model.database.attachments,
            crop: crop
        ) { layout in
            layoutBox.value = layout
            if canMove != layout.canMove { canMove = layout.canMove }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(drag, including: isAdjusting && isImage ? .all : .subviews)
        .simultaneousGesture(magnify, including: isAdjusting && isImage ? .all : .subviews)
        #if os(macOS)
        .pointerStyle(grabPointer)
        #endif
        .overlay {
            if isAdjusting, isImage, gestureStart == nil {
                hint
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsControls, !isAdjusting {
                controls
                    .padding(.top, isCompact ? 10 : 14)
                    .padding(.trailing, isCompact ? 12 : 20)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if isAdjusting {
                adjustBar
                    .padding(.bottom, 12)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(LumenMotion.standard, value: isAdjusting)
        .animation(LumenMotion.quick, value: gestureStart == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Обложка")
    }

    // MARK: Кнопки

    private var controls: some View {
        HStack(spacing: 2) {
            Button {
                isAdjusting = true
            } label: {
                Label("Ракурс", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .contentShape(Capsule())
            }
            .help(isImage ? "Подвинуть картинку и выбрать высоту обложки" : "Выбрать высоту обложки")
            .keyHint("Ракурс обложки") { isAdjusting = true }
            .accessibilityIdentifier("cover.adjust")

            Menu {
                changeMenu()
            } label: {
                Text("Сменить")
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .contentShape(Capsule())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Другая обложка: горы, цвет или своё фото")

            Button {
                model.setCover(nil)
            } label: {
                Text("Убрать")
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .contentShape(Capsule())
            }
            .help("Убрать обложку")
            .keyHint("Убрать обложку") { model.setCover(nil) }
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(theme.textPrimary)
        .padding(3)
        .lumenGlass(Capsule())
    }

    private var hint: some View {
        Label(
            canMove ? "Тяните картинку, чтобы выбрать ракурс" : "Увеличьте картинку, чтобы её двигать",
            systemImage: "hand.draw"
        )
        .font(.callout.weight(.medium))
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .lumenGlass(Capsule())
        .allowsHitTesting(false)
    }

    /// Полоса внизу обложки в режиме ракурса: размер картинки, высота полосы, «По центру», «Готово».
    private var adjustBar: some View {
        let layout = isCompact ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if isImage {
                HStack(spacing: 8) {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundStyle(theme.textSecondary)
                    Slider(
                        value: Binding(
                            get: { crop.zoom },
                            set: { zoom in
                                var updated = crop
                                updated.zoom = zoom
                                model.setCoverCrop(updated, save: false)
                            }
                        ),
                        in: CoverCrop.minZoom...CoverCrop.maxZoom,
                        onEditingChanged: { isEditing in
                            if !isEditing { model.setCoverCrop(crop) }
                        }
                    )
                    .frame(minWidth: 120, maxWidth: 200)
                    .accessibilityLabel("Размер картинки")
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(theme.textSecondary)
                }
            }
            HStack(spacing: 10) {
                Picker("Высота", selection: Binding(
                    get: { crop.height },
                    set: { height in
                        var updated = crop
                        updated.height = height
                        withAnimation(LumenMotion.standard) { model.setCoverCrop(updated) }
                    }
                )) {
                    ForEach(CoverCrop.Height.allCases, id: \.self) { height in
                        Text(height.title).tag(height)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Высота обложки")

                if isImage {
                    Button("По центру") {
                        withAnimation(LumenMotion.standard) {
                            model.setCoverCrop(CoverCrop(height: crop.height))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textPrimary)
                    .keyHint("Обложка по центру") { model.setCoverCrop(CoverCrop(height: crop.height)) }
                }

                Button {
                    isAdjusting = false
                } label: {
                    Text("Готово")
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyHint("Готово") { isAdjusting = false }
                .accessibilityIdentifier("cover.done")
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .lumenGlass(Capsule(), prominent: true)
    }

    // MARK: Жесты

    /// Тянут картинку: показывается то, что было за краем полосы.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = gestureStart ?? crop
                if gestureStart == nil { gestureStart = start }
                guard let layout = layoutBox.value else { return }
                let moved = start.dragged(
                    dx: value.translation.width,
                    dy: value.translation.height,
                    spanX: layout.spanX,
                    spanY: layout.spanY
                )
                model.setCoverCrop(moved, save: false)
            }
            .onEnded { _ in
                gestureStart = nil
                model.setCoverCrop(crop)
            }
    }

    /// Щипок на тачпаде или экране: картинка крупнее или мельче.
    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? crop.zoom
                if zoomStart == nil { zoomStart = start }
                var zoomed = crop
                zoomed.zoom = min(max(start * value.magnification, CoverCrop.minZoom), CoverCrop.maxZoom)
                model.setCoverCrop(zoomed, save: false)
            }
            .onEnded { _ in
                zoomStart = nil
                model.setCoverCrop(crop)
            }
    }
}

/// Сама картинка обложки. Прокрутку читает только она: горы темнеют, когда лист уезжает вверх,
/// а остальная обложка с кнопками на каждом кадре прокрутки не пересобирается.
private struct ScrolledPageCover: View {
    let scroll: PageScrollOffset
    let cover: PageCover
    let attachments: AttachmentStore
    let crop: CoverCrop
    let onLayout: (CoverLayout) -> Void

    var body: some View {
        PageCoverView(
            cover: cover,
            attachments: attachments,
            sunset: scroll.offset / 220,
            crop: crop,
            onLayout: onLayout
        )
    }
}
