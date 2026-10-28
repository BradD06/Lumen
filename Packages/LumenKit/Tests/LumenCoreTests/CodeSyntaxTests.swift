import Testing
@testable import LumenCore

struct CodeSyntaxTests {
    @Test(arguments: [
        ("let name = \"Ivan\"", CodeLanguage.swift),
        ("import SwiftUI\n\nstruct ContentView: View {\n    @State var count = 0\n}", .swift),
        ("def greet(name):\n    print(f\"Hi {name}\")\n    return None", .python),
        ("const items = [1, 2, 3];\nconsole.log(items.map(x => x * 2));", .javascript),
        ("interface User {\n  name: string;\n  age: number;\n}", .typescript),
        ("{\"name\": \"Ivan\", \"age\": 20}", .json),
        ("<div class=\"card\">\n  <p>Привет</p>\n</div>", .html),
        (".card {\n  color: red;\n  padding: 8px;\n}", .css),
        ("SELECT name, age FROM users WHERE age > 18;", .sql),
        ("#!/bin/bash\necho \"hello\" | grep h", .shell),
        ("#include <iostream>\nint main() {\n    std::cout << \"hi\";\n}", .cpp),
        ("public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"hi\");\n    }\n}", .java),
        ("fun main() {\n    val x = 1\n    println(x)\n}", .kotlin),
        ("package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"hi\")\n}", .go),
        ("fn main() {\n    let mut x = 5;\n    println!(\"{}\", x);\n}", .rust),
        ("def hello\n  puts \"hi\"\nend", .ruby),
        ("просто заметка", .plain),
        ("", .plain),
    ])
    func detectsLanguage(code: String, language: CodeLanguage) {
        #expect(CodeLanguage.detect(code) == language)
    }

    @Test func swiftTokens() {
        let tokens = CodeHighlighter.tokens(in: "let name = \"Ivan\" // имя\nprint(42)", language: .swift)
        #expect(tokens.map(\.text).joined() == "let name = \"Ivan\" // имя\nprint(42)")
        #expect(tokens.contains(CodeToken("let", .keyword)))
        #expect(tokens.contains(CodeToken("\"Ivan\"", .string)))
        #expect(tokens.contains(CodeToken("// имя", .comment)))
        #expect(tokens.contains(CodeToken("print", .function)))
        #expect(tokens.contains(CodeToken("42", .number)))
    }

    @Test func typesAndAttributes() {
        let tokens = CodeHighlighter.tokens(in: "@State var user: User", language: .swift)
        #expect(tokens.contains(CodeToken("@State", .keyword)))
        #expect(tokens.contains(CodeToken("User", .type)))
    }

    @Test func jsonKeysDifferFromValues() {
        let tokens = CodeHighlighter.tokens(in: "{\"a\": \"b\", \"n\": true}", language: .json)
        #expect(tokens.contains(CodeToken("\"a\"", .attribute)))
        #expect(tokens.contains(CodeToken("\"b\"", .string)))
        #expect(tokens.contains(CodeToken("true", .keyword)))
    }

    @Test func sqlKeywordsIgnoreCase() {
        let tokens = CodeHighlighter.tokens(in: "select * FROM t", language: .sql)
        #expect(tokens.contains(CodeToken("select", .keyword)))
        #expect(tokens.contains(CodeToken("FROM", .keyword)))
    }

    @Test func htmlTags() {
        let tokens = CodeHighlighter.tokens(in: "<a href=\"x\">link</a>", language: .html)
        #expect(tokens.filter { $0.kind == .tag }.map(\.text) == ["a", "a"])
        #expect(tokens.contains(CodeToken("href", .attribute)))
        #expect(tokens.contains(CodeToken("\"x\"", .string)))
        #expect(tokens.contains(CodeToken(">link</", .plain)))
    }

    @Test func unclosedStringStopsAtLineEnd() {
        let tokens = CodeHighlighter.tokens(in: "x = \"abc\nlet y", language: .swift)
        #expect(tokens.contains(CodeToken("let", .keyword)))
    }

    @Test(arguments: CodeLanguage.allCases)
    func tokensCoverWholeText(language: CodeLanguage) {
        let code = "fn x(a: Int) -> \"s\\\"\" /* c */ # $v 0x1F @x 'q' `t` <b>\n-- d"
        #expect(CodeHighlighter.tokens(in: code, language: language).map(\.text).joined() == code)
    }
}
