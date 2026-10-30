import GRDB
import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Главный экран: дашборд из карточек-виджетов и два главных входа (быстрая заметка и заметки по источнику).
struct HomeView: View {
    let database: AppDatabase
    var onOpen: (UUID) -> Void
    var onNewNote: () -> Void
    var onShowInbox: () -> Void

    @State private var snapshot = HomeSnapshot.empty
    @Environment(\.lumenTheme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actions
                stats
                if !snapshot.recent.isEmpty {
                    recent
                }
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ThemedBackground())
        .navigationTitle("Главная")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await observe() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textSecondary)
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        case 18..<23: "Добрый вечер"
        default: "Доброй ночи"
        }
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
            Button(action: onNewNote) {
                ActionCard(
                    title: "Быстрая заметка",
                    subtitle: "Записать мысль во «Входящие»",
                    systemImage: "square.and.pencil",
                    style: .vivid(0)
                )
            }
            .buttonStyle(.plain)

            ActionCard(
                title: "Заметки по книге",
                subtitle: "Книга или файл рядом с заметкой. Скоро",
                systemImage: "book.pages",
                style: .glass
            )
            .opacity(0.7)
        }
    }

    private var stats: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            Button(action: onShowInbox) {
                StatCard(
                    title: "Входящие",
                    value: "\(snapshot.inboxCount)",
                    caption: snapshot.inboxCount == 0 ? "всё разобрано" : "ждут разбора",
                    systemImage: "tray",
                    style: .vivid(1)
                )
            }
            .buttonStyle(.plain)
            StatCard(
                title: "Страницы",
                value: "\(snapshot.pageCount)",
                caption: "всего заметок",
                systemImage: "doc.text",
                style: .vivid(2)
            )
            StatCard(
                title: "Сегодня",
                value: "\(snapshot.editedToday)",
                caption: "страниц изменено",
                systemImage: "flame",
                style: .vivid(3)
            )
            StatCard(
                title: "Читаю сейчас",
                value: "—",
                caption: "Читалка появится вместе с библиотекой",
                systemImage: "books.vertical"
            )
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Недавние")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(snapshot.recent) { preview in
                    Button {
                        onOpen(preview.page.id)
                    } label: {
                        PagePreviewCard(preview: preview)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func observe() async {
        let observation = ValueObservation.tracking { db in try HomeSnapshot.fetch(db) }
        do {
            for try await value in observation.values(in: database.reader) {
                withAnimation { snapshot = value }
            }
        } catch {
            print("Home observation failed: \(error)")
        }
    }
}

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let style: CardStyle

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .lumenCard(style)
    }
}

/// Карточка страницы с началом текста.
struct PagePreviewCard: View {
    let preview: PagePreview
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageLabel(page: preview.page)
                .font(.headline)
            Text(preview.excerpt.isEmpty ? "Пустая заметка" : preview.excerpt)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            Text(preview.page.updatedAt.lumenRelative)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .lumenCard()
    }
}
