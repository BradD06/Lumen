import Foundation

/// Простое дерево XML для разбора книг и документов Office. Файлы небольшие,
/// а обходить дерево гораздо проще, чем писать отдельный SAX-разбор под каждый формат.
final class XElement {
    /// Имя вместе с префиксом пространства имён: `w:p`, `dc:title`.
    let name: String
    let attributes: [String: String]
    private(set) var nodes: [XNode] = []
    weak var parent: XElement?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// Имя без префикса: `p` для `w:p`.
    var localName: String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    var elements: [XElement] {
        nodes.compactMap { if case .element(let element) = $0 { element } else { nil } }
    }

    /// Атрибут по имени без префикса: `attribute("val")` найдёт и `w:val`, и `val`.
    func attribute(_ local: String) -> String? {
        if let value = attributes[local] { return value }
        return attributes.first { $0.key.split(separator: ":").last.map(String.init) == local }?.value
    }

    func child(_ local: String) -> XElement? {
        elements.first { $0.localName == local }
    }

    func children(_ local: String) -> [XElement] {
        elements.filter { $0.localName == local }
    }

    /// Все потомки с таким именем, в порядке документа.
    func descendants(_ local: String) -> [XElement] {
        var result: [XElement] = []
        for element in elements {
            if element.localName == local { result.append(element) }
            result += element.descendants(local)
        }
        return result
    }

    /// Весь текст внутри элемента.
    var text: String {
        nodes.map { node in
            switch node {
            case .text(let text): text
            case .element(let element): element.text
            }
        }.joined()
    }

    fileprivate func append(_ node: XNode) {
        if case .text(let text) = node, case .text(let previous) = nodes.last {
            nodes[nodes.count - 1] = .text(previous + text)
        } else {
            nodes.append(node)
        }
    }
}

enum XNode {
    case element(XElement)
    case text(String)
}

enum XMLTree {
    /// Корневой элемент документа или `nil`, если XML не разобрать.
    static func parse(_ data: Data) -> XElement? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldResolveExternalEntities = false
        guard parser.parse() || builder.root != nil else { return nil }
        return builder.root
    }

    static func parse(contentsOf url: URL) -> XElement? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XElement?
        private var stack: [XElement] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let element = XElement(name: elementName, attributes: attributeDict)
            if let parent = stack.last {
                element.parent = parent
                parent.append(.element(element))
            } else if root == nil {
                root = element
            }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.append(.text(string))
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let string = String(data: CDATABlock, encoding: .utf8) {
                stack.last?.append(.text(string))
            }
        }
    }
}

enum HTML {
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    /// Целая страница с телом `body`. Оформление добавляет читалка, здесь только разметка.
    static func page(title: String, body: String, extraStyle: String = "") -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(extraStyle)</style>
        </head><body>
        \(body)
        </body></html>
        """
    }
}
