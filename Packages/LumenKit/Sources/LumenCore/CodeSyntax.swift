import Foundation

/// Язык блока кода. Определяется по самому тексту, как это делают редакторы без расширения файла.
public enum CodeLanguage: String, CaseIterable, Sendable {
    case swift, python, javascript, typescript, json, html, css, sql, shell
    case c, cpp, java, kotlin, go, rust, ruby
    case plain

    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .json: "JSON"
        case .html: "HTML"
        case .css: "CSS"
        case .sql: "SQL"
        case .shell: "Shell"
        case .c: "C"
        case .cpp: "C++"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .go: "Go"
        case .rust: "Rust"
        case .ruby: "Ruby"
        case .plain: "Текст"
        }
    }

    /// Признаки языка с весами. Побеждает язык с наибольшей суммой, при равенстве тот, что выше в списке.
    private static let signs: [(CodeLanguage, [(pattern: String, weight: Int)])] = [
        (.swift, [
            (#"^\s*import (SwiftUI|Foundation|UIKit|AppKit|Combine)\b"#, 5),
            (#"\bfunc \w+\s*(<[^>]*>)?\("#, 3),
            (#"^\s*(let|var) \w+(\s*:\s*[\w\[\]?]+)?\s*=[^=>]"#, 2),
            (#"\bguard\b.*\belse\b"#, 4),
            (#"\b(struct|enum|protocol|extension) \w+"#, 2),
            (#"@(State|Binding|Published|MainActor|Observable|Environment)\b"#, 5),
            (#"\\\("#, 3),
            (#"\bif let\b|\?\?"#, 3),
            (#"->\s*[A-Z]\w*"#, 2),
        ]),
        (.python, [
            (#"^\s*def \w+\(.*\)\s*(->\s*[\w\[\], ]+)?:\s*$"#, 5),
            (#"^\s*(from \w[\w.]* )?import \w[\w.]*( as \w+)?\s*$"#, 2),
            (#"^\s*(elif|except|finally)\b"#, 4),
            (#"\bprint\("#, 1),
            (#"\b(None|True|False|self)\b"#, 2),
            (#"^\s*(if|for|while|class|with)\b.*:\s*$"#, 3),
        ]),
        (.typescript, [
            (#":\s*(string|number|boolean|any|void|unknown)\b"#, 4),
            (#"^\s*(export )?(interface|type) \w+"#, 4),
            (#"\b(const|let) \w+\s*:\s*\w+"#, 2),
        ]),
        (.javascript, [
            (#"\b(const|let|var) \w+\s*=.*;\s*$"#, 3),
            (#"\bfunction\s*\w*\s*\("#, 4),
            (#"=>"#, 2),
            (#"\bconsole\.\w+\("#, 5),
            (#"===|!=="#, 3),
            (#"\b(document|window|require|module\.exports)\b"#, 3),
        ]),
        (.html, [
            (#"<!DOCTYPE|<html|<div|<span|<p>|<body|<head|<a href"#, 6),
            (#"</\w+>"#, 3),
        ]),
        (.css, [
            (#"^\s*[.#]?[\w-]+(?:(?:\s*[,>+~]\s*|\s+)[.#]?[\w-]+)*\s*\{\s*$"#, 2),
            (#"^\s*[\w-]+\s*:\s*[^;]+;\s*$"#, 2),
            (#"\b(color|margin|padding|display|font-size|background)\s*:"#, 3),
        ]),
        (.sql, [
            (#"(?i)\bselect\b.+\bfrom\b"#, 6),
            (#"(?i)^\s*(insert into|update \w+ set|delete from|create table|alter table|drop table)\b"#, 6),
            (#"(?i)\b(where|join|group by|order by)\b"#, 1),
        ]),
        (.shell, [
            (#"^#!/(usr/)?bin/(env )?(ba|z)?sh"#, 8),
            (#"^\s*(\$ )?(sudo|cd|ls|echo|export|brew|npm|yarn|git|pip|curl|mkdir|rm|chmod|swift build|xcodebuild)\b"#, 3),
            (#"\|\s*(grep|sed|awk|xargs|head|tail)\b"#, 3),
            (#"\$\{?\w+\}?"#, 1),
        ]),
        (.cpp, [
            (#"\bstd::|\bcout\b|\bcin\b|\bnamespace\b|\btemplate\s*<"#, 5),
            (#"#include\s*<(iostream|vector|string|map)>"#, 6),
        ]),
        (.c, [
            (#"#include\s*[<"]"#, 4),
            (#"\bint main\s*\("#, 3),
            (#"\b(printf|malloc|sizeof)\b"#, 3),
        ]),
        (.java, [
            (#"\bpublic (static )?(final )?(class|void|interface)\b"#, 5),
            (#"\bSystem\.out\.print"#, 6),
            (#"\b(private|protected) \w+(<[^>]*>)? \w+"#, 2),
        ]),
        (.kotlin, [
            (#"\bfun \w+\("#, 5),
            (#"\bval \w+"#, 3),
            (#"\bprintln\("#, 2),
        ]),
        (.go, [
            (#"^\s*package \w+\s*$"#, 5),
            (#"\bfunc (\(\w+ \*?\w+\) )?\w+\("#, 3),
            (#":="#, 3),
            (#"\bfmt\.\w+\("#, 5),
        ]),
        (.rust, [
            (#"\bfn \w+\s*(<[^>]*>)?\("#, 5),
            (#"\blet mut\b"#, 5),
            (#"\b\w+!\("#, 3),
            (#"\b(impl|pub|use) \w+"#, 2),
        ]),
        (.ruby, [
            (#"^\s*def \w+[?!]?(\(.*\))?\s*$"#, 4),
            (#"^\s*end\s*$"#, 3),
            (#"\bputs\b|\brequire ['"]"#, 4),
            (#"\bdo \|\w+(, *\w+)*\|"#, 5),
        ]),
    ]

    private static let compiledSigns: [(CodeLanguage, [(NSRegularExpression, Int)])] = signs.map { language, list in
        (language, list.compactMap { sign in
            (try? NSRegularExpression(pattern: sign.pattern, options: [.anchorsMatchLines])).map { ($0, sign.weight) }
        })
    }

    /// Угадывает язык по тексту. Если ни один признак не подошёл, возвращает `.plain`.
    public static func detect(_ code: String) -> CodeLanguage {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plain }
        if trimmed.first == "{" || trimmed.first == "[",
           (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil {
            return .json
        }

        let range = NSRange(code.startIndex..., in: code)
        var best: (language: CodeLanguage, score: Int) = (.plain, 0)
        for (language, list) in compiledSigns {
            let score = list.reduce(0) { sum, sign in
                sum + sign.0.numberOfMatches(in: code, range: range) * sign.1
            }
            if score > best.score { best = (language, score) }
        }
        return best.language
    }
}

/// Кусок кода и его роль для подсветки. Куски подряд в точности составляют исходный текст.
public struct CodeToken: Equatable, Sendable {
    public enum Kind: Sendable {
        case plain, keyword, type, function, string, number, comment, tag, attribute
    }

    public var text: String
    public var kind: Kind

    public init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// Разбор кода на куски для подсветки. Не полноценный парсер: хватает, чтобы цвета были как в редакторе.
public enum CodeHighlighter {
    public static func tokens(in code: String, language: CodeLanguage) -> [CodeToken] {
        let rules = Rules(language)
        let chars = Array(code)
        var tokens: [CodeToken] = []
        var i = 0

        func add(_ end: Int, _ kind: CodeToken.Kind) {
            let text = String(chars[i..<end])
            if let last = tokens.last, last.kind == kind {
                tokens[tokens.count - 1].text += text
            } else {
                tokens.append(CodeToken(text, kind))
            }
            i = end
        }
        func starts(_ prefix: String, at index: Int) -> Bool {
            let p = Array(prefix)
            return index + p.count <= chars.count && Array(chars[index..<index + p.count]) == p
        }
        func find(_ suffix: String, from index: Int) -> Int {
            var j = index
            while j < chars.count {
                if starts(suffix, at: j) { return j + suffix.count }
                j += 1
            }
            return chars.count
        }
        func nextNonSpace(after index: Int) -> Character? {
            var j = index
            while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
            return j < chars.count ? chars[j] : nil
        }

        guard language != .plain else { return code.isEmpty ? [] : [CodeToken(code, .plain)] }

        var insideTag = false
        while i < chars.count {
            let c = chars[i]

            if language == .html {
                if starts("<!--", at: i) {
                    add(find("-->", from: i + 4), .comment)
                    continue
                }
                if c == "<" {
                    var j = i + 1
                    if j < chars.count, chars[j] == "/" || chars[j] == "!" { j += 1 }
                    add(j, .plain)
                    while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "-" { j += 1 }
                    add(j, .tag)
                    insideTag = true
                    continue
                }
                if c == ">" {
                    insideTag = false
                    add(i + 1, .plain)
                    continue
                }
                if !insideTag {
                    var j = i + 1
                    while j < chars.count, chars[j] != "<" { j += 1 }
                    add(j, .plain)
                    continue
                }
            }

            if let comment = rules.lineComments.first(where: { starts($0, at: i) }) {
                // `#` в Shell и Python начинает комментарий только в начале слова, а не внутри `$#`.
                if comment != "#" || i == 0 || chars[i - 1].isWhitespace {
                    var j = i + comment.count
                    while j < chars.count, chars[j] != "\n" { j += 1 }
                    add(j, .comment)
                    continue
                }
            }
            if let block = rules.blockComment, starts(block.open, at: i) {
                add(find(block.close, from: i + block.open.count), .comment)
                continue
            }

            if rules.quotes.contains(c) {
                let triple = String(repeating: c, count: 3)
                if language == .python || language == .swift || language == .kotlin, starts(triple, at: i) {
                    add(find(triple, from: i + 3), .string)
                    continue
                }
                var j = i + 1
                while j < chars.count, chars[j] != c {
                    if chars[j] == "\\" { j += 1 }
                    // Обычная строка не переносится: незакрытая кавычка красит только до конца строки.
                    if j < chars.count, chars[j] == "\n", c != "`" { break }
                    j += 1
                }
                let end = min(j + 1, chars.count)
                let isKey = language == .json && nextNonSpace(after: end) == ":"
                add(end, isKey ? .attribute : .string)
                continue
            }

            if c.isNumber {
                var j = i + 1
                while j < chars.count, chars[j].isHexDigit || "xXobB._".contains(chars[j]) || (language == .css && chars[j].isLetter) || (language == .css && chars[j] == "%") {
                    j += 1
                }
                add(j, .number)
                continue
            }

            if c.isLetter || c == "_" || rules.identifierPrefixes.contains(c) {
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || (rules.dashInNames && chars[j] == "-") {
                    j += 1
                }
                let word = String(chars[i..<j])
                let next = nextNonSpace(after: j)
                let kind: CodeToken.Kind
                if word.count == 1, rules.identifierPrefixes.contains(c) {
                    kind = .plain
                } else if rules.isKeyword(word) {
                    kind = .keyword
                } else if c == "@" || (c == "#" && language != .css) {
                    kind = .keyword
                } else if c == "$" {
                    kind = .attribute
                } else if c == ":" {
                    kind = .string
                } else if language == .html || language == .css {
                    kind = next == ":" || next == "=" ? .attribute : (language == .css ? .tag : .attribute)
                } else if next == "(" || (language == .rust && next == "!") {
                    kind = word.first?.isUppercase == true && rules.capitalizedTypes ? .type : .function
                } else if word.first?.isUppercase == true && rules.capitalizedTypes {
                    kind = .type
                } else {
                    kind = .plain
                }
                add(j, kind)
                continue
            }

            add(i + 1, .plain)
        }
        return tokens
    }

    private struct Rules {
        var keywords: Set<String> = []
        var caseInsensitive = false
        var lineComments: [String] = ["//"]
        var blockComment: (open: String, close: String)? = ("/*", "*/")
        var quotes: Set<Character> = ["\"", "'"]
        var identifierPrefixes: Set<Character> = []
        var capitalizedTypes = true
        var dashInNames = false

        func isKeyword(_ word: String) -> Bool {
            keywords.contains(caseInsensitive ? word.lowercased() : word)
        }

        init(_ language: CodeLanguage) {
            switch language {
            case .swift:
                keywords = ["let", "var", "func", "if", "else", "guard", "return", "for", "in", "while", "repeat", "switch", "case", "default", "break", "continue", "struct", "class", "enum", "protocol", "extension", "import", "init", "deinit", "self", "Self", "super", "true", "false", "nil", "try", "catch", "throw", "throws", "rethrows", "async", "await", "public", "private", "fileprivate", "internal", "open", "static", "final", "override", "mutating", "lazy", "weak", "unowned", "some", "any", "inout", "where", "as", "is", "typealias", "associatedtype", "defer", "do", "subscript", "operator", "nonisolated", "actor", "get", "set", "willSet", "didSet"]
                quotes = ["\""]
                identifierPrefixes = ["@", "#"]
            case .python:
                keywords = ["def", "class", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is", "return", "yield", "import", "from", "as", "with", "try", "except", "finally", "raise", "pass", "break", "continue", "lambda", "global", "nonlocal", "assert", "del", "async", "await", "None", "True", "False", "self"]
                lineComments = ["#"]
                blockComment = nil
                identifierPrefixes = ["@"]
            case .javascript, .typescript:
                keywords = ["const", "let", "var", "function", "return", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "new", "this", "class", "extends", "super", "import", "export", "from", "as", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "in", "of", "true", "false", "null", "undefined", "void", "delete", "yield", "static", "get", "set"]
                if language == .typescript {
                    keywords.formUnion(["interface", "type", "enum", "implements", "public", "private", "protected", "readonly", "string", "number", "boolean", "any", "unknown", "never", "keyof", "namespace", "declare", "abstract"])
                }
                quotes = ["\"", "'", "`"]
            case .json:
                keywords = ["true", "false", "null"]
                lineComments = []
                blockComment = nil
                quotes = ["\""]
                capitalizedTypes = false
            case .html:
                lineComments = []
                blockComment = nil
                capitalizedTypes = false
                dashInNames = true
            case .css:
                keywords = ["important", "inherit", "initial", "auto", "none"]
                lineComments = []
                identifierPrefixes = [".", "#", "@"]
                capitalizedTypes = false
                dashInNames = true
            case .sql:
                keywords = ["select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create", "table", "drop", "alter", "add", "index", "primary", "key", "foreign", "references", "join", "left", "right", "inner", "outer", "on", "as", "group", "by", "order", "asc", "desc", "limit", "offset", "having", "distinct", "null", "is", "in", "like", "between", "union", "all", "case", "when", "then", "else", "end", "default", "unique", "count", "sum", "avg", "min", "max", "integer", "text", "varchar", "boolean", "exists"]
                caseInsensitive = true
                lineComments = ["--"]
                capitalizedTypes = false
            case .shell:
                keywords = ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "function", "return", "export", "local", "echo", "cd", "sudo", "source", "exit"]
                lineComments = ["#"]
                blockComment = nil
                identifierPrefixes = ["$"]
                capitalizedTypes = false
                dashInNames = true
            case .c, .cpp:
                keywords = ["int", "char", "float", "double", "long", "short", "unsigned", "signed", "void", "bool", "const", "static", "struct", "union", "enum", "typedef", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "sizeof", "goto", "extern", "true", "false", "NULL"]
                if language == .cpp {
                    keywords.formUnion(["class", "public", "private", "protected", "virtual", "override", "template", "typename", "namespace", "using", "new", "delete", "this", "auto", "nullptr", "constexpr", "std", "try", "catch", "throw"])
                }
                identifierPrefixes = ["#"]
            case .java, .kotlin:
                keywords = ["class", "interface", "enum", "public", "private", "protected", "static", "final", "abstract", "void", "int", "long", "double", "float", "boolean", "char", "byte", "short", "new", "return", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "this", "super", "extends", "implements", "import", "package", "try", "catch", "finally", "throw", "throws", "true", "false", "null", "instanceof"]
                if language == .kotlin {
                    keywords.formUnion(["fun", "val", "var", "when", "is", "in", "object", "companion", "data", "sealed", "open", "override", "internal", "suspend", "it"])
                }
                identifierPrefixes = ["@"]
            case .go:
                keywords = ["package", "import", "func", "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "return", "if", "else", "for", "range", "switch", "case", "default", "break", "continue", "select", "nil", "true", "false", "make", "new", "len", "append", "string", "int", "bool", "error", "float64", "byte"]
                quotes = ["\"", "'", "`"]
            case .rust:
                keywords = ["fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl", "pub", "use", "mod", "crate", "self", "Self", "super", "match", "if", "else", "for", "in", "while", "loop", "return", "break", "continue", "as", "where", "move", "ref", "async", "await", "dyn", "true", "false", "Some", "None", "Ok", "Err", "unsafe", "type"]
                quotes = ["\""]
                identifierPrefixes = ["#"]
            case .ruby:
                keywords = ["def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until", "for", "in", "do", "return", "yield", "begin", "rescue", "ensure", "raise", "require", "attr_accessor", "self", "nil", "true", "false", "and", "or", "not", "puts", "then", "case", "when"]
                lineComments = ["#"]
                blockComment = nil
                identifierPrefixes = ["@", ":"]
            case .plain:
                break
            }
        }
    }
}
