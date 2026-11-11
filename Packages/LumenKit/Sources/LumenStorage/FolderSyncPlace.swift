import Foundation

/// Где лежит папка синхронизации: в iCloud Drive или нет, и как её назвать человеку.
public struct FolderSyncPlace: Sendable, Equatable {
    /// Папка в iCloud Drive: её содержимое само поедет на другие устройства Apple.
    public var isInICloudDrive: Bool
    /// Выбран сам iCloud Drive: на других устройствах его проще всего найти.
    public var isICloudDriveRoot: Bool
    /// Папка с данными, например «iCloud Drive/Lumen Sync».
    public var displayName: String
    /// Папка, которую выбрали (без «Lumen Sync»): её же нужно выбрать на других устройствах.
    public var pickedName: String

    /// Так называется iCloud Drive в системном пути: `…/Mobile Documents/com~apple~CloudDocs`.
    static let iCloudDriveComponent = "com~apple~CloudDocs"

    /// `dataFolder` это папка «Lumen Sync», см. `FolderSyncEngine.dataFolder(in:)`.
    public init(dataFolder: URL) {
        let parts = dataFolder.standardizedFileURL.pathComponents
        if let index = parts.lastIndex(of: Self.iCloudDriveComponent) {
            let inside = Array(parts[(index + 1)...])
            isInICloudDrive = true
            isICloudDriveRoot = inside == [FolderSyncEngine.folderName]
            displayName = (["iCloud Drive"] + inside).joined(separator: "/")
            pickedName = (["iCloud Drive"] + Self.droppingDataFolder(inside)).joined(separator: "/")
        } else {
            isInICloudDrive = false
            isICloudDriveRoot = false
            displayName = parts.suffix(2).joined(separator: "/")
            pickedName = Self.droppingDataFolder(parts).last ?? displayName
        }
    }

    private static func droppingDataFolder(_ parts: [String]) -> [String] {
        parts.last == FolderSyncEngine.folderName ? Array(parts.dropLast()) : parts
    }
}

/// Что сказать человеку о синхронизации через папку: связались ли устройства и что сделать дальше.
public enum FolderSyncAdvice: Sendable, Equatable {
    /// Первый круг ещё идёт: другие устройства пока не искали.
    case checking
    /// В папке есть другие устройства.
    case connected(devices: [String])
    /// Других устройств в папке нет: их нужно включить так же.
    case waitingForOthers(pickedName: String, isICloudDriveRoot: Bool)
    /// Папка не в iCloud Drive, и других устройств в ней нет: скорее всего, она только на этом устройстве.
    case notInCloud

    public static func make(place: FolderSyncPlace, otherDevices: [FolderSyncDevice], hasSynced: Bool) -> Self {
        if !otherDevices.isEmpty {
            var seen = Set<String>()
            return .connected(devices: otherDevices.map(\.name).filter { seen.insert($0).inserted })
        }
        if !place.isInICloudDrive { return .notInCloud }
        if !hasSynced { return .checking }
        return .waitingForOthers(pickedName: place.pickedName, isICloudDriveRoot: place.isICloudDriveRoot)
    }

    public var isConnected: Bool {
        if case .connected = self { true } else { false }
    }

    public var title: String {
        switch self {
        case .checking: "Ищу другие устройства…"
        case .connected(let devices): "Связано: \(devices.joined(separator: ", "))"
        case .waitingForOthers: "Осталось включить на другом устройстве"
        case .notInCloud: "Эта папка не в iCloud Drive"
        }
    }

    public var text: String {
        switch self {
        case .checking:
            "Lumen смотрит, что уже лежит в папке. Это займёт несколько секунд."
        case .connected:
            "Правки сами приходят и уходят, пока Lumen открыт. Большие книги iCloud иногда везёт несколько минут."
        case .waitingForOthers(let pickedName, let isRoot):
            if isRoot {
                "Откройте Lumen на iPhone, iPad или другом Mac и нажмите «Включить синхронизацию». Если спросят папку, выберите сам iCloud Drive. Первые заметки iCloud может везти несколько минут."
            } else {
                "Откройте Lumen на iPhone, iPad или другом Mac, нажмите «Включить синхронизацию» и выберите ту же папку: \(pickedName). Первые заметки iCloud может везти несколько минут."
            }
        case .notInCloud:
            "Если это не папка Dropbox или другого облака, заметки останутся только на этом устройстве. Надёжнее выбрать сам iCloud Drive."
        }
    }
}
