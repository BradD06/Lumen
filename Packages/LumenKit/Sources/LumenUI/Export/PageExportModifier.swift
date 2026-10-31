import LumenCore
import LumenStorage
import SwiftUI
import UniformTypeIdentifiers

/// В какой формат выгрузить страницу.
enum PageExportFormat: String, Identifiable, CaseIterable {
    case markdown
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .pdf: "PDF"
        }
    }

    var symbolName: String {
        switch self {
        case .markdown: "doc.plaintext"
        case .pdf: "doc.richtext"
        }
    }
}

/// Готовый файл для окна сохранения. Данные уже собраны, окну остаётся только записать их.
struct ExportFileDocument: FileDocument {
    static let markdownType = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data
    var contentType: UTType

    init(_ file: ExportedFile) {
        data = file.data
        contentType = switch file.kind {
        case .markdown: Self.markdownType
        case .markdownArchive: .zip
        case .pdf: .pdf
        }
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = .data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Кнопки «Экспорт» для меню страницы.
struct PageExportButtons: View {
    @Binding var request: PageExportFormat?

    var body: some View {
        Menu {
            ForEach(PageExportFormat.allCases) { format in
                Button {
                    request = format
                } label: {
                    Label(format.title, systemImage: format.symbolName)
                }
            }
        } label: {
            Label("Экспорт", systemImage: "square.and.arrow.up")
        }
    }
}

/// Собирает файл страницы, когда в `request` появляется формат, и показывает окно сохранения.
struct PageExportModifier: ViewModifier {
    let database: AppDatabase
    let pageId: UUID
    @Binding var request: PageExportFormat?
    /// Дописать несохранённые правки, чтобы в файл попало то, что на экране.
    var beforeExport: @MainActor () async -> Void

    @State private var document: ExportFileDocument?
    @State private var fileName = ""
    @State private var isExporting = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, format in
                guard let format else { return }
                Task { await prepare(format) }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: document,
                contentType: document?.contentType ?? .data,
                defaultFilename: fileName
            ) { result in
                document = nil
                if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            .alert(
                "Не удалось экспортировать",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func prepare(_ format: PageExportFormat) async {
        defer { request = nil }
        await beforeExport()
        do {
            let file: ExportedFile?
            switch format {
            case .markdown:
                file = try await database.exportMarkdown(pageId)
            case .pdf:
                file = try await database.pageExport(pageId).map { export in
                    ExportedFile(
                        kind: .pdf,
                        name: export.fileName,
                        data: PagePDFRenderer.pdf(for: export, attachments: database.attachments)
                    )
                }
            }
            guard let file else { return }
            document = ExportFileDocument(file)
            fileName = file.name
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    /// Экспорт страницы в Markdown или PDF по запросу из меню, см. `PageExportButtons`.
    func pageExport(
        database: AppDatabase,
        pageId: UUID,
        request: Binding<PageExportFormat?>,
        beforeExport: @escaping @MainActor () async -> Void = {}
    ) -> some View {
        modifier(PageExportModifier(database: database, pageId: pageId, request: request, beforeExport: beforeExport))
    }
}
