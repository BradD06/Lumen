import Foundation

/// Формулы в базах данных, как в Notion: колонка «Формула» считает значение из других колонок
/// строки. Значение не хранится, оно считается при показе (`Formula.computed`).
///
/// Язык: числа, строки в кавычках, `да` / `нет` (`true` / `false`), колонки как `prop("Срок")`
/// или `{Срок}`, `+ - * / % ^`, сравнения `== != < <= > >=`, `и` / `или` / `не` (`and`, `or`, `not`,
/// `&&`, `||`, `!`) и функции (`Formula.functions`), например `if({Готово}, "✓", "")`.
public indirect enum FormulaExpression: Hashable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case property(String)
    case unary(String, FormulaExpression)
    case binary(String, FormulaExpression, FormulaExpression)
    case call(String, [FormulaExpression])
}

/// Результат формулы.
public enum FormulaValue: Hashable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case date(DayDate)
    case empty

    /// Как значение выглядит в тексте: «3», «2.5», «31.10.2026», «да».
    public var displayText: String {
        switch self {
        case .number(let number): Formula.format(number)
        case .text(let text): text
        case .bool(let value): value ? "да" : "нет"
        case .date(let day): String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
        case .empty: ""
        }
    }

    var isTruthy: Bool {
        switch self {
        case .number(let number): number != 0
        case .text(let text): !text.isEmpty
        case .bool(let value): value
        case .date: true
        case .empty: false
        }
    }

    /// Значение для колонки базы: так его показывают, сортируют и фильтруют как обычное.
    public var propertyValue: PropertyValue? {
        switch self {
        case .number(let number): number.isFinite ? .number(number) : nil
        case .text(let text): text.isEmpty ? nil : .text(text)
        case .bool(let value): .checkbox(value)
        case .date(let day): .date(day)
        case .empty: nil
        }
    }
}

public struct FormulaError: Error, Hashable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

public enum Formula {
    /// Функции для подсказки под полем формулы: как пишется и что делает.
    public static let functions: [(syntax: String, summary: String)] = [
        ("if(условие, да, нет)", "одно из двух значений; по-русски «если»"),
        ("and(a, b) · or(a, b) · not(a)", "логика; также «и», «или», «не»"),
        ("round(x, знаков) · floor(x) · ceil(x)", "округление; «округл»"),
        ("abs(x) · sqrt(x) · pow(x, y)", "модуль, корень, степень"),
        ("min(…) · max(…) · sum(…)", "наименьшее, наибольшее, сумма"),
        ("length(текст) · upper · lower", "длина и регистр текста"),
        ("concat(…) · contains(текст, часть) · replace(текст, что, чем)", "работа с текстом"),
        ("empty(x)", "пусто ли значение; «пусто»"),
        ("format(x) · toNumber(текст)", "в текст и в число"),
        ("today()", "сегодняшний день; «сегодня»"),
        ("dateAdd(дата, n, \"days\")", "дата через n дней, недель (weeks), месяцев (months), лет (years)"),
        ("dateBetween(дата1, дата2, \"days\")", "сколько дней (недель, месяцев, лет) от второй даты до первой"),
        ("year(дата) · month(дата) · day(дата)", "год, месяц, число"),
    ]

    /// Русские имена функций и слов.
    static let aliases: [String: String] = [
        "если": "if", "и": "and", "или": "or", "не": "not",
        "округл": "round", "округлить": "round", "вниз": "floor", "вверх": "ceil",
        "модуль": "abs", "корень": "sqrt", "степень": "pow",
        "мин": "min", "макс": "max", "сумма": "sum",
        "длина": "length", "прописные": "upper", "строчные": "lower",
        "сцепить": "concat", "содержит": "contains", "заменить": "replace",
        "пусто": "empty", "текст": "format", "число": "toNumber",
        "сегодня": "today", "год": "year", "месяц": "month", "день": "day",
        "свойство": "prop", "колонка": "prop",
    ]

    // MARK: Разбор

    public static func parse(_ source: String) throws -> FormulaExpression {
        var parser = Parser(tokens: try tokenize(source))
        guard !parser.tokens.isEmpty else { throw FormulaError("Формула пустая") }
        let expression = try parser.expression(0)
        if let extra = parser.peek {
            throw FormulaError("Лишнее в формуле: «\(extra.text)»")
        }
        return expression
    }

    enum Token: Hashable {
        case number(Double)
        case text(String)
        case identifier(String)
        case property(String)
        case symbol(String)

        var text: String {
            switch self {
            case .number(let number): Formula.format(number)
            case .text(let text): "\"\(text)\""
            case .identifier(let name), .symbol(let name): name
            case .property(let name): "{\(name)}"
            }
        }
    }

    static func tokenize(_ source: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(source)
        var index = 0
        func peek(_ offset: Int = 0) -> Character? {
            index + offset < chars.count ? chars[index + offset] : nil
        }
        while let char = peek() {
            if char.isWhitespace {
                index += 1
            } else if char.isNumber, char.isASCII {
                var text = ""
                while let next = peek(), next.isASCII, next.isNumber || next == "." {
                    text.append(next)
                    index += 1
                }
                guard let number = Double(text) else { throw FormulaError("Не число: «\(text)»") }
                tokens.append(.number(number))
            } else if char == "\"" || char == "«" || char == "“" {
                let close: Character = char == "«" ? "»" : char == "“" ? "”" : "\""
                index += 1
                var text = ""
                while let next = peek(), next != close {
                    if next == "\\", let escaped = peek(1) {
                        text.append(escaped)
                        index += 2
                    } else {
                        text.append(next)
                        index += 1
                    }
                }
                guard peek() == close else { throw FormulaError("Не закрыта кавычка") }
                index += 1
                tokens.append(.text(text))
            } else if char == "{" {
                index += 1
                var name = ""
                while let next = peek(), next != "}" {
                    name.append(next)
                    index += 1
                }
                guard peek() == "}" else { throw FormulaError("Не закрыта скобка «}»") }
                index += 1
                tokens.append(.property(name.trimmingCharacters(in: .whitespaces)))
            } else if char.isLetter || char == "_" {
                var name = ""
                while let next = peek(), next.isLetter || next.isNumber || next == "_" {
                    name.append(next)
                    index += 1
                }
                tokens.append(.identifier(name))
            } else {
                let pair = peek(1).map { String([char, $0]) }
                if let pair, ["==", "!=", "<=", ">=", "&&", "||"].contains(pair) {
                    tokens.append(.symbol(pair))
                    index += 2
                } else if "+-*/%^(),<>!=".contains(char) {
                    // Одиночное «=» значит то же, что «==»: так привычнее в таблицах.
                    tokens.append(.symbol(char == "=" ? "==" : String(char)))
                    index += 1
                } else if char == "≠" || char == "≤" || char == "≥" {
                    tokens.append(.symbol(char == "≠" ? "!=" : char == "≤" ? "<=" : ">="))
                    index += 1
                } else {
                    throw FormulaError("Непонятный знак «\(char)»")
                }
            }
        }
        return tokens
    }

    struct Parser {
        var tokens: [Token]
        var position = 0

        var peek: Token? { position < tokens.count ? tokens[position] : nil }

        mutating func next() -> Token? {
            defer { position += 1 }
            return peek
        }

        /// Сила операторов: чем больше, тем раньше считается.
        static func binding(_ token: Token?) -> (op: String, power: Int)? {
            switch token {
            case .symbol(let symbol):
                switch symbol {
                case "||": return ("or", 1)
                case "&&": return ("and", 2)
                case "==", "!=": return (symbol, 3)
                case "<", "<=", ">", ">=": return (symbol, 4)
                case "+", "-": return (symbol, 5)
                case "*", "/", "%": return (symbol, 6)
                case "^": return (symbol, 8)
                default: return nil
                }
            case .identifier(let name):
                switch Formula.canonical(name) {
                case "or": return ("or", 1)
                case "and": return ("and", 2)
                default: return nil
                }
            default:
                return nil
            }
        }

        mutating func expression(_ minPower: Int) throws -> FormulaExpression {
            var left = try prefix()
            while let binding = Self.binding(peek), binding.power > minPower {
                let op = binding.op
                position += 1
                // Степень правоассоциативна: 2^3^2 = 2^9.
                let right = try expression(op == "^" ? binding.power - 1 : binding.power)
                left = .binary(op, left, right)
            }
            return left
        }

        mutating func prefix() throws -> FormulaExpression {
            guard let token = next() else { throw FormulaError("Формула оборвалась") }
            switch token {
            case .number(let number):
                return .number(number)
            case .text(let text):
                return .text(text)
            case .property(let name):
                return .property(name)
            case .symbol("-"):
                return .unary("-", try expression(7))
            case .symbol("+"):
                return try expression(7)
            case .symbol("!"):
                return .unary("not", try expression(7))
            case .symbol("("):
                let inner = try expression(0)
                guard next() == .symbol(")") else { throw FormulaError("Не хватает «)»") }
                return inner
            case .identifier(let raw):
                let name = Formula.canonical(raw)
                switch name {
                case "true", "да": return .bool(true)
                case "false", "нет": return .bool(false)
                default: break
                }
                guard peek == .symbol("(") else {
                    if name == "not" { return .unary("not", try expression(7)) }
                    throw FormulaError("Неизвестное слово «\(raw)». Колонку пишут так: {\(raw)}")
                }
                position += 1
                var arguments: [FormulaExpression] = []
                if peek != .symbol(")") {
                    while true {
                        arguments.append(try expression(0))
                        if peek == .symbol(",") {
                            position += 1
                        } else {
                            break
                        }
                    }
                }
                guard next() == .symbol(")") else { throw FormulaError("Не хватает «)» после \(raw)(…") }
                if name == "prop" {
                    guard arguments.count == 1, case .text(let property) = arguments[0] else {
                        throw FormulaError("prop() ждёт имя колонки в кавычках")
                    }
                    return .property(property)
                }
                return .call(name, arguments)
            case .symbol(let symbol):
                throw FormulaError("Неожиданный знак «\(symbol)»")
            }
        }
    }

    static func canonical(_ name: String) -> String {
        let lower = name.lowercased()
        return aliases[lower] ?? lower
    }

    // MARK: Вычисление

    /// Значения колонок-формул дописываются в строки (только в памяти, в базу не пишутся).
    public static func computed(_ rows: [DataRow], in table: DataTable, today: DayDate = .today()) -> [DataRow] {
        let formulas = table.properties.filter { $0.type == .formula }
        guard !formulas.isEmpty else { return rows }
        var parsed: [UUID: Result<FormulaExpression, FormulaError>] = [:]
        for property in formulas {
            parsed[property.id] = Result { try parse(property.formula ?? "") }.mapError { $0 as? FormulaError ?? FormulaError("\($0)") }
        }
        return rows.map { row in
            var row = row
            var values = row.values
            for property in formulas {
                let result = evaluate(property, row: row, table: table, today: today, parsed: parsed)
                switch result {
                case .success(let value):
                    values[property.id] = value.propertyValue
                case .failure(let error):
                    // Пустая формула просто пустая, ошибка видна в ячейке.
                    values[property.id] = (property.formula ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil : .text("⚠︎ \(error.message)")
                }
            }
            row.page.properties = values
            return row
        }
    }

    /// Значение одной формулы для строки, с ошибкой, если формула неверна.
    public static func evaluate(
        _ property: PropertyDefinition,
        row: DataRow,
        table: DataTable,
        today: DayDate = .today(),
        parsed: [UUID: Result<FormulaExpression, FormulaError>] = [:]
    ) -> Result<FormulaValue, FormulaError> {
        var evaluator = Evaluator(row: row, table: table, today: today, parsed: parsed)
        return Result { try evaluator.value(of: property) }.mapError { $0 as? FormulaError ?? FormulaError("\($0)") }
    }

    /// Проверка формулы на образце строки: что получится или что не так.
    public static func preview(_ source: String, property: PropertyDefinition, row: DataRow?, table: DataTable, today: DayDate = .today()) -> Result<FormulaValue, FormulaError> {
        var draft = property
        draft.formula = source
        var table = table
        if let index = table.properties.firstIndex(where: { $0.id == property.id }) {
            table.properties[index] = draft
        }
        do {
            _ = try parse(source)
        } catch {
            return .failure(error as? FormulaError ?? FormulaError("\(error)"))
        }
        guard let row else { return .success(.empty) }
        return evaluate(draft, row: row, table: table, today: today)
    }

    struct Evaluator {
        let row: DataRow
        let table: DataTable
        let today: DayDate
        var parsed: [UUID: Result<FormulaExpression, FormulaError>]
        var visiting: Set<UUID> = []

        mutating func value(of property: PropertyDefinition) throws -> FormulaValue {
            guard !visiting.contains(property.id) else {
                throw FormulaError("Формула «\(property.name)» ссылается сама на себя")
            }
            visiting.insert(property.id)
            defer { visiting.remove(property.id) }
            let expression: FormulaExpression
            if let cached = parsed[property.id] {
                expression = try cached.get()
            } else {
                expression = try Formula.parse(property.formula ?? "")
                parsed[property.id] = .success(expression)
            }
            return try evaluate(expression)
        }

        mutating func evaluate(_ expression: FormulaExpression) throws -> FormulaValue {
            switch expression {
            case .number(let number): return .number(number)
            case .text(let text): return .text(text)
            case .bool(let value): return .bool(value)
            case .property(let name): return try property(named: name)
            case .unary(let op, let operand):
                let value = try evaluate(operand)
                if op == "not" { return .bool(!value.isTruthy) }
                let number = try number(value, "минус")
                return .number(-number)
            case .binary(let op, let lhs, let rhs):
                let left = try evaluate(lhs)
                // «и» и «или» не считают правую часть, если ответ уже ясен.
                if op == "and" {
                    guard left.isTruthy else { return .bool(false) }
                    return .bool(try evaluate(rhs).isTruthy)
                }
                if op == "or" {
                    guard !left.isTruthy else { return .bool(true) }
                    return .bool(try evaluate(rhs).isTruthy)
                }
                let right = try evaluate(rhs)
                return try binary(op, left, right)
            case .call(let name, let arguments):
                return try call(name, arguments)
            }
        }

        func property(named name: String) throws -> FormulaValue {
            let key = name.trimmingCharacters(in: .whitespaces)
            guard let definition = table.properties.first(where: { $0.name.localizedCaseInsensitiveCompare(key) == .orderedSame }) else {
                if ["название", "name", "title"].contains(key.lowercased()) { return .text(row.title) }
                throw FormulaError("Нет колонки «\(key)»")
            }
            if definition.type == .formula {
                var nested = self
                return try nested.value(of: definition)
            }
            guard let value = row.value(definition.id) else {
                return definition.type == .checkbox ? .bool(false) : .empty
            }
            switch value {
            case .text(let text): return .text(text)
            case .number(let number): return .number(number)
            case .option(let id): return definition.option(id).map { .text($0.name) } ?? .empty
            case .options(let ids):
                let names = ids.compactMap { definition.option($0)?.name }
                return names.isEmpty ? .empty : .text(names.joined(separator: ", "))
            case .date(let day): return .date(day)
            case .checkbox(let isOn): return .bool(isOn)
            case .page: return .empty
            // Связь в формуле это число связанных строк: `{Задачи} > 3`.
            case .pages(let ids): return ids.isEmpty ? .empty : .number(Double(ids.count))
            }
        }

        func number(_ value: FormulaValue, _ context: String) throws -> Double {
            switch value {
            case .number(let number): return number
            case .bool(let flag): return flag ? 1 : 0
            case .empty: return 0
            case .text(let text):
                if let number = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) { return number }
                throw FormulaError("«\(text)» не число (\(context))")
            case .date:
                throw FormulaError("Дата вместо числа (\(context))")
            }
        }

        func binary(_ op: String, _ lhs: FormulaValue, _ rhs: FormulaValue) throws -> FormulaValue {
            switch op {
            case "+":
                switch (lhs, rhs) {
                case (.text, _), (_, .text):
                    return .text(lhs.displayText + rhs.displayText)
                case (.date(let day), _):
                    return .date(day.adding(days: Int(try number(rhs, "+").rounded()), calendar: Formula.calendar))
                case (_, .date(let day)):
                    return .date(day.adding(days: Int(try number(lhs, "+").rounded()), calendar: Formula.calendar))
                default:
                    return .number(try number(lhs, "+") + number(rhs, "+"))
                }
            case "-":
                if case .date(let a) = lhs, case .date(let b) = rhs {
                    return .number(Double(Formula.days(from: b, to: a)))
                }
                if case .date(let day) = lhs {
                    return .date(day.adding(days: -Int(try number(rhs, "-").rounded()), calendar: Formula.calendar))
                }
                return .number(try number(lhs, "-") - number(rhs, "-"))
            case "*":
                return .number(try number(lhs, "*") * number(rhs, "*"))
            case "/":
                let divisor = try number(rhs, "/")
                guard divisor != 0 else { throw FormulaError("Деление на ноль") }
                return .number(try number(lhs, "/") / divisor)
            case "%":
                let divisor = try number(rhs, "%")
                guard divisor != 0 else { throw FormulaError("Деление на ноль") }
                return .number(try number(lhs, "%").truncatingRemainder(dividingBy: divisor))
            case "^":
                return .number(pow(try number(lhs, "^"), try number(rhs, "^")))
            case "==": return .bool(Formula.compare(lhs, rhs) == .orderedSame)
            case "!=": return .bool(Formula.compare(lhs, rhs) != .orderedSame)
            case "<", "<=", ">", ">=":
                guard let order = Formula.compare(lhs, rhs) else {
                    throw FormulaError("Нельзя сравнить «\(lhs.displayText)» и «\(rhs.displayText)»")
                }
                switch op {
                case "<": return .bool(order == .orderedAscending)
                case "<=": return .bool(order != .orderedDescending)
                case ">": return .bool(order == .orderedDescending)
                default: return .bool(order != .orderedAscending)
                }
            default:
                throw FormulaError("Неизвестный знак «\(op)»")
            }
        }

        mutating func call(_ name: String, _ arguments: [FormulaExpression]) throws -> FormulaValue {
            func expect(_ range: ClosedRange<Int>) throws {
                guard range.contains(arguments.count) else {
                    let count = range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "от \(range.lowerBound) до \(range.upperBound)"
                    throw FormulaError("\(name)() ждёт \(count) знач.")
                }
            }
            // `if` считает только нужную ветку: в другой может быть деление на ноль.
            if name == "if" {
                try expect(2...3)
                if try evaluate(arguments[0]).isTruthy { return try evaluate(arguments[1]) }
                return arguments.count == 3 ? try evaluate(arguments[2]) : .empty
            }
            var values: [FormulaValue] = []
            for argument in arguments {
                values.append(try evaluate(argument))
            }
            switch name {
            case "and":
                return .bool(values.allSatisfy(\.isTruthy))
            case "or":
                return .bool(values.contains(where: \.isTruthy))
            case "not":
                try expect(1...1)
                return .bool(!values[0].isTruthy)
            case "round":
                try expect(1...2)
                let digits = values.count == 2 ? try number(values[1], name) : 0
                let scale = pow(10, digits.rounded())
                return .number((try number(values[0], name) * scale).rounded() / scale)
            case "floor":
                try expect(1...1)
                return .number(try number(values[0], name).rounded(.down))
            case "ceil":
                try expect(1...1)
                return .number(try number(values[0], name).rounded(.up))
            case "abs":
                try expect(1...1)
                return .number(abs(try number(values[0], name)))
            case "sqrt":
                try expect(1...1)
                let value = try number(values[0], name)
                guard value >= 0 else { throw FormulaError("Корень из отрицательного числа") }
                return .number(value.squareRoot())
            case "pow":
                try expect(2...2)
                return .number(pow(try number(values[0], name), try number(values[1], name)))
            case "min", "max":
                guard !values.isEmpty else { throw FormulaError("\(name)() ждёт хотя бы одно значение") }
                var best = values[0]
                for value in values.dropFirst() {
                    guard let order = Formula.compare(value, best) else { throw FormulaError("\(name)(): значения разного вида") }
                    if name == "min" ? order == .orderedAscending : order == .orderedDescending { best = value }
                }
                return best
            case "sum":
                var total = 0.0
                for value in values {
                    total += try number(value, name)
                }
                return .number(total)
            case "length":
                try expect(1...1)
                return .number(Double(values[0].displayText.count))
            case "upper":
                try expect(1...1)
                return .text(values[0].displayText.uppercased())
            case "lower":
                try expect(1...1)
                return .text(values[0].displayText.lowercased())
            case "concat":
                return .text(values.map(\.displayText).joined())
            case "contains":
                try expect(2...2)
                let part = values[1].displayText
                return .bool(part.isEmpty || values[0].displayText.localizedCaseInsensitiveContains(part))
            case "replace":
                try expect(3...3)
                let target = values[1].displayText
                guard !target.isEmpty else { return .text(values[0].displayText) }
                return .text(values[0].displayText.replacingOccurrences(of: target, with: values[2].displayText))
            case "empty":
                try expect(1...1)
                if case .bool = values[0] { return .bool(false) }
                return .bool(values[0].displayText.trimmingCharacters(in: .whitespaces).isEmpty)
            case "format":
                try expect(1...1)
                return .text(values[0].displayText)
            case "tonumber":
                try expect(1...1)
                return .number(try number(values[0], name))
            case "today", "now":
                try expect(0...0)
                return .date(today)
            case "dateadd":
                try expect(2...3)
                let day = try date(values[0], name)
                let amount = Int(try number(values[1], name).rounded())
                let unit = try Formula.unit(values.count == 3 ? values[2].displayText : "days")
                let date = Formula.calendar.date(byAdding: unit, value: amount, to: day.date(calendar: Formula.calendar)) ?? day.date(calendar: Formula.calendar)
                return .date(DayDate(date, calendar: Formula.calendar))
            case "datebetween":
                try expect(2...3)
                let a = try date(values[0], name)
                let b = try date(values[1], name)
                let unit = try Formula.unit(values.count == 3 ? values[2].displayText : "days")
                let parts = Formula.calendar.dateComponents([unit], from: b.date(calendar: Formula.calendar), to: a.date(calendar: Formula.calendar))
                return .number(Double(parts.value(for: unit) ?? 0))
            case "year", "month", "day":
                try expect(1...1)
                let day = try date(values[0], name)
                return .number(Double(name == "year" ? day.year : name == "month" ? day.month : day.day))
            default:
                throw FormulaError("Нет функции «\(name)»")
            }
        }

        func date(_ value: FormulaValue, _ context: String) throws -> DayDate {
            switch value {
            case .date(let day): return day
            case .text(let text):
                if let day = DayDate(string: text) { return day }
                throw FormulaError("«\(text)» не дата (\(context))")
            default:
                throw FormulaError("\(context)() ждёт дату")
            }
        }
    }

    /// Григорианский календарь: «через месяц» одинаково на всех устройствах.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    static func days(from a: DayDate, to b: DayDate) -> Int {
        calendar.dateComponents([.day], from: a.date(calendar: calendar), to: b.date(calendar: calendar)).day ?? 0
    }

    static func unit(_ name: String) throws -> Calendar.Component {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "days", "day", "дни", "дней", "день": .day
        case "weeks", "week", "недели", "недель", "неделя": .weekOfYear
        case "months", "month", "месяцы", "месяцев", "месяц": .month
        case "years", "year", "годы", "лет", "год": .year
        default: throw FormulaError("Неизвестная единица «\(name)»: days, weeks, months или years")
        }
    }

    static func compare(_ lhs: FormulaValue, _ rhs: FormulaValue) -> ComparisonResult? {
        func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
            a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        }
        switch (lhs, rhs) {
        case (.number(let a), .number(let b)): return order(a, b)
        case (.date(let a), .date(let b)): return order(a, b)
        case (.bool(let a), .bool(let b)): return a == b ? .orderedSame : (a ? .orderedDescending : .orderedAscending)
        case (.text(let a), .text(let b)): return a.localizedCaseInsensitiveCompare(b)
        case (.empty, .empty): return .orderedSame
        case (.empty, .number(let b)): return order(0, b)
        case (.number(let a), .empty): return order(a, 0)
        case (.empty, .text(let b)): return b.isEmpty ? .orderedSame : .orderedAscending
        case (.text(let a), .empty): return a.isEmpty ? .orderedSame : .orderedDescending
        case (.empty, .bool(let b)): return b ? .orderedAscending : .orderedSame
        case (.bool(let a), .empty): return a ? .orderedDescending : .orderedSame
        case (.text(let a), .number(let b)):
            return Double(a).map { order($0, b) } ?? a.localizedCaseInsensitiveCompare(format(b))
        case (.number(let a), .text(let b)):
            return Double(b).map { order(a, $0) } ?? format(a).localizedCaseInsensitiveCompare(b)
        default: return nil
        }
    }

    /// Число без лишних знаков: 3, 2.5, 0.3 (а не 0.30000000000000004).
    public static func format(_ number: Double) -> String {
        guard number.isFinite else { return number.isNaN ? "не число" : (number > 0 ? "∞" : "−∞") }
        let rounded = (number * 1e9).rounded() / 1e9
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int64(rounded))
        }
        return String(rounded)
    }
}
