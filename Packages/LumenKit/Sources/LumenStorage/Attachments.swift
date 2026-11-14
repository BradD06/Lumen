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

    /// Размер файла в байтах; `nil`, если файла здесь нет (например, ещё не доехал с другого устройства).
    public func fileSize(_ name: String) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: name).path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    /// Одинаковы ли два вложения байт в байт.
    public func sameContent(_ a: String, _ b: String) -> Bool {
        Self.sameContent(url(for: a), url(for: b))
    }

    /// Одинаковы ли два файла байт в байт. Сначала размер, потом содержимое по кускам:
    /// книга бывает большой, целиком в память её не читаем.
    public static func sameContent(_ a: URL, _ b: URL) -> Bool {
        let sizeA = (try? FileManager.default.attributesOfItem(atPath: a.path))?[.size] as? NSNumber
        let sizeB = (try? FileManager.default.attributesOfItem(atPath: b.path))?[.size] as? NSNumber
        guard let sizeA, let sizeB, sizeA == sizeB else { return false }
        guard let first = try? FileHandle(forReadingFrom: a), let second = try? FileHandle(forReadingFrom: b) else { return false }
        defer {
            try? first.close()
            try? second.close()
        }
        do {
            while true {
                let left = try first.read(upToCount: 1 << 20) ?? Data()
                let right = try second.read(upToCount: 1 << 20) ?? Data()
                guard left == right else { return false }
                if left.isEmpty { return true }
            }
        } catch {
            return false
        }
    }

    public func data(for name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }
}
