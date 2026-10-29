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

    /// Копирует файл под новым уникальным именем с тем же расширением. Книги бывают большими,
    /// поэтому файл копируется, а не читается в память.
    public func importFile(at source: URL) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = UUID().uuidString
        let fileExtension = source.pathExtension
        if !fileExtension.isEmpty {
            name += ".\(fileExtension.lowercased())"
        }
        try FileManager.default.copyItem(at: source, to: url(for: name))
        return name
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    public func url(for name: String) -> URL {
        // Только имя файла: вложение не может указывать за пределы папки.
        folder.appendingPathComponent((name as NSString).lastPathComponent)
    }

    public func data(for name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }
}
