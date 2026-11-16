import Foundation

/// Размер или рамка, которую читают только обработчики (бросок, перетаскивание, ⌘J), а не `body`.
/// Держится в `@State` как объект: запись в неё не пересобирает экран, поэтому кадры
/// изменения размера окна и прокрутки не трогают всё, что под этим видом.
@MainActor
final class GeometryBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
