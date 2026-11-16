import Foundation
import Observation
import Testing
@testable import LumenUI

/// `@Setting` будит вью только на свой ключ: запись чужого (например, положения окна) ничего не трогает.
@MainActor
@Suite(.serialized)
struct SettingTests {
    private final class Flag: @unchecked Sendable {
        var fired = false
    }

    private func makeBox(_ key: String) -> SettingBox<TabStripMode> {
        SettingBox(key: key, defaultValue: .multiple, read: { ($0 as? String).flatMap(TabStripMode.init(rawValue:)) }, write: { $0.rawValue })
    }

    /// Уведомление UserDefaults приходит через главную очередь: ждём его, не больше секунды.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func readsDefaultAndWritesRawValue() {
        let key = "test.setting.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let box = makeBox(key)
        #expect(box.value == .multiple)
        box.value = .never
        #expect(UserDefaults.standard.string(forKey: key) == "never")
        #expect(makeBox(key).value == .never)
    }

    @Test func followsWritesFromElsewhere() async {
        let key = "test.setting.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let box = makeBox(key)
        _ = box.value
        UserDefaults.standard.set("always", forKey: key)
        await waitUntil { box.value == .always }
        #expect(box.value == .always)
    }

    @Test func ignoresOtherKeys() async throws {
        let key = "test.setting.\(UUID().uuidString)"
        let other = "test.setting.other.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: other)
        }
        let box = makeBox(key)
        let flag = Flag()
        withObservationTracking { _ = box.value } onChange: { flag.fired = true }
        for index in 0..<5 {
            UserDefaults.standard.set(index, forKey: other)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!flag.fired)

        UserDefaults.standard.set("never", forKey: key)
        await waitUntil { flag.fired }
        #expect(flag.fired)
    }
}
