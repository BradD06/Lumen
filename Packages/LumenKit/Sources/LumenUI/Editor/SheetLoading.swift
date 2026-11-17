import SwiftUI

/// Длинная заметка открывается по частям. Сразу строятся первые листы (их и видно), остальные
/// лежат пустой бумагой нужного размера и достраиваются по одному, пока страницу не листают.
/// Лист, до которого докрутили или на который перешли, строится сразу.
/// Так стопка остаётся обычным `VStack` (листается плавно), а заметка открывается быстро.
@MainActor
@Observable
final class SheetLoader {
    /// Сколько первых листов строится сразу при открытии: больше на экран не помещается.
    nonisolated static let initialSheets = 2

    /// Листы с номером меньше этого построены.
    private(set) var builtCount = SheetLoader.initialSheets
    /// Листы вне очереди: до них докрутили, к ним перешли или в них поставили курсор.
    private(set) var revealed: Set<Int> = []

    /// Построены все листы, и новые тоже строятся сразу.
    var isFinished: Bool { builtCount == .max }

    func isBuilt(_ index: Int) -> Bool {
        index < builtCount || revealed.contains(index)
    }

    /// Построить лист сейчас, не дожидаясь очереди.
    func reveal(_ index: Int) {
        guard index >= 0, !isBuilt(index) else { return }
        revealed.insert(index)
    }

    /// Все листы сразу: ленивой стопке очередь не нужна, она сама строит только видное.
    func finish() {
        builtCount = .max
        revealed = []
    }

    /// Достраивает остальные листы по одному. Пока страницу листают, ждёт: постройка листа
    /// посреди прокрутки и есть рывок. Между листами есть пауза, чтобы кадры успевали рисоваться.
    func buildRest(
        sheetCount: () -> Int,
        isScrolling: () -> Bool,
        step: Duration = .milliseconds(30)
    ) async {
        while !isFinished {
            try? await Task.sleep(for: step)
            if Task.isCancelled { return }
            if isScrolling() { continue }
            var next = builtCount
            while next < sheetCount(), isBuilt(next) { next += 1 }
            guard next < sheetCount() else { break }
            builtCount = next + 1
        }
        finish()
    }
}

/// Место листа в стопке: построенный лист или, пока до него не дошла очередь, пустая бумага.
/// Построенный лист больше не смотрит на очередь, и её шаги не пересобирают его строки.
struct DeferredSheet<Content: View, Placeholder: View>: View {
    let index: Int
    let loader: SheetLoader
    @ViewBuilder var content: () -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var isBuilt = false

    var body: some View {
        if isBuilt || loader.isBuilt(index) {
            content()
                .onAppear { isBuilt = true }
        } else {
            placeholder()
                .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                    if isVisible { loader.reveal(index) }
                }
        }
    }
}
