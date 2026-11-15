import Foundation
import LumenCore
import LumenStorage

/// Файлы, PDF, видео, аудио и закладки на сайты в заметке.
extension PageEditorModel {
    /// Какие файлы подходят блоку.
    static func acceptsFile(_ url: URL, for type: BlockType) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch type {
        case .pdf: return ext == "pdf"
        case .video: return FileAttachment.symbolName(forExtension: ext) == "film"
        case .audio: return FileAttachment.symbolName(forExtension: ext) == "waveform"
        default: return true
        }
    }

    /// Копирует файл во вложения и показывает его в блоке. Большое видео копируется не в главном потоке.
    func attachFile(_ id: UUID, from url: URL) async {
        guard findBlock(id) != nil else { return }
        let attachments = database.attachments
        do {
            let name = try await Task.detached {
                let isScoped = url.startAccessingSecurityScopedResource()
                defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
                return try attachments.importFile(at: url)
            }.value
            let file = FileAttachment(name: url.lastPathComponent, size: attachments.fileSize(name))
            guard findBlock(id) != nil else {
                attachments.remove(name)
                return
            }
            recordUndo()
            update(id) {
                $0.content.attachment = name
                $0.content.file = file
            }
        } catch {
            NoticeCenter.shared.report("Не удалось добавить файл", error)
        }
    }

    /// Адрес файла блока, если файл уже есть на этом устройстве (с другого мог ещё не доехать).
    func attachmentURL(of block: Block) -> URL? {
        guard let name = block.content.attachment else { return nil }
        let url = database.attachments.url(for: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Блок снова пустой, чтобы выбрать другой файл или адрес. Файл остаётся во вложениях,
    /// чтобы отмена вернула его.
    func removeAttachment(_ id: UUID) {
        guard let block = findBlock(id), block.content.attachment != nil || block.content.bookmark != nil else { return }
        recordUndo()
        update(id) {
            $0.content.attachment = nil
            $0.content.file = nil
            $0.content.bookmark = nil
        }
    }

    // MARK: Закладки

    /// Закладка на сайт по введённому адресу. Возвращает false, если это не адрес.
    @discardableResult
    func setBookmark(_ id: UUID, address: String) async -> Bool {
        guard let url = WebBookmark.normalizedURL(address), findBlock(id) != nil else { return false }
        recordUndo()
        update(id) { $0.content.bookmark = WebBookmark(url: url.absoluteString) }
        await loadBookmarkPreview(id)
        return true
    }

    /// Название, описание, картинка и значок сайта. Без сети закладка остаётся просто адресом.
    func loadBookmarkPreview(_ id: UUID) async {
        guard let bookmark = findBlock(id)?.content.bookmark, let url = URL(string: bookmark.url) else { return }
        let attachments = database.attachments
        guard let loaded = await WebPreviewLoader.load(url, attachments: attachments) else { return }
        // Пока грузилось, адрес могли поменять: старое превью не нужно.
        guard var current = findBlock(id)?.content.bookmark, current.url == bookmark.url else { return }
        current.title = loaded.title ?? current.title
        current.summary = loaded.summary ?? current.summary
        current.siteName = loaded.siteName ?? current.siteName
        current.image = loaded.image ?? current.image
        current.icon = loaded.icon ?? current.icon
        update(id) { $0.content.bookmark = current }
    }
}

/// Загрузка превью сайта: HTML страницы, из него `WebPreview`, картинка и значок во вложения.
enum WebPreviewLoader {
    struct Loaded: Sendable {
        var title: String?
        var summary: String?
        var siteName: String?
        var image: String?
        var icon: String?
    }

    /// Самая большая картинка превью, которую стоит скачивать.
    static let maxImageBytes = 5 * 1024 * 1024

    static func load(_ url: URL, attachments: AttachmentStore) async -> Loaded? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        // Многие сайты отдают превью только браузерам.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        let finalURL = response.url ?? url
        let mime = (response as? HTTPURLResponse)?.mimeType?.lowercased() ?? "text/html"
        guard mime.contains("html") else {
            return Loaded(title: finalURL.lastPathComponent.isEmpty ? nil : finalURL.lastPathComponent)
        }
        let html = decode(data, encodingName: response.textEncodingName)
        let preview = WebPreview.parse(html: html, baseURL: finalURL)
        async let image = download(preview.imageURL, attachments: attachments)
        async let icon = download(preview.iconURL, attachments: attachments)
        return await Loaded(title: preview.title, summary: preview.summary, siteName: preview.siteName, image: image, icon: icon)
    }

    /// Текст страницы: кодировка из ответа или из `<meta charset>`, иначе UTF-8 или Windows-1251.
    static func decode(_ data: Data, encodingName: String?) -> String {
        var names = [encodingName?.lowercased()]
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        if let range = head.range(of: "charset=") {
            let rest = head[range.upperBound...].drop { $0 == "\"" || $0 == "'" }
            names.append(String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }))
        }
        for name in names.compactMap({ $0 }) {
            let encoding: String.Encoding? = switch name {
            case "utf-8", "utf8": .utf8
            case "windows-1251", "cp1251": .windowsCP1251
            case "koi8-r": String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)))
            case "iso-8859-1", "latin1": .isoLatin1
            default: nil
            }
            if let encoding, let text = String(data: data, encoding: encoding) { return text }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) ?? ""
    }

    private static func download(_ url: URL?, attachments: AttachmentStore) async -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              !data.isEmpty, data.count <= maxImageBytes else { return nil }
        let mime = (response as? HTTPURLResponse)?.mimeType?.lowercased() ?? ""
        guard mime.isEmpty || mime.hasPrefix("image/") else { return nil }
        let ext = switch mime {
        case "image/png": "png"
        case "image/jpeg", "image/jpg": "jpg"
        case "image/gif": "gif"
        case "image/webp": "webp"
        case "image/svg+xml": "svg"
        case "image/x-icon", "image/vnd.microsoft.icon": "ico"
        default: url.pathExtension.isEmpty ? "img" : url.pathExtension
        }
        // SVG картинкой не показать.
        guard ext != "svg" else { return nil }
        return try? attachments.save(data, fileExtension: ext)
    }
}
