import AVKit
import LumenCore
import LumenThemes
import PDFKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Блоки «Файл», «PDF», «Видео» и «Аудио». Пока файла нет, блок предлагает выбрать его
/// или перетащить. Файл копируется во вложения и ездит между устройствами вместе с заметкой.
struct FileBlock: View {
    let block: Block
    let model: PageEditorModel

    @State private var isImporting = false
    @State private var isDropTarget = false
    @State private var previewURL: URL?
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if let file = block.content.file, block.content.attachment != nil {
                if let url = model.attachmentURL(of: block) {
                    content(file: file, url: url)
                } else {
                    // С другого устройства пришла заметка, а сам файл ещё в пути.
                    FileCard(file: file, subtitle: "Файл ещё не загрузился на это устройство", isDimmed: true)
                }
            } else {
                picker
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.contentTypes(block.type)) { result in
            guard case .success(let url) = result else { return }
            Task { await model.attachFile(block.id, from: url) }
        }
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private func content(file: FileAttachment, url: URL) -> some View {
        switch block.type {
        case .pdf:
            VStack(alignment: .leading, spacing: 8) {
                FileCard(file: file, subtitle: file.sizeText, isCompact: true) { previewURL = url }
                PDFEmbed(url: url)
                    .frame(height: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        case .video:
            VideoBlockPlayer(url: url)
        case .audio:
            AudioBlockPlayer(url: url, title: file.name)
        default:
            FileCard(file: file, subtitle: file.sizeText) { previewURL = url }
        }
    }

    private var picker: some View {
        HStack(spacing: 12) {
            Image(systemName: block.type.symbolName)
                .font(.title2)
                .foregroundStyle(theme.textSecondary)
            Button {
                isImporting = true
            } label: {
                Label(pickerTitle, systemImage: "folder")
            }
            .buttonStyle(.bordered)
            Text("или перетащите сюда")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 0)
        }
        .lumenCard(padding: 14)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.accent, lineWidth: 2)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.isFileURL && PageEditorModel.acceptsFile($0, for: block.type) }) else { return false }
            Task { await model.attachFile(block.id, from: url) }
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private var pickerTitle: String {
        switch block.type {
        case .pdf: "Выбрать PDF"
        case .video: "Выбрать видео"
        case .audio: "Выбрать аудио"
        default: "Выбрать файл"
        }
    }

    static func contentTypes(_ type: BlockType) -> [UTType] {
        switch type {
        case .pdf: [.pdf]
        case .video: [.movie, .video]
        case .audio: [.audio]
        default: [.item]
        }
    }
}

/// Карточка файла: значок, имя и размер. Нажатие открывает быстрый просмотр.
struct FileCard: View {
    let file: FileAttachment
    var subtitle: String?
    var isCompact = false
    var isDimmed = false
    var onOpen: (() -> Void)?

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: file.symbolName)
                    .font(isCompact ? .body : .title2)
                    .foregroundStyle(theme.accent)
                    .frame(width: isCompact ? 22 : 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(isCompact ? .subheadline.weight(.medium) : .body.weight(.medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if onOpen != nil, !isCompact {
                    Image(systemName: "eye")
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
        .opacity(isDimmed ? 0.6 : 1)
        .help("Открыть файл")
        .modifier(FileCardBackground(isCompact: isCompact))
    }
}

private struct FileCardBackground: ViewModifier {
    let isCompact: Bool

    func body(content: Content) -> some View {
        if isCompact {
            content
        } else {
            content.lumenCard(padding: 12)
        }
    }
}

// MARK: PDF

#if os(macOS)
/// PDF в заметке: листается прямо в блоке, по ширине блока.
struct PDFEmbed: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }

    private func configure(_ view: PDFView) {
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
    }
}
#else
struct PDFEmbed: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#endif

// MARK: Видео

/// Видео со своим проигрывателем. Высота по форме кадра, не выше 520 пунктов.
struct VideoBlockPlayer: View {
    let url: URL

    @State private var player: AVPlayer
    @State private var aspect: Double = 9.0 / 16.0

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(1 / aspect, contentMode: .fit)
            .frame(maxHeight: 520)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: url) {
                let asset = AVURLAsset(url: url)
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                   let loaded = try? await track.load(.naturalSize, .preferredTransform) {
                    let shown = loaded.0.applying(loaded.1)
                    let width = abs(shown.width)
                    let height = abs(shown.height)
                    if width > 0, height > 0 { aspect = min(max(height / width, 0.3), 2) }
                }
            }
            .onDisappear { player.pause() }
    }
}

// MARK: Аудио

/// Аудио: кнопка, полоса с перемоткой и время.
struct AudioBlockPlayer: View {
    let url: URL
    let title: String

    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @Environment(\.lumenTheme) private var theme

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Пауза" : "Слушать")
            .keyHint(isPlaying ? "Пауза" : "Слушать") { toggle() }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Slider(value: $position, in: 0...max(duration, 0.1), onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                    }
                })
                .controlSize(.small)
                HStack {
                    Text(Self.time(position))
                    Spacer()
                    Text(Self.time(duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
            }
        }
        .lumenCard(padding: 12)
        .task(id: url) {
            if let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite {
                duration = seconds
            }
            // Полоса идёт за звуком, пока блок на экране.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                let current = player.currentTime().seconds
                if !isScrubbing, current.isFinite { position = current }
                let playing = player.timeControlStatus == .playing
                if playing != isPlaying { isPlaying = playing }
                if duration > 0, current >= duration - 0.05, !playing, position > 0 {
                    position = duration
                }
            }
        }
        .onDisappear { player.pause() }
    }

    private func toggle() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, position >= duration - 0.05 {
                player.seek(to: .zero)
                position = 0
            }
            player.play()
            isPlaying = true
        }
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

// MARK: Закладка

/// Закладка на сайт: карточка с названием, описанием, значком и картинкой, как в Notion.
/// Пустая закладка показывает поле для адреса.
struct BookmarkBlock: View {
    let block: Block
    let model: PageEditorModel

    @State private var address = ""
    @State private var isLoading = false
    @State private var isInvalid = false
    @FocusState private var isAddressFocused: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if let bookmark = block.content.bookmark {
            card(bookmark)
        } else {
            addressField
        }
    }

    private var addressField: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(theme.textSecondary)
            TextField("Вставьте ссылку на сайт и нажмите Return", text: $address)
                .textFieldStyle(.plain)
                .focused($isAddressFocused)
                .onSubmit(add)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button("Добавить", action: add)
                    .buttonStyle(.bordered)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .lumenCard(padding: 12)
        .overlay(alignment: .bottomLeading) {
            if isInvalid {
                Text("Это не похоже на адрес сайта")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .offset(x: 14, y: 18)
            }
        }
        .onAppear { isAddressFocused = true }
        .onChange(of: address) { isInvalid = false }
    }

    private func add() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let added = await model.setBookmark(block.id, address: address)
            isLoading = false
            isInvalid = !added
        }
    }

    private func card(_ bookmark: WebBookmark) -> some View {
        Button {
            if let url = URL(string: bookmark.url) { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bookmark.title ?? bookmark.host)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let summary = bookmark.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 6) {
                        if let icon = bookmark.icon {
                            AttachmentImage(name: icon, attachments: model.database.attachments, maxPixelSize: 64)
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        } else {
                            Image(systemName: "globe")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Text(bookmark.siteName ?? bookmark.host)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
                if let image = bookmark.image {
                    AttachmentImage(name: image, attachments: model.database.attachments, contentMode: .fill, maxPixelSize: 600)
                        .frame(width: 128, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(bookmark.url)
        .lumenCard(padding: 12)
    }
}
