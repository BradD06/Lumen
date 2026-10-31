import Foundation
import LumenCore
import LumenStorage
import LumenThemes
import Observation
import SwiftUI

/// Что приложению дали открыть снаружи: файл книги из «Файлов», Telegram или Finder
/// и ссылки `lumen://` на страницы, книги и цитаты.
///
/// Очередь общая на всё приложение: на Mac файлы приходят в делегат приложения ещё до того,
/// как появилось окно, а экран разбирает их, когда готов.
@MainActor
@Observable
public final class IncomingOpenQueue {
    public static let shared = IncomingOpenQueue()

    private(set) var urls: [URL] = []
    /// Когда какую ссылку получили: одна и та же ссылка может прийти дважды, через делегат и SwiftUI.
    @ObservationIgnored private var received: [URL: Date] = [:]

    public init() {}

    public func receive(_ url: URL) {
        let now = Date()
        received = received.filter { now.timeIntervalSince($0.value) < 2 }
        guard received[url] == nil else { return }
        received[url] = now
        urls.append(url)
    }

    public func receive(_ urls: [URL]) {
        urls.forEach(receive)
    }

    func takeAll() -> [URL] {
        defer { urls = [] }
        return urls
    }
}

/// Куда ведёт то, что открыли снаружи.
enum IncomingOpen {
    enum Failure: Error, Equatable {
        case notFound
        case importFailed(String)

        var message: String {
            switch self {
            case .notFound: "Того, на что ведёт ссылка, больше нет: его удалили или оно на другом устройстве."
            case .importFailed(let name): "Не получилось добавить «\(name)» в библиотеку."
            }
        }
    }

    /// Файл добавляется в библиотеку (или находится там, если его уже добавляли), ссылка
    /// превращается в экран. Ссылка на место сначала ставит место чтения, и книга откроется там.
    static func resolve(_ url: URL, database: AppDatabase) async -> Result<SidebarItem, Failure> {
        if url.isFileURL {
            do {
                let source = try await SourceImporter.importIncomingFile(url, into: database)
                return .success(.source(source.id, highlight: nil))
            } catch {
                print("Failed to open \(url.lastPathComponent): \(error)")
                return .failure(.importFailed(url.lastPathComponent))
            }
        }
        guard let link = LumenLink(url: url) else { return .failure(.notFound) }
        do {
            switch link {
            case .page(let id):
                guard let page = try await database.page(id), page.deletedAt == nil else { return .failure(.notFound) }
                return .success(.page(page.id))
            case .source(let id):
                guard try await liveSource(id, database) else { return .failure(.notFound) }
                return .success(.source(id, highlight: nil))
            case .highlight(let sourceId, let highlightId):
                guard try await liveSource(sourceId, database) else { return .failure(.notFound) }
                return .success(.source(sourceId, highlight: highlightId))
            case .place(let sourceId, let locator):
                guard try await liveSource(sourceId, database) else { return .failure(.notFound) }
                try await database.setReadingLocator(sourceId, locator: locator)
                return .success(.source(sourceId, highlight: nil))
            }
        } catch {
            return .failure(.notFound)
        }
    }

    private static func liveSource(_ id: UUID, _ database: AppDatabase) async throws -> Bool {
        guard let source = try await database.source(id) else { return false }
        return !source.isTrashed
    }
}

extension View {
    /// Принимает файлы и ссылки `lumen://`, которые открыли снаружи, и показывает их через `open`.
    func opensIncomingLinks(database: AppDatabase, open: @escaping (SidebarItem) -> Void) -> some View {
        modifier(IncomingOpenModifier(database: database, open: open))
    }
}

private struct IncomingOpenModifier: ViewModifier {
    let database: AppDatabase
    let open: (SidebarItem) -> Void

    @State private var queue = IncomingOpenQueue.shared
    @State private var isProcessing = false
    @State private var isImporting = false
    @State private var failure: IncomingOpen.Failure?
    @Environment(\.lumenTheme) private var theme

    func body(content: Content) -> some View {
        content
            .onOpenURL { queue.receive($0) }
            // Ссылку и файл принимает уже открытое окно, а не новое.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .onChange(of: queue.urls.count, initial: true) { _, count in
                if count > 0 { startProcessing() }
            }
            .overlay(alignment: .top) {
                if isImporting {
                    Label("Добавляю в библиотеку…", systemImage: "books.vertical")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert(
                "Не получилось открыть",
                isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } },
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
    }

    /// Разбор идёт отдельной задачей: пока добавляется большая книга, могут прийти ещё файлы,
    /// они встают в очередь и разбираются следом.
    private func startProcessing() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            while !queue.urls.isEmpty {
                await handle(queue.takeAll())
            }
            isProcessing = false
        }
    }

    private func handle(_ urls: [URL]) async {
        let hasFiles = urls.contains(where: \.isFileURL)
        if hasFiles { withAnimation(.snappy) { isImporting = true } }
        var last: SidebarItem?
        for url in urls {
            switch await IncomingOpen.resolve(url, database: database) {
            case .success(let item): last = item
            case .failure(let error): failure = error
            }
        }
        if hasFiles { withAnimation(.snappy) { isImporting = false } }
        // Открыли сразу несколько файлов: все легли в библиотеку, на экране последний.
        if let last {
            if hasFiles { LumenSounds.play(.create) }
            open(last)
        }
    }
}
