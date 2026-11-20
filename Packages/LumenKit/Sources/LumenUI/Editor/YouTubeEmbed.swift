import Foundation
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI
import WebKit

// Видео с YouTube в заметке: блок «Видео» со ссылкой (`content.bookmark`) вместо файла.
// Пока ролик не включили, видна картинка-превью; проигрыватель (WKWebView) создаётся только по нажатию,
// так что десяток роликов в заметке не замедляет её открытие и прокрутку.

// MARK: Модель

extension PageEditorModel {
    /// Ссылка на ролик YouTube в блоке: блок становится «Видео» с проигрывателем.
    /// Возвращает false, если это не ссылка на ролик.
    @discardableResult
    func setVideoLink(_ id: UUID, address: String) -> Bool {
        guard let link = YouTubeLink(string: address), findBlock(id) != nil else { return false }
        recordUndo()
        update(id) {
            $0.type = .video
            $0.content.runs = []
            $0.content.attachment = nil
            $0.content.file = nil
            $0.content.bookmark = WebBookmark(url: link.watchURL.absoluteString, siteName: "YouTube")
        }
        return true
    }

    /// В пустой абзац вставили одну ссылку на ролик: он становится видео, как в Notion,
    /// а курсор встаёт в новый абзац под ним. ⌘Z возвращает ссылку текстом.
    func pasteVideoLink(_ id: UUID, to source: String) -> Bool {
        guard let block = findBlock(id), block.type == .paragraph, block.text.isEmpty,
              source.count > 1, YouTubeLink(string: source) != nil else { return false }
        // Сначала ссылка встаёт текстом отдельным шагом, чтобы ⌘Z вернул именно её.
        recordUndo(typing: .block(id))
        update(id) { $0.content.runs = InlineMarkup.runs(from: source) }
        setVideoLink(id, address: source)
        focusRequest = insertBlock(after: id, type: .paragraph).id
        return true
    }

    /// Название, автор и превью ролика. Без сети видео остаётся со ссылкой и запасной картинкой.
    func loadVideoInfo(_ id: UUID) async {
        guard let bookmark = findBlock(id)?.content.bookmark, let link = YouTubeLink(string: bookmark.url) else { return }
        let info = await YouTubeInfoLoader.load(link, attachments: database.attachments, needsThumbnail: bookmark.image == nil)
        // Пока грузилось, ссылку могли поменять: старое не нужно.
        guard var current = findBlock(id)?.content.bookmark, current.url == bookmark.url else {
            if let thumbnail = info.thumbnail { database.attachments.remove(thumbnail) }
            return
        }
        current.title = info.title ?? current.title
        current.summary = info.author ?? current.summary
        current.image = info.thumbnail ?? current.image
        guard current != bookmark else { return }
        update(id) { $0.content.bookmark = current }
    }
}

/// Название и автор из oEmbed YouTube, картинка-превью во вложения (чтобы была видна без сети).
enum YouTubeInfoLoader {
    struct Info: Sendable {
        var title: String?
        var author: String?
        var thumbnail: String?
    }

    private struct OEmbed: Decodable {
        var title: String?
        var author_name: String?
    }

    static func load(_ link: YouTubeLink, attachments: AttachmentStore, needsThumbnail: Bool) async -> Info {
        async let meta = oEmbed(link)
        var thumbnail: String?
        if needsThumbnail {
            thumbnail = await downloadThumbnail(link, attachments: attachments)
        }
        let loaded = await meta
        return Info(title: loaded?.title, author: loaded?.author_name, thumbnail: thumbnail)
    }

    private static func oEmbed(_ link: YouTubeLink) async -> OEmbed? {
        guard let (data, response) = try? await URLSession.shared.data(from: link.oEmbedURL),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
        return try? JSONDecoder().decode(OEmbed.self, from: data)
    }

    /// Самое крупное превью, какое есть у ролика (у старых нет большого, тогда 404).
    private static func downloadThumbnail(_ link: YouTubeLink, attachments: AttachmentStore) async -> String? {
        for url in link.thumbnailURLs {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  !data.isEmpty, data.count <= WebPreviewLoader.maxImageBytes else { continue }
            if let name = try? attachments.save(data, fileExtension: "jpg") { return name }
        }
        return nil
    }
}

// MARK: Блок

/// Ролик в заметке: превью с кнопкой, по нажатию проигрыватель YouTube прямо в блоке.
/// Под ним название, автор и «На YouTube».
struct YouTubeBlock: View {
    let block: Block
    let link: YouTubeLink
    let model: PageEditorModel

    @State private var isPlaying = false
    @Environment(\.openURL) private var openURL
    @Environment(\.lumenTheme) private var theme

    /// Ролики, для которых в этот запуск уже спрашивали название: без сети не стучаться при каждой прокрутке.
    @MainActor private static var requested: Set<UUID> = []

    private var bookmark: WebBookmark? { block.content.bookmark }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if isPlaying {
                    YouTubeWebPlayer(url: link.embedURL(origin: YouTubeWebPlayer.origin))
                } else {
                    poster
                }
            }
            .aspectRatio(1 / link.aspect, contentMode: .fit)
            .frame(maxHeight: 520)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            caption
        }
        .task(id: block.id) {
            guard bookmark?.title == nil || bookmark?.image == nil, !Self.requested.contains(block.id) else { return }
            Self.requested.insert(block.id)
            await model.loadVideoInfo(block.id)
        }
        .onChange(of: link) { isPlaying = false }
        // Ушёл с экрана: проигрыватель закрывается, звук не играет из невидимой заметки.
        .onDisappear { isPlaying = false }
    }

    private var poster: some View {
        Button {
            isPlaying = true
        } label: {
            theme.surface2
                .overlay {
                    if let image = bookmark?.image {
                        AttachmentImage(name: image, attachments: model.database.attachments, contentMode: .fill, maxPixelSize: 1600)
                    } else {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 40))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .clipped()
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 68, height: 48)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .overlay(alignment: .bottomTrailing) {
                    if let start = link.startText {
                        Text("с \(start)")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(theme.onAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.accent, in: Capsule())
                            .padding(10)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Смотреть здесь")
        .keyHint("Смотреть видео") { isPlaying = true }
    }

    private var caption: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark?.title ?? "Видео YouTube")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                openURL(link.watchURL)
            } label: {
                Label("На YouTube", systemImage: "arrow.up.right")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(link.watchURL.absoluteString)
            .keyHint("Открыть на YouTube") { openURL(link.watchURL) }
        }
        .padding(.horizontal, 4)
    }

    private var subtitle: String {
        [bookmark?.summary, link.startText.map { "с \($0)" }, "YouTube"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Поле под «Выбрать видео»: вместо файла можно дать ссылку на YouTube.
struct YouTubeAddressField: View {
    let blockId: UUID
    let model: PageEditorModel

    @State private var address = ""
    @State private var isInvalid = false
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(theme.textSecondary)
                TextField("Или вставьте ссылку на YouTube и нажмите Return", text: $address)
                    .textFieldStyle(.plain)
                    .onSubmit(add)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Добавить", action: add)
                    .buttonStyle(.bordered)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if isInvalid {
                Text("Это не ссылка на ролик YouTube")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .onChange(of: address) { isInvalid = false }
    }

    private func add() {
        isInvalid = !model.setVideoLink(blockId, address: address)
    }
}

// MARK: Проигрыватель

/// Встроенный проигрыватель YouTube. Страница с iframe грузится с адресом приложения:
/// без него YouTube не показывает ролик в приложениях (ошибка 153, нужен Referer).
/// Ссылки из проигрывателя (название, логотип) открываются в браузере, а не внутри блока.
#if os(macOS)
struct YouTubeWebPlayer: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> YouTubePlayerCoordinator { YouTubePlayerCoordinator() }

    func makeNSView(context: Context) -> WKWebView {
        Self.makeWebView(url: url, coordinator: context.coordinator)
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static func dismantleNSView(_ view: WKWebView, coordinator: YouTubePlayerCoordinator) {
        // Звук не должен доигрывать из убранного блока.
        view.loadHTMLString("", baseURL: nil)
    }
}

/// Прокрутка колёсиком над роликом листает заметку, а не застревает в проигрывателе.
final class PassScrollWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
#else
struct YouTubeWebPlayer: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> YouTubePlayerCoordinator { YouTubePlayerCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        Self.makeWebView(url: url, coordinator: context.coordinator)
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: YouTubePlayerCoordinator) {
        view.loadHTMLString("", baseURL: nil)
    }
}
#endif

extension YouTubeWebPlayer {
    /// Адрес приложения, от имени которого встроен ролик: `https://` и идентификатор приложения,
    /// как YouTube просит у приложений.
    static var origin: String {
        "https://" + (Bundle.main.bundleIdentifier ?? "io.github.bradd06.lumen").lowercased()
    }

    @MainActor
    static func makeWebView(url: URL, coordinator: YouTubePlayerCoordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Ролик включают нажатием на превью, так что сразу играет.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        #if os(macOS)
        let view = PassScrollWebView(frame: .zero, configuration: configuration)
        #else
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        view.loadHTMLString(html(for: url), baseURL: URL(string: origin + "/"))
        return view
    }

    static func html(for url: URL) -> String {
        let source = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return """
            <!doctype html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="referrer" content="strict-origin-when-cross-origin">
            <style>html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
            iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }</style>
            </head><body>
            <iframe src="\(source)" allow="autoplay; encrypted-media; picture-in-picture; fullscreen; web-share"
              allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
            </body></html>
            """
    }
}

/// Внутри блока остаётся только проигрыватель: переходы и новые окна уходят в браузер.
@MainActor
final class YouTubePlayerCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              navigationAction.targetFrame?.isMainFrame == true else { return .allow }
        if url.scheme == "about" || url.absoluteString.hasPrefix(YouTubeWebPlayer.origin) { return .allow }
        Self.openOutside(url)
        return .cancel
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { Self.openOutside(url) }
        return nil
    }

    private static func openOutside(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
