import Foundation
import Observation
import SwiftUI

/// Настройка из UserDefaults для вью, вместо `@AppStorage`: `@Setting(key) private var x = default`, `$x` даёт Binding.
///
/// `@AppStorage` будит вью на любую запись в UserDefaults, даже чужого ключа. А SwiftUI на Mac пишет туда
/// положение окна на каждый его сдвиг: при перетаскивании окна весь экран пересобирался 60 раз в секунду.
/// Здесь вью обновляется, только когда меняется значение своего ключа.
@MainActor
@propertyWrapper
struct Setting<Value: Equatable>: DynamicProperty {
    @State private var box: SettingBox<Value>

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Bindable(box).value
    }

    fileprivate init(key: String, defaultValue: Value, read: @escaping (Any) -> Value?, write: @escaping (Value) -> Any) {
        _box = State(initialValue: SettingBox(key: key, defaultValue: defaultValue, read: read, write: write))
    }
}

/// Bool, Int, Double, String хранятся в UserDefaults как есть.
protocol PlainSettingValue: Equatable {}
extension Bool: PlainSettingValue {}
extension Int: PlainSettingValue {}
extension Double: PlainSettingValue {}
extension String: PlainSettingValue {}

extension Setting where Value: PlainSettingValue {
    init(wrappedValue: Value, _ key: String) {
        self.init(key: key, defaultValue: wrappedValue, read: { $0 as? Value }, write: { $0 })
    }
}

/// Перечисления хранятся строкой `rawValue`, как у `@AppStorage`.
extension Setting where Value: RawRepresentable, Value.RawValue == String {
    init(wrappedValue: Value, _ key: String) {
        self.init(key: key, defaultValue: wrappedValue, read: { ($0 as? String).flatMap(Value.init(rawValue:)) }, write: { $0.rawValue })
    }
}

/// Значение одного ключа. Наблюдатели видят только `stored`, и он меняется, лишь когда значение другое.
@MainActor
@Observable
final class SettingBox<Value: Equatable> {
    @ObservationIgnored let key: String
    @ObservationIgnored private let defaultValue: Value
    @ObservationIgnored private let read: (Any) -> Value?
    @ObservationIgnored private let write: (Value) -> Any
    /// Подписка ставится при первом чтении: init вью идёт на каждой пересборке родителя,
    /// и ящики из лишних init сразу выбрасываются.
    @ObservationIgnored nonisolated(unsafe) private var observer: (any NSObjectProtocol)?
    private var stored: Value

    init(key: String, defaultValue: Value, read: @escaping (Any) -> Value?, write: @escaping (Value) -> Any) {
        self.key = key
        self.defaultValue = defaultValue
        self.read = read
        self.write = write
        stored = UserDefaults.standard.object(forKey: key).flatMap(read) ?? defaultValue
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var value: Value {
        get {
            if observer == nil { startObserving() }
            return stored
        }
        set {
            if stored != newValue { stored = newValue }
            UserDefaults.standard.set(write(newValue), forKey: key)
        }
    }

    /// Перечитать свой ключ (после записи из другого места приложения).
    func reload() {
        let current = UserDefaults.standard.object(forKey: key).flatMap(read) ?? defaultValue
        if current != stored { stored = current }
    }

    private func startObserving() {
        // KVO не подходит: в ключах точки (`screen.tabs`), а KVO понимает их как путь.
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }
}
