import Foundation
import ObjectiveC
import PencilKit

/// PencilKit сам откладывает сохранение своего состояния в настройки приложения (`PKReplicaManager`).
/// У процесса `swift test` нет bundle id, и это сохранение через несколько секунд роняет весь прогон
/// в случайном тесте («CFEqual() called with NULL first argument», сигнал 5). В приложении bundle id есть,
/// поэтому выключаем это сохранение только здесь, в тестах.
enum PencilKitTestGuard {
    static func install() {
        _ = installed
    }

    private static let installed: Bool = {
        guard Bundle.main.bundleIdentifier == nil,
              let replicas = NSClassFromString("PKReplicaManager"),
              let method = class_getInstanceMethod(replicas, NSSelectorFromString("_saveStateImmediately"))
        else { return false }
        let skip: @convention(block) (AnyObject) -> Void = { _ in }
        method_setImplementation(method, imp_implementationWithBlock(skip))
        return true
    }()
}
