import Foundation

/// Папка с файлами-вложениями. Блоки и обложки хранят только имя файла.
public struct AttachmentStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Временная папка для тестов и превью.
    public static func temporary() -> AttachmentStore {
        AttachmentStore(
            folder: FileManager.default.temporaryDirectory
                .appendingPathComponent("LumenAttachments-\(UUID().uuidString)", isDirectory: true)
        )
    }

    /// Сохраняет данные под новым уникальным именем и возвращает это имя.
    public func save(_ data: Data, fileExtension: String? = nil) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = UUID().uuidString
        if let fileExtension, !fileExtension.isEmpty {
            name += ".\(fileExtension.lowercased())"
        }
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    public func url(for name: String) -> URL {
        // Только имя файла: вложение не может указывать за пределы папки.
        folder.appendingPathComponent((name as NSString).lastPathComponent)
    }

    public func data(for name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }
}
