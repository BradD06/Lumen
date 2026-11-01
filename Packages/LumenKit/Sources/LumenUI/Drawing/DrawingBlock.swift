import LumenCore
import LumenThemes
import PencilKit
import SwiftUI

/// Блок «Рисунок» внутри обычной заметки: область, где пишут от руки. Высоту области
/// меняют, потянув за полоску снизу. Пока в области не рисуют, она только показывает
/// рисунок, и страницу можно листать прямо по нему. Нажатие начинает рисование.
///
/// Если область уже холста (например, в узкой панели разделённого экрана), рисунок
/// уменьшается целиком вместе с высотой области, а не обрезается справа.
struct DrawingBlock: View {
    let block: Block
    let model: PageEditorModel

    /// Высота во время перетаскивания полоски. В модель она уходит, когда полоску отпустили.
    @State private var resizingHeight: Double?
    @State private var resizeStart: Double?
    /// Ширина области на экране. До первого замера рисунок в натуральную величину.
    @State private var availableWidth: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.lumenTheme) private var theme

    private var isEditing: Bool { model.activeDrawingId == block.id }
    private var isDark: Bool { colorScheme == .dark }
    /// Высота области в пунктах рисунка. На экране она умножается на `scale`.
    private var height: Double { resizingHeight ?? DrawingArea.height(of: block.content) }
    private var canvasWidth: Double { block.content.drawingWidth ?? DrawingInkWidthCache.width(of: block) }
    private var scale: Double { DrawingArea.scale(canvasWidth: canvasWidth, available: availableWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                editingBar
            }
            GeometryReader { geometry in
                surface(size: geometry.size, scale: scale)
            }
            .frame(height: height * scale)
            .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { availableWidth = $0 }
            .background(theme.cardFill.opacity(isEditing ? 0.55 : 0.3), in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isEditing ? theme.accent.opacity(0.7) : theme.textSecondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: isEditing ? 1.5 : 1, dash: isEditing ? [] : [5, 4])
                )
            }
            resizeHandle
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Рисунок")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    @ViewBuilder
    private func surface(size: CGSize, scale: Double) -> some View {
        // Видимая часть рисунка в его координатах: при уменьшении она шире области.
        let rect = CGRect(x: 0, y: 0, width: size.width / scale, height: size.height / scale)
        let visibleWidth = Double(rect.width)
        if isEditing {
            #if os(iOS)
            PencilCanvas(
                data: block.drawing,
                isDrawingEnabled: true,
                showsToolPicker: true,
                isDark: isDark,
                notebook: nil,
                areaZoom: scale,
                onChange: { model.setDrawing(block.id, data: $0, visibleWidth: visibleWidth) }
            )
            #else
            ZStack {
                DrawingImageView(data: block.drawing, rect: rect, isDark: isDark)
                MouseDrawingLayer(
                    drawing: DrawingSupport.drawing(from: block.drawing),
                    scale: scale,
                    isDark: isDark,
                    onChange: { drawing, isNewStep in
                        model.setDrawing(
                            block.id,
                            data: DrawingSupport.data(of: drawing),
                            recordsUndo: isNewStep,
                            visibleWidth: visibleWidth
                        )
                    }
                )
            }
            #endif
        } else {
            ZStack {
                DrawingImageView(data: block.drawing, rect: rect, isDark: isDark)
                if block.drawing == nil {
                    Label(Self.emptyHint, systemImage: "pencil.and.scribble")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                LumenSounds.play(.tap)
                model.startDrawing(block.id)
            }
            .help("Нажмите, чтобы рисовать")
        }
    }

    private static var emptyHint: String {
        #if os(iOS)
        "Нажмите и пишите пальцем или Apple Pencil"
        #else
        "Нажмите и рисуйте мышью или трекпадом"
        #endif
    }

    /// Над областью, пока в ней рисуют: перо (на Mac) и «Готово».
    private var editingBar: some View {
        HStack(spacing: 10) {
            #if os(macOS)
            MouseInkBar()
            #else
            Label("Рисование", systemImage: "pencil.and.scribble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            #endif
            Spacer(minLength: 0)
            if block.drawing != nil {
                Button {
                    model.clearDrawing(block.id)
                } label: {
                    Label("Очистить", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .help("Стереть весь рисунок")
            }
            Button {
                model.stopDrawing()
            } label: {
                Text("Готово").fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    /// Полоска снизу: потяните вверх или вниз, чтобы поменять высоту области.
    private var resizeHandle: some View {
        Capsule()
            .fill(theme.textSecondary.opacity(resizingHeight == nil ? 0.35 : 0.7))
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = resizeStart ?? DrawingArea.height(of: block.content)
                        resizeStart = start
                        resizingHeight = DrawingArea.clampedHeight(start + value.translation.height / scale)
                    }
                    .onEnded { _ in
                        if let resizingHeight {
                            model.setDrawingHeight(block.id, resizingHeight)
                        }
                        resizingHeight = nil
                        resizeStart = nil
                    }
            )
            #if os(macOS)
            .pointerStyle(.rowResize)
            #endif
            .help("Потяните, чтобы поменять высоту области")
            .accessibilityLabel("Высота области рисунка")
            .accessibilityValue("\(Int(height)) пунктов")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.setDrawingHeight(block.id, height + 80)
                case .decrement: model.setDrawingHeight(block.id, height - 80)
                @unknown default: break
                }
            }
    }
}

/// Ширина рисунков, сделанных до того, как ширина холста стала запоминаться: её считают
/// по штрихам один раз на каждую версию рисунка, а не при каждой перерисовке.
@MainActor
private enum DrawingInkWidthCache {
    private static var widths: [UUID: (data: Data, width: Double)] = [:]

    static func width(of block: Block) -> Double {
        guard let data = block.drawing else { return 0 }
        if let cached = widths[block.id], cached.data == data { return cached.width }
        let width = DrawingSupport.inkWidth(of: data) ?? 0
        widths[block.id] = (data, width)
        return width
    }
}
