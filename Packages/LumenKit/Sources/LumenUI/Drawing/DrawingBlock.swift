import LumenCore
import LumenThemes
import PencilKit
import SwiftUI

/// Блок «Рисунок» внутри обычной заметки: область, где пишут от руки. Высоту области
/// меняют, потянув за полоску снизу. Пока в области не рисуют, она только показывает
/// рисунок, и страницу можно листать прямо по нему. Нажатие начинает рисование.
struct DrawingBlock: View {
    let block: Block
    let model: PageEditorModel

    /// Высота во время перетаскивания полоски. В модель она уходит, когда полоску отпустили.
    @State private var resizingHeight: Double?
    @State private var resizeStart: Double?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.lumenTheme) private var theme

    private var isEditing: Bool { model.activeDrawingId == block.id }
    private var isDark: Bool { colorScheme == .dark }
    private var height: Double { resizingHeight ?? DrawingArea.height(of: block.content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                editingBar
            }
            GeometryReader { geometry in
                surface(size: geometry.size)
            }
            .frame(height: height)
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
    private func surface(size: CGSize) -> some View {
        let rect = CGRect(origin: .zero, size: size)
        if isEditing {
            #if os(iOS)
            PencilCanvas(
                data: block.drawing,
                isDrawingEnabled: true,
                showsToolPicker: true,
                isDark: isDark,
                notebook: nil,
                onChange: { model.setDrawing(block.id, data: $0) }
            )
            #else
            ZStack {
                DrawingImageView(data: block.drawing, rect: rect, isDark: isDark)
                MouseDrawingLayer(
                    drawing: DrawingSupport.drawing(from: block.drawing),
                    isDark: isDark,
                    onChange: { drawing, isNewStep in
                        model.setDrawing(block.id, data: DrawingSupport.data(of: drawing), recordsUndo: isNewStep)
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
                        resizingHeight = DrawingArea.clampedHeight(start + value.translation.height)
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
