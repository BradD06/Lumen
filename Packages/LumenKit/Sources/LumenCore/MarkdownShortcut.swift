/// Markdown-сокращения в начале пустого абзаца: `# ` превращает блок в заголовок, `- ` в список и так далее.
public enum MarkdownShortcut {
    private struct Rule {
        let trigger: String
        let type: BlockType
        /// Срабатывает только когда весь текст блока равен триггеру.
        let exact: Bool
    }

    private static let rules: [Rule] = [
        Rule(trigger: "### ", type: .heading3, exact: false),
        Rule(trigger: "## ", type: .heading2, exact: false),
        Rule(trigger: "# ", type: .heading1, exact: false),
        Rule(trigger: "- ", type: .bulletedList, exact: false),
        Rule(trigger: "* ", type: .bulletedList, exact: false),
        Rule(trigger: "1. ", type: .numberedList, exact: false),
        Rule(trigger: "[] ", type: .todo, exact: false),
        Rule(trigger: "[ ] ", type: .todo, exact: false),
        Rule(trigger: "> ", type: .quote, exact: false),
        Rule(trigger: "```", type: .code, exact: true),
        Rule(trigger: "---", type: .divider, exact: true),
    ]

    /// Возвращает новый тип блока и текст без триггера, если текст начинается с сокращения.
    public static func match(_ text: String) -> (type: BlockType, remainder: String)? {
        for rule in rules {
            if rule.exact {
                if text == rule.trigger { return (rule.type, "") }
            } else if text.hasPrefix(rule.trigger) {
                return (rule.type, String(text.dropFirst(rule.trigger.count)))
            }
        }
        return nil
    }
}
