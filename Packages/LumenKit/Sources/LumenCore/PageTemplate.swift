import Foundation

/// Шаблон страницы: готовое начало заметки. Свои шаблоны хранятся в базе и ездят между устройствами,
/// встроенные (`PageTemplate.builtIn`) собираются из Markdown.
public struct PageTemplate: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var icon: String?
    /// Блоки шаблона: при применении копируются на страницу с новыми id.
    public var blocks: BlockClipboard
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, icon: String? = nil, blocks: BlockClipboard, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.blocks = blocks
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Встроенный ли шаблон (его нельзя удалить).
    public var isBuiltIn: Bool { Self.builtIn.contains { $0.id == id } }
}

extension PageTemplate {
    /// Шаблоны, которые есть всегда.
    public static let builtIn: [PageTemplate] = [
        make("5E1A0001-0000-4000-8000-000000000001", "Конспект лекции", "🎓", """
            ## Тема
            Предмет, преподаватель, дата
            ## Главные идеи
            - Идея
            ## Определения и формулы
            - Термин: что значит
            ## Вопросы
            - [ ] Что осталось непонятным
            ## Повторить к экзамену
            - [ ] Тема
            """),
        make("5E1A0001-0000-4000-8000-000000000002", "Конспект книги", "📚", """
            ## О книге
            Автор, год, почему читаю
            ## Главные мысли
            - Мысль
            ## Цитаты
            > Цитата
            ## Что применю
            - [ ] Шаг
            """),
        make("5E1A0001-0000-4000-8000-000000000003", "План недели", "🗓️", """
            ## Цели недели
            - [ ] Цель
            ## Понедельник
            - [ ] Дело
            ## Вторник
            - [ ] Дело
            ## Среда
            - [ ] Дело
            ## Четверг
            - [ ] Дело
            ## Пятница
            - [ ] Дело
            ## Выходные
            - [ ] Отдых
            ## Итоги
            Что получилось, что перенести
            """),
        make("5E1A0001-0000-4000-8000-000000000004", "Дневник", "📔", """
            ## Что было сегодня
            Несколько строк о дне
            ## За что благодарен
            - Одно хорошее
            ## Что узнал
            - Мысль
            ## Завтра
            - [ ] Главное дело
            """),
        make("5E1A0001-0000-4000-8000-000000000005", "Встреча", "🤝", """
            ## Участники
            - Имя
            ## Повестка
            1. Вопрос
            ## Решения
            - Решение
            ## Задачи
            - [ ] Кто и что сделает
            """),
    ]

    private static func make(_ id: String, _ title: String, _ icon: String, _ markdown: String) -> PageTemplate {
        // Блоки встроенного шаблона живут на «ничьей» странице: при применении всё равно копируются.
        let blocks = MarkdownPaste.makeBlocks(MarkdownPaste.blocks(from: markdown), pageId: UUID())
        return PageTemplate(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            icon: icon,
            blocks: BlockClipboard(blocks: blocks),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}

extension MarkdownPaste {
    /// Готовые блоки страницы из разобранного Markdown: вложенность из `depth`, порядок в `sortKey`.
    /// Блоки идут в порядке документа (родитель раньше детей).
    public static func makeBlocks(_ parsed: [MarkdownBlock], pageId: UUID, now: Date = Date(timeIntervalSince1970: 0)) -> [Block] {
        var result: [Block] = []
        var chain: [UUID] = []
        var lastKey: [UUID?: String] = [:]
        for item in parsed {
            let depth = min(item.depth, chain.count)
            let parent: UUID? = depth == 0 ? nil : chain[depth - 1]
            let key = SortKey.between(lastKey[parent], nil)
            lastKey[parent] = key
            let block = Block(pageId: pageId, parentBlockId: parent, type: item.type, content: item.content, sortKey: key, createdAt: now)
            result.append(block)
            chain = Array(chain.prefix(depth)) + [block.id]
        }
        return result
    }
}
