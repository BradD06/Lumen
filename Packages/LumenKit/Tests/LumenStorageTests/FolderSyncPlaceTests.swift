import Foundation
import Testing
import LumenStorage

/// Что Lumen говорит человеку после включения синхронизации через папку.
struct FolderSyncPlaceTests {
    let macDrive = URL(fileURLWithPath: "/Users/anna/Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    let phoneDrive = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

    @Test func iCloudDriveItselfIsTheRoot() {
        let place = FolderSyncPlace(dataFolder: FolderSyncEngine.dataFolder(in: macDrive))
        #expect(place.isInICloudDrive)
        #expect(place.isICloudDriveRoot)
        #expect(place.displayName == "iCloud Drive/Lumen Sync")
        #expect(place.pickedName == "iCloud Drive")
    }

    @Test func pickingLumenSyncInsideICloudDriveIsTheSameAsTheRoot() {
        let picked = phoneDrive.appendingPathComponent("Lumen Sync", isDirectory: true)
        let place = FolderSyncPlace(dataFolder: FolderSyncEngine.dataFolder(in: picked))
        #expect(place.isICloudDriveRoot)
        #expect(place.pickedName == "iCloud Drive")
    }

    @Test func subfolderOfICloudDriveIsNamedForOtherDevices() {
        let picked = phoneDrive.appendingPathComponent("Документы", isDirectory: true)
        let place = FolderSyncPlace(dataFolder: FolderSyncEngine.dataFolder(in: picked))
        #expect(place.isInICloudDrive)
        #expect(!place.isICloudDriveRoot)
        #expect(place.displayName == "iCloud Drive/Документы/Lumen Sync")
        #expect(place.pickedName == "iCloud Drive/Документы")
    }

    @Test func localFolderIsNotInTheCloud() {
        let picked = URL(fileURLWithPath: "/Users/anna/Documents/Заметки", isDirectory: true)
        let place = FolderSyncPlace(dataFolder: FolderSyncEngine.dataFolder(in: picked))
        #expect(!place.isInICloudDrive)
        #expect(place.displayName == "Заметки/Lumen Sync")
        #expect(place.pickedName == "Заметки")
    }

    @Test func adviceBeforeFirstRoundIsChecking() {
        let place = FolderSyncPlace(dataFolder: FolderSyncEngine.dataFolder(in: macDrive))
        #expect(FolderSyncAdvice.make(place: place, otherDevices: [], hasSynced: false) == .checking)
    }

    @Test func adviceWithoutOtherDevicesSaysWhatToDoNext() {
        let place = FolderSyncPlace(dataFolder: FolderSyncEngine.dataFolder(in: phoneDrive.appendingPathComponent("Документы")))
        let advice = FolderSyncAdvice.make(place: place, otherDevices: [], hasSynced: true)
        #expect(advice == .waitingForOthers(pickedName: "iCloud Drive/Документы", isICloudDriveRoot: false))
        #expect(advice.text.contains("iCloud Drive/Документы"))
        #expect(!advice.isConnected)
    }

    @Test func adviceNamesOtherDevicesOnce() {
        let place = FolderSyncPlace(dataFolder: FolderSyncEngine.dataFolder(in: macDrive))
        let devices = [
            FolderSyncDevice(id: "1", name: "iPhone", lastSeen: Date()),
            FolderSyncDevice(id: "2", name: "iPad", lastSeen: Date()),
            FolderSyncDevice(id: "3", name: "iPhone", lastSeen: Date()),
        ]
        let advice = FolderSyncAdvice.make(place: place, otherDevices: devices, hasSynced: true)
        #expect(advice == .connected(devices: ["iPhone", "iPad"]))
        #expect(advice.title == "Связано: iPhone, iPad")
        #expect(advice.isConnected)
    }

    @Test func localFolderWithoutDevicesWarns() {
        let place = FolderSyncPlace(dataFolder: URL(fileURLWithPath: "/Users/anna/Documents/Lumen Sync"))
        #expect(FolderSyncAdvice.make(place: place, otherDevices: [], hasSynced: true) == .notInCloud)
        // Dropbox или флешка, на которой уже есть другое устройство: значит, всё работает.
        let devices = [FolderSyncDevice(id: "1", name: "Mac", lastSeen: Date())]
        #expect(FolderSyncAdvice.make(place: place, otherDevices: devices, hasSynced: true).isConnected)
    }
}
