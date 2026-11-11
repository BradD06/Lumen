import GRDB
import LumenCore
import LumenReader
import LumenStorage
import LumenThemes
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Откуда взять своё фото обложки.
enum BookCoverPick: Hashable {
    /// Окно «Обложка книги»: фото, полоска на корешке, возврат обложки из книги.
    case editor
    case file
    case photos
    case camera
}

/// Смена обложки книги отовсюду, где видна книга: меню книги на полке и в библиотеке, витрина.
/// Окна выбора показывает `bookCoverHost`, кнопки только просят.
struct BookCoverActions {
    var pick: @MainActor (Source, BookCoverPick) -> Void
    var paste: @MainActor (Source) -> Void
    var restore: @MainActor (Source) -> Void
}

extension EnvironmentValues {
    @Entry var bookCover: BookCoverActions? = nil
}

extension View {
    /// Экран с книгами умеет менять их обложки: окно обложки, выбор файла, Фото, камера.
    func bookCoverHost(database: AppDatabase) -> some View {
        modifier(BookCoverHost(database: database))
    }
}

/// Своё фото обложки: картинка уменьшается в фоне и ложится во вложения книги.
@MainActor
enum BookCoverWork {
    static func apply(_ data: Data, to bookId: UUID, in database: AppDatabase) async {
        let prepared = await Task.detached(priority: .userInitiated) { SourceMetadata.customCover(from: data) }.value
        guard let prepared else {
            NoticeCenter.shared.show("Это не картинка, обложка осталась прежней")
            return
        }
        do {
            try await database.setCustomCover(bookId, imageData: prepared)
        } catch {
            NoticeCenter.shared.report("Не удалось сменить обложку", error)
        }
    }

    static func paste(to bookId: UUID, in database: AppDatabase) {
        guard let image = NotebookPasteboard.image() else {
            NoticeCenter.shared.show("В буфере обмена нет картинки")
            return
        }
        Task { await apply(image.data, to: bookId, in: database) }
    }

    static func restore(_ bookId: UUID, in database: AppDatabase) {
        Task {
            await NoticeCenter.shared.attempt("Не удалось вернуть обложку") {
                try await database.restoreBookCover(bookId)
            }
        }
    }

    /// Файл из окна выбора: на iPhone он доступен только внутри разрешения.
    static func read(_ url: URL) -> Data? {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

private struct BookCoverHost: ViewModifier {
    let database: AppDatabase

    @State private var editing: Source?
    @State private var importing: Source?
    @State private var choosingPhoto: Source?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var shooting: Source?

    func body(content: Content) -> some View {
        content
            .environment(\.bookCover, BookCoverActions(
                pick: { book, pick in
                    switch pick {
                    case .editor: editing = book
                    case .file: importing = book
                    case .photos: choosingPhoto = book
                    case .camera: shooting = book
                    }
                },
                paste: { book in BookCoverWork.paste(to: book.id, in: database) },
                restore: { book in BookCoverWork.restore(book.id, in: database) }
            ))
            .sheet(item: $editing) { book in
                BookCoverEditor(database: database, initial: book) { editing = nil }
            }
            // Окна выбора висят на отдельном пустом виде: два `fileImporter` в одной цепочке
            // (у полки свой, для книг) мешают друг другу.
            .background {
                Color.clear
                    .fileImporter(isPresented: isPresented($importing), allowedContentTypes: [.image]) { result in
                        guard let book = importing else { return }
                        importing = nil
                        guard case .success(let url) = result, let data = BookCoverWork.read(url) else { return }
                        Task { await BookCoverWork.apply(data, to: book.id, in: database) }
                    }
                    .photosPicker(isPresented: isPresented($choosingPhoto), selection: $pickedPhoto, matching: .images)
                    .onChange(of: pickedPhoto) { _, item in
                        guard let item, let book = choosingPhoto else { return }
                        choosingPhoto = nil
                        pickedPhoto = nil
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                await BookCoverWork.apply(data, to: book.id, in: database)
                            }
                        }
                    }
                    #if os(iOS)
                    .fullScreenCover(item: $shooting) { book in
                        CameraPicker { data in
                            shooting = nil
                            guard let data else { return }
                            Task { await BookCoverWork.apply(data, to: book.id, in: database) }
                        }
                        .ignoresSafeArea()
                    }
                    #endif
            }
    }

    /// Окно открыто, пока выбрана книга. Закрыли без выбора: книга забывается.
    private func isPresented(_ book: Binding<Source?>) -> Binding<Bool> {
        Binding(
            get: { book.wrappedValue != nil },
            set: { if !$0 { book.wrappedValue = nil } }
        )
    }
}

/// Пункты обложки в меню книги. На iPhone и iPad сразу откуда взять фото (долгое нажатие на книгу),
/// на Mac одно окно обложки.
struct BookCoverMenu: View {
    let book: Source

    @Environment(\.bookCover) private var bookCover

    var body: some View {
        if let bookCover {
            #if os(iOS)
            Menu("Сменить обложку", systemImage: "photo") {
                BookCoverSourceButtons(book: book, actions: bookCover)
            }
            #else
            Button("Сменить обложку…", systemImage: "photo") { bookCover.pick(book, .editor) }
            if book.customCover != nil {
                Button("Вернуть обложку из книги", systemImage: "arrow.uturn.backward") { bookCover.restore(book) }
            }
            #endif
        }
    }
}

/// Кнопка «Сменить обложку» в окне книги на полке.
struct BookCoverButton: View {
    let book: Source

    @Environment(\.bookCover) private var bookCover
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        if let bookCover {
            #if os(iOS)
            Menu {
                BookCoverSourceButtons(book: book, actions: bookCover)
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            #else
            Button {
                bookCover.pick(book, .editor)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .keyHint("Сменить обложку") { bookCover.pick(book, .editor) }
            #endif
        }
    }

    private var label: some View {
        Label("Сменить обложку", systemImage: "photo")
            .font(.callout.weight(.medium))
            .foregroundStyle(theme.accent)
            .contentShape(Rectangle())
            .accessibilityIdentifier("changeBookCover")
    }
}

#if os(iOS)
/// Откуда взять обложку на iPhone и iPad: камера, Фото, Файлы, буфер обмена.
private struct BookCoverSourceButtons: View {
    let book: Source
    let actions: BookCoverActions

    var body: some View {
        if CameraPicker.isAvailable {
            Button("Снять на камеру", systemImage: "camera") { actions.pick(book, .camera) }
        }
        Button("Выбрать из Фото", systemImage: "photo.on.rectangle") { actions.pick(book, .photos) }
        Button("Из файлов", systemImage: "doc") { actions.pick(book, .file) }
        Button("Вставить из буфера", systemImage: "doc.on.clipboard") { actions.paste(book) }
        Button("Корешок и обложка…", systemImage: "book.closed") { actions.pick(book, .editor) }
        if book.customCover != nil {
            Divider()
            Button("Вернуть обложку из книги", systemImage: "arrow.uturn.backward") { actions.restore(book) }
        }
    }
}

/// Снимок обложки камерой. В SwiftUI своей камеры нет, поэтому системное окно UIKit.
@MainActor
struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.92))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
#endif

/// Окно «Обложка книги»: обложка из книги или своё фото (файл, буфер, перетащить на обложку,
/// на iPhone и iPad ещё камера и Фото) и рамка, какая полоска обложки станет корешком.
struct BookCoverEditor: View {
    let database: AppDatabase
    let initial: Source
    var onDone: () -> Void

    @State private var live: Source?
    @State private var isImporting = false
    @State private var isDropTargeted = false
    /// Середина полоски корешка, пока рамку тащат: корешок меняется сразу, в базу пишется в конце.
    @State private var dragCenter: Double?
    @State private var isChoosingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isShooting = false
    @Environment(\.lumenTheme) private var theme

    private var book: Source { live ?? initial }

    /// Книга, как она будет выглядеть: с полоской, которую сейчас держат.
    private var preview: Source {
        var source = book
        if let dragCenter { source.spineCenter = dragCenter }
        return source
    }

    private var hasCustom: Bool { book.customCover != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) {
                        artwork
                        options.frame(width: 340)
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        artwork.frame(maxWidth: .infinity)
                        options
                    }
                }
                .padding(24)
            }
            .keyHintClip()
            .background(ThemedBackground())
            .navigationTitle("Обложка книги")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", action: onDone)
                        .keyHint("Готово", perform: onDone)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 470)
        #endif
        .environment(\.colorScheme, theme.colorScheme)
        .keyHintHost()
        .task { await observe() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result, let data = BookCoverWork.read(url) else { return }
            apply(data)
        }
        .photosPicker(isPresented: $isChoosingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    apply(data)
                }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShooting) {
            CameraPicker { data in
                isShooting = false
                if let data { apply(data) }
            }
            .ignoresSafeArea()
        }
        #endif
        .accessibilityIdentifier("bookCoverEditor")
    }

    // MARK: Обложка и корешок

    private var artwork: some View {
        HStack(alignment: .bottom, spacing: 16) {
            SourceCoverArt(source: preview, attachments: database.attachments, width: 190, height: 280)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.accent.opacity(isDropTargeted ? 1 : 0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .padding(-7)
                }
                .overlay {
                    if isDropTargeted {
                        Label("Отпустите, чтобы поставить обложку", systemImage: "photo.badge.plus")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(10)
                    }
                }
                .dropDestination(for: DroppedImage.self) { images, _ in
                    guard let image = images.first else { return false }
                    apply(image.data)
                    return true
                } isTargeted: { isDropTargeted = $0 }
                .help("Перетащите сюда картинку, и она станет обложкой")
                .accessibilityLabel("Обложка «\(book.displayTitle)»")
            VStack(spacing: 6) {
                BookSpine(source: preview, attachments: database.attachments)
                Text("корешок")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Корешок на полке")
        }
        .padding(8)
    }

    // MARK: Выбор

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            option(
                title: "Из книги",
                detail: book.cover == nil ? "Нарисованная обложка с названием" : "Обложка из файла книги",
                isOn: !hasCustom
            ) {
                if hasCustom { BookCoverWork.restore(book.id, in: database) }
            }
            option(title: "Своё фото", detail: customDetail, isOn: hasCustom) {
                if !hasCustom { chooseDefault() }
            }
            sourceButtons
                .padding(.leading, 4)
            if let cover = preview.shownCover {
                Text("Что видно на корешке")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                    .textCase(.uppercase)
                    .padding(.top, 8)
                SpineStripPicker(
                    cover: cover,
                    attachments: database.attachments,
                    style: BookSpineStyle(source: book),
                    center: dragCenter ?? book.spineCenter ?? 0.5,
                    onChange: { dragCenter = $0 },
                    onCommit: commitSpine
                )
                HStack {
                    Text("Подвиньте рамку: эта полоска обложки станет корешком.")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if book.spineCenter != nil {
                        Button("По середине") { commitSpine(nil) }
                            .buttonStyle(.plain)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(theme.accent)
                            .keyHint("Корешок из середины") { commitSpine(nil) }
                    }
                }
            }
            Button {
                BookCoverWork.restore(book.id, in: database)
            } label: {
                Label("Вернуть обложку из книги", systemImage: "arrow.uturn.backward")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(hasCustom ? theme.accent : theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!hasCustom)
            .padding(.top, 6)
            .keyHint("Вернуть обложку из книги") { BookCoverWork.restore(book.id, in: database) }
        }
    }

    private var customDetail: String {
        #if os(iOS)
        "Снимок с камеры, из Фото, из Файлов или из буфера обмена"
        #else
        "Картинка с компьютера, из буфера или перетащите её на обложку"
        #endif
    }

    @ViewBuilder
    private var sourceButtons: some View {
        HStack(spacing: 8) {
            #if os(iOS)
            if CameraPicker.isAvailable {
                sourceButton("Камера", systemImage: "camera") { isShooting = true }
            }
            sourceButton("Фото", systemImage: "photo.on.rectangle") { isChoosingPhoto = true }
            sourceButton("Файлы", systemImage: "doc") { isImporting = true }
            sourceButton("Вставить", systemImage: "doc.on.clipboard") { BookCoverWork.paste(to: book.id, in: database) }
            #else
            sourceButton("Выбрать файл…", systemImage: "folder") { isImporting = true }
            sourceButton("Вставить ⌘V", systemImage: "doc.on.clipboard") { BookCoverWork.paste(to: book.id, in: database) }
                .keyboardShortcut("v", modifiers: .command)
            #endif
        }
    }

    private func sourceButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(theme.contrast.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.contrast.opacity(0.14)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .keyHint(title, perform: action)
    }

    private func option(title: String, detail: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(theme.accent.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .overlay {
                        if isOn {
                            Circle().fill(theme.accent).frame(width: 8, height: 8)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.accent.opacity(isOn ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.accent.opacity(isOn ? 0.6 : 0.2)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyHint(title, perform: action)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Действия

    /// «Своё фото», пока фото нет: самый частый способ его взять.
    private func chooseDefault() {
        #if os(iOS)
        isChoosingPhoto = true
        #else
        isImporting = true
        #endif
    }

    private func apply(_ data: Data) {
        let id = book.id
        Task { await BookCoverWork.apply(data, to: id, in: database) }
    }

    private func commitSpine(_ center: Double?) {
        let id = book.id
        // Корешок остаётся там, куда его поставили, пока база не вернула новое значение.
        live?.spineCenter = center
        dragCenter = nil
        Task {
            await NoticeCenter.shared.attempt("Не удалось сохранить корешок") {
                try await database.setSpineCenter(id, center)
            }
        }
    }

    private func observe() async {
        let id = initial.id
        let observation = ValueObservation.tracking { db in try Source.fetchOne(db, key: id) }
        do {
            for try await value in observation.values(in: database.reader) {
                live = value
            }
        } catch {
            lumenLog.error("Book cover observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Полоса обложки во всю ширину и рамка шириной с корешок: где рамка, та полоска и будет на корешке.
struct SpineStripPicker: View {
    let cover: String
    let attachments: AttachmentStore
    let style: BookSpineStyle
    /// Середина рамки, 0…1 по ширине обложки.
    let center: Double
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void

    @Environment(\.lumenTheme) private var theme

    private static let height: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let frameWidth = max(14, width * style.width / max(style.coverWidth, 1))
            let x = min(max(CGFloat(center) * width, frameWidth / 2), width - frameWidth / 2)
            ZStack(alignment: .leading) {
                AttachmentImage(name: cover, attachments: attachments, contentMode: .fill)
                    .frame(width: width, height: Self.height)
                    .clipped()
                // Всё, кроме рамки, притемнено.
                HStack(spacing: 0) {
                    Color.black.opacity(0.4).frame(width: max(0, x - frameWidth / 2))
                    Color.clear.frame(width: frameWidth)
                    Color.black.opacity(0.4)
                }
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.accent, lineWidth: 2)
                    .frame(width: frameWidth, height: Self.height - 6)
                    .offset(x: x - frameWidth / 2)
            }
            .frame(width: width, height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onChange(Self.fraction(value.location.x, width: width)) }
                    .onEnded { value in onCommit(Self.fraction(value.location.x, width: width)) }
            )
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("Полоска обложки на корешке")
        .accessibilityValue("\(Int((center * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommit(min(1, center + 0.05))
            case .decrement: onCommit(max(0, center - 0.05))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("spineStrip")
    }

    nonisolated static func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0.5 }
        return Double(min(max(x / width, 0), 1))
    }
}
