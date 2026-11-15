import Foundation
import Testing
@testable import LumenCore

struct FormulaTests {
    let price = PropertyDefinition(name: "Цена", type: .number)
    let count = PropertyDefinition(name: "Количество", type: .number)
    let done = PropertyDefinition(name: "Готово", type: .checkbox)
    let due = PropertyDefinition(name: "Срок", type: .date)
    let stage = PropertyDefinition(name: "Этап", type: .select, options: [SelectOption(name: "Черновик")])
    let today = DayDate(year: 2026, month: 11, day: 15)

    private func table(_ formulas: [PropertyDefinition]) -> DataTable {
        DataTable(pageId: UUID(), properties: [price, count, done, due, stage] + formulas, views: [DataView(name: "Таблица", layout: .table)])
    }

    private func row(_ title: String = "Строка", key: String = "a", _ values: [UUID: PropertyValue] = [:]) -> DataRow {
        DataRow(page: Page(title: title, properties: PropertyValues(values), sortKey: key))
    }

    private func value(_ source: String, _ values: [UUID: PropertyValue] = [:], title: String = "Строка") throws -> FormulaValue {
        let formula = PropertyDefinition(name: "Итог", type: .formula, formula: source)
        return try Formula.evaluate(formula, row: row(title, values), table: table([formula]), today: today).get()
    }

    private func error(_ source: String) -> String? {
        let formula = PropertyDefinition(name: "Итог", type: .formula, formula: source)
        if case .failure(let error) = Formula.evaluate(formula, row: row(), table: table([formula]), today: today) {
            return error.message
        }
        return nil
    }

    @Test func arithmeticFollowsPrecedence() throws {
        #expect(try value("1 + 2 * 3") == .number(7))
        #expect(try value("(1 + 2) * 3") == .number(9))
        #expect(try value("2 ^ 3 ^ 2") == .number(512))
        #expect(try value("-2 + 10 % 4") == .number(0))
        #expect(try value("0.1 + 0.2").displayText == "0.3")
        #expect(try value("{Цена} * {Количество}", [price.id: .number(12.5), count.id: .number(4)]) == .number(50))
        #expect(try value("prop(\"Цена\") + 1", [price.id: .number(2)]) == .number(3))
        #expect(try value("{Цена} + 1") == .number(1), "Пустое число считается нулём")
    }

    @Test func textLogicAndRussianWords() throws {
        #expect(try value("\"Итого: \" + {Цена}", [price.id: .number(3)]) == .text("Итого: 3"))
        #expect(try value("если({Готово}, \"✓\", \"…\")", [done.id: .checkbox(true)]) == .text("✓"))
        #expect(try value("if({Готово}, 1, 2)") == .number(2))
        #expect(try value("{Цена} > 10 и не {Готово}", [price.id: .number(20)]) == .bool(true))
        #expect(try value("{Этап} = «Черновик»", [stage.id: .option(stage.options[0].id)]) == .bool(true))
        #expect(try value("upper({Название})", title: "Конспект") == .text("КОНСПЕКТ"))
        #expect(try value("length(\"абв\") + round(2.346, 2)").displayText == "5.35")
        #expect(try value("contains({Название}, \"глава\")", title: "Глава 3") == .bool(true))
        #expect(try value("empty({Срок})") == .bool(true))
        #expect(try value("max(3, 9, 4) + min(2, 5) + sum(1, 2, 3)") == .number(17))
    }

    @Test func dates() throws {
        let deadline = DayDate(year: 2026, month: 11, day: 20)
        #expect(try value("dateBetween({Срок}, today(), \"days\")", [due.id: .date(deadline)]) == .number(5))
        #expect(try value("{Срок} - сегодня()", [due.id: .date(deadline)]) == .number(5))
        #expect(try value("{Срок} + 12", [due.id: .date(deadline)]) == .date(DayDate(year: 2026, month: 12, day: 2)))
        #expect(try value("dateAdd({Срок}, 1, \"months\")", [due.id: .date(deadline)]) == .date(DayDate(year: 2026, month: 12, day: 20)))
        #expect(try value("year(today()) * 100 + month(today())") == .number(202611))
        #expect(try value("{Срок} < today()", [due.id: .date(deadline)]) == .bool(false))
    }

    @Test func clearErrors() {
        #expect(error("1 +") == "Формула оборвалась")
        #expect(error("{Нет такой}") == "Нет колонки «Нет такой»")
        #expect(error("1 / 0") == "Деление на ноль")
        #expect(error("foo(1)") == "Нет функции «foo»")
        #expect(error("Цена * 2")?.contains("{Цена}") == true, "Подсказка, как написать колонку")
        #expect(error("(1 + 2") == "Не хватает «)»")
        #expect(error("\"текст") == "Не закрыта кавычка")
        #expect(error("1 2") == "Лишнее в формуле: «2»")
        #expect(error("if(1 > 0, 1, 1 / 0)") == nil, "Ненужная ветка не считается")
    }

    @Test func formulasUseOtherFormulasButNotThemselves() throws {
        var first = PropertyDefinition(name: "Сумма", type: .formula, formula: "{Цена} * 2")
        let second = PropertyDefinition(name: "Итог", type: .formula, formula: "{Сумма} + 1")
        let values = [price.id: PropertyValue.number(5)]
        #expect(try Formula.evaluate(second, row: row("Строка", values), table: table([first, second])).get() == .number(11))

        first.formula = "{Итог} + 1"
        let result = Formula.evaluate(second, row: row("Строка", values), table: table([first, second]))
        guard case .failure(let error) = result else {
            Issue.record("Цикл должен дать ошибку")
            return
        }
        #expect(error.message.contains("ссылается сама на себя"))
    }

    @Test func computedValuesFilterAndSort() {
        let total = PropertyDefinition(name: "Итог", type: .formula, formula: "{Цена} * {Количество}")
        var data = table([total])
        let rows = [
            row("Дорого", key: "a", [price.id: .number(100), count.id: .number(3)]),
            row("Дёшево", key: "b", [price.id: .number(5), count.id: .number(2)]),
            row("Средне", key: "c", [price.id: .number(20), count.id: .number(2)]),
        ]
        let computed = Formula.computed(rows, in: data, today: today)
        #expect(computed.map { $0.value(total.id) } == [.number(300), .number(10), .number(40)])
        #expect(rows[0].value(total.id) == nil, "В исходные строки ничего не пишется")

        data.views[0].filters = [DataFilter(propertyId: total.id, op: .greater, value: .text("20"))]
        data.views[0].sorts = [DataSort(propertyId: total.id, ascending: true)]
        let visible = DataQuery.rows(rows, in: data, view: data.views[0], today: today)
        #expect(visible.map(\.title) == ["Средне", "Дорого"])
        #expect(DataQuery.presetValues(for: data.views[0], in: data).isEmpty, "Формуле значение не задают")
    }

    @Test func brokenFormulaShowsErrorInCell() {
        let broken = PropertyDefinition(name: "Итог", type: .formula, formula: "{Цена} +")
        let empty = PropertyDefinition(name: "Пусто", type: .formula)
        let computed = Formula.computed([row()], in: table([broken, empty]), today: today)
        #expect(computed[0].value(broken.id)?.text?.hasPrefix("⚠︎") == true)
        #expect(computed[0].value(empty.id) == nil)
    }

    @Test func definitionsWithoutFormulaStillDecode() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Цена","type":"number","options":[]}"#
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: Data(json.utf8))
        #expect(decoded.formula == nil)
        let formula = PropertyDefinition(name: "Итог", type: .formula, formula: "1 + 1")
        let roundTrip = try JSONDecoder().decode(PropertyDefinition.self, from: JSONEncoder().encode(formula))
        #expect(roundTrip == formula)
    }
}
