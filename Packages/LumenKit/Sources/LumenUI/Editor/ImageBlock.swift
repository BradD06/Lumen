import ImageIO
import LumenCore
import LumenThemes
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Блок-картинка. Пока картинка не выбрана, показывает кнопки выбора из фото и файлов.
///
/// Размер меняют ручками, как в Notion: справа ширина (форма сохраняется), снизу высота,
/// в углу и то и другое. Если форма не как у снимка, картинка заполняет рамку и обрезается по краям.
/// На Mac ручки видны при наведении, на iPhone и iPad по нажатию на картинку.
struct ImageBlock: View {
    let block: Block
    let model: PageEditorModel

    @State private var photo: PhotosPickerItem?
    @State private var isImportingFile = false
    /// Ширина строки, в которой стоит картинка.
    @State private var availableWidth: CGFloat = 0
    /// Высота на ширину самого снимка.
    @State private var naturalAspect: Double?
    @State private var isHovered = false
    @State private var showsHandles = false
    /// Размер во время перетаскивания ручки. В модель он уходит, когда ручку отпустили.
    @State private var liveSize: CGSize?
    @State private var dragStart: CGSize?
    @Environment(\.lumenTheme) private var theme

    private enum ResizeEdge {
        case width, height, corner
    }

    init(block: Block, model: PageEditorModel) {
        self.block = block
        self.model = model
        let aspect = block.content.attachment.flatMap { ImageAspectCache.values[model.database.attachments.url(for: $0).path] }
        _naturalAspect = State(initialValue: aspect)
    }

    var body: some View {
        Group {
            if let name = block.content.attachment {
                picture(name)
            } else {
                picker
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.setImage(block.id, data: data, fileExtension: nil)
                }
                photo = nil
            }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                model.setImage(block.id, data: data, fileExtension: url.pathExtension)
            }
        }
    }

    /// Размер картинки на экране. Пока ширина строки не измерена, `nil`.
    private var displaySize: CGSize? {
        if let liveSize { return liveSize }
        guard availableWidth > 0 else { return nil }
        let size = ImageSizing.size(
            widthShare: block.content.imageWidth,
            aspect: block.content.imageAspect,
            natural: naturalAspect,
            available: Double(availableWidth)
        )
        return CGSize(width: size.width, height: size.height)
    }

    private var handlesVisible: Bool {
        #if os(macOS)
        isHovered || liveSize != nil
        #else
        showsHandles || liveSize != nil
        #endif
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    private func picture(_ name: String) -> some View {
        let size = displaySize
        return AttachmentImage(name: name, attachments: model.database.attachments, contentMode: size == nil ? .fit : .fill)
            .frame(width: size?.width, height: size?.height)
            .frame(maxWidth: size == nil ? .infinity : nil, maxHeight: size == nil ? CGFloat(ImageSizing.defaultMaxHeight) : nil, alignment: .leading)
            .clipShape(shape)
            .overlay {
                if handlesVisible, let size {
                    handles(size)
                        .transition(.opacity)
                }
            }
            .animation(LumenMotion.quick, value: handlesVisible)
            .onHover { isHovered = $0 }
            #if os(iOS)
            .onTapGesture {
                withAnimation(LumenMotion.quick) { showsHandles.toggle() }
            }
            #endif
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .task(id: name) {
                let url = model.database.attachments.url(for: name)
                if let cached = ImageAspectCache.values[url.path] {
                    naturalAspect = cached
                    return
                }
                let aspect = await Task.detached { ImageAspectCache.read(url) }.value
                if let aspect {
                    ImageAspectCache.values[url.path] = aspect
                }
                naturalAspect = aspect
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Картинка")
    }

    /// Ручки по краям картинки. Они лежат внутри её рамки: снаружи клики забрало бы поле соседнего блока.
    private func handles(_ size: CGSize) -> some View {
        ZStack {
            handle(.width, size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            handle(.height, size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            handle(.corner, size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            if let liveSize {
                Text("\(Int(liveSize.width.rounded())) × \(Int(liveSize.height.rounded()))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.accent, in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handle(_ edge: ResizeEdge, size: CGSize) -> some View {
        knob(edge, size: size)
            .padding(6)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture(edge))
            #if os(macOS)
            .pointerStyle(pointer(edge))
            #endif
            .help(help(edge))
            .accessibilityElement()
            .accessibilityLabel(help(edge))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.1 : -0.1
                switch edge {
                case .width, .corner:
                    let share = min(max((block.content.imageWidth ?? Double(size.width / max(availableWidth, 1))) + step, 0.1), 1)
                    model.setImageSize(block.id, widthShare: share, aspect: block.content.imageAspect)
                case .height:
                    let aspect = ImageSizing.clampAspect(Double(size.height / max(size.width, 1)) * (1 + step))
                    model.setImageSize(block.id, widthShare: block.content.imageWidth, aspect: aspect)
                }
            }
    }

    @ViewBuilder
    private func knob(_ edge: ResizeEdge, size: CGSize) -> some View {
        switch edge {
        case .width:
            Capsule()
                .fill(theme.accent)
                .overlay(Capsule().strokeBorder(theme.onAccent.opacity(0.8), lineWidth: 1))
                .frame(width: 6, height: min(44, max(size.height * 0.35, 16)))
                .frame(width: 18, height: max(min(size.height * 0.6, 120), 24))
        case .height:
            Capsule()
                .fill(theme.accent)
                .overlay(Capsule().strokeBorder(theme.onAccent.opacity(0.8), lineWidth: 1))
                .frame(width: min(44, max(size.width * 0.35, 16)), height: 6)
                .frame(width: max(min(size.width * 0.6, 160), 24), height: 18)
        case .corner:
            Circle()
                .fill(theme.accent)
                .overlay(Circle().strokeBorder(theme.onAccent.opacity(0.8), lineWidth: 1.5))
                .frame(width: 14, height: 14)
                .frame(width: 22, height: 22)
        }
    }

    private func resizeGesture(_ edge: ResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard let current = displaySize, current.width > 0 else { return }
                let start = dragStart ?? current
                dragStart = start
                let maxWidth = max(availableWidth, CGFloat(ImageSizing.minWidth))
                func clampWidth(_ width: CGFloat) -> CGFloat {
                    min(max(width, min(CGFloat(ImageSizing.minWidth), maxWidth)), maxWidth)
                }
                func clampHeight(_ height: CGFloat) -> CGFloat {
                    min(max(height, CGFloat(ImageSizing.minHeight)), CGFloat(ImageSizing.maxHeight))
                }
                var width = start.width
                var height = start.height
                switch edge {
                case .width:
                    width = clampWidth(start.width + value.translation.width)
                    height = width * start.height / start.width
                case .height:
                    height = clampHeight(start.height + value.translation.height)
                case .corner:
                    width = clampWidth(start.width + value.translation.width)
                    height = clampHeight(start.height + value.translation.height)
                }
                liveSize = CGSize(width: width, height: height)
            }
            .onEnded { _ in
                if let liveSize {
                    let stored = ImageSizing.stored(
                        width: Double(liveSize.width),
                        height: Double(liveSize.height),
                        available: Double(availableWidth),
                        natural: naturalAspect,
                        keepsShape: edge == .width,
                        currentAspect: block.content.imageAspect
                    )
                    model.setImageSize(block.id, widthShare: stored.widthShare, aspect: stored.aspect)
                }
                liveSize = nil
                dragStart = nil
            }
    }

    #if os(macOS)
    private func pointer(_ edge: ResizeEdge) -> PointerStyle {
        switch edge {
        case .width: .columnResize
        case .height: .rowResize
        case .corner: .frameResize(position: .bottomTrailing)
        }
    }
    #endif

    private func help(_ edge: ResizeEdge) -> String {
        switch edge {
        case .width: "Потяните, чтобы поменять ширину картинки"
        case .height: "Потяните, чтобы поменять высоту картинки"
        case .corner: "Потяните, чтобы поменять ширину и высоту"
        }
    }

    private var picker: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(theme.textSecondary)
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Выбрать фото", systemImage: "photo.on.rectangle")
            }
            Button {
                isImportingFile = true
            } label: {
                Label("Из файлов", systemImage: "folder")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .lumenCard(padding: 14)
    }
}

/// Пропорции картинок из вложений: читаются из заголовка файла, без раскодирования.
@MainActor
enum ImageAspectCache {
    static var values: [String: Double] = [:]

    /// Высота на ширину с учётом поворота снимка. `nil` для форматов, которые ImageIO не читает.
    nonisolated static func read(_ url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        // Ориентации 5–8 повёрнуты на четверть оборота: ширина и высота меняются местами.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? width / height : height / width
    }
}
