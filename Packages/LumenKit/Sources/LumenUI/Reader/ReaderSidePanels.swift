import LumenCore
import LumenReader
import LumenStorage
import LumenThemes
import SwiftUI

/// Содержание книги: вложенные пункты, текущий в персиковой «таблетке», нажатие переходит к месту.
struct TableOfContents: View {
    let model: ReaderModel
    /// В шторке на iPhone содержание закрывается сразу после перехода.
    var closesOnSelect = false
    /// Рядом с книгой содержание лежит стеклянной карточкой, в шторке фон даёт сама шторка.
    var isCard = true
    var onClose: () -> Void
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let current = model.currentTocEntry
        let currentIndex = current.flatMap { model.toc.firstIndex(of: $0) }
        let baseLevel = model.toc.map(\.level).min() ?? 0
        let content = VStack(spacing: 0) {
            HStack {
                Label("Содержание", systemImage: "list.bullet.indent")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Скрыть содержание")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.toc.enumerated()), id: \.element.id) { index, entry in
                            let isCurrent = index == currentIndex
                            let isRead = currentIndex.map { index < $0 } ?? false
                            let level = max(entry.level - baseLevel, 0)
                            Button {
                                model.open(entry)
                                if closesOnSelect { onClose() }
                            } label: {
                                row(entry, level: level, isCurrent: isCurrent, isRead: isRead)
                            }
                            .buttonStyle(.plain)
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
                }
                .onAppear {
                    if let current { proxy.scrollTo(current.id, anchor: .center) }
                }
                .onChange(of: current?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        if isCard {
            content.readerGlassCard(theme)
        } else {
            content
        }
    }

    private func row(_ entry: TocEntry, level: Int, isCurrent: Bool, isRead: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isCurrent ? ReaderStyle.peach : isRead ? ReaderStyle.peach.opacity(0.55) : Color.white.opacity(0.18))
                .frame(width: level == 0 ? 8 : 6, height: level == 0 ? 8 : 6)
                .background {
                    if isCurrent {
                        Circle().fill(ReaderStyle.peach.opacity(0.22)).frame(width: 16, height: 16)
                    }
                }
            Text(entry.title)
                .font(.system(size: level == 0 ? 14 : 13.5, weight: level == 0 || isCurrent ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isCurrent ? theme.textPrimary : theme.textPrimary.opacity(level == 0 ? 0.85 : 0.68))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12 + CGFloat(min(level, 4)) * 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [ReaderStyle.peach.opacity(0.26), ReaderStyle.lilac.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Все выделения книги: нажатие прокручивает к месту.
struct HighlightsList: View {
    let model: ReaderModel
    var onClose: () -> Void
    /// Выделение, к которому пишут комментарий.
    @State private var editingNote: Highlight?
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Group {
            if model.highlights.isEmpty {
                ContentUnavailableView {
                    Label("Выделений пока нет", systemImage: "highlighter")
                } description: {
                    Text("Выделите текст в книге: его можно покрасить или сразу отправить в заметки.")
                }
            } else {
                List {
                    ForEach(model.highlights) { highlight in
                        Button {
                            onClose()
                            LumenSounds.play(.navigate)
                            model.reveal(highlight)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Capsule()
                                    .fill(Color(hex: highlight.color.hex))
                                    .frame(width: 4)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(highlight.text)
                                        .font(.system(.callout, design: .serif))
                                        .lineLimit(4)
                                        .foregroundStyle(theme.textPrimary)
                                    if let note = highlight.note {
                                        HighlightNoteLabel(note: note)
                                    }
                                    Text(highlight.label)
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                model.addExcerpt(highlight)
                            } label: {
                                Label("В заметки", systemImage: "quote.opening")
                            }
                            Button {
                                editingNote = highlight
                            } label: {
                                Label(highlight.note == nil ? "Комментарий…" : "Изменить комментарий…", systemImage: "text.bubble")
                            }
                            Button {
                                copyToPasteboard(highlight.text)
                            } label: {
                                Label("Скопировать", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) {
                                model.deleteHighlight(highlight.id)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(ThemedBackground())
        .sheet(item: $editingNote) { highlight in
            HighlightNoteSheet(highlight: highlight) { note in
                model.setNote(note, of: highlight.id)
            }
        }
    }
}
