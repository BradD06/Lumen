import 'package:xml/xml.dart';

import 'imported_book.dart';

/// Разобрать XML/XHTML. HTML-сущности (`&nbsp;`, `&mdash;`) понимаем.
XmlDocument? parseXml(String source) {
  try {
    return XmlDocument.parse(source, entityMapping: XmlDefaultEntityMapping.html5());
  } on XmlException {
    return null;
  }
}

Iterable<XmlElement> elementsNamed(XmlNode root, String localName) =>
    root.descendants.whereType<XmlElement>().where((e) => e.name.local == localName);

XmlElement? firstNamed(XmlNode root, String localName) =>
    elementsNamed(root, localName).firstOrNull;

/// Атрибут по локальному имени, с любым пространством имён (`epub:type`, `l:href`).
String? attr(XmlElement e, String localName) =>
    e.attributes.where((a) => a.name.local == localName).firstOrNull?.value;

/// Текст элемента без сносок, с пробелами между блоками.
String inlineText(XmlElement e, {bool Function(XmlElement)? skip}) {
  final out = StringBuffer();
  void walk(XmlNode node) {
    for (final child in node.children) {
      if (child is XmlText || child is XmlCDATA) {
        out.write(child.value);
      } else if (child is XmlElement) {
        if (skip?.call(child) ?? false) continue;
        if (child.name.local == 'br') {
          out.write(' ');
          continue;
        }
        walk(child);
        out.write(_blockLike.contains(child.name.local) ? ' ' : '');
      }
    }
  }

  walk(e);
  return cleanParagraph(out.toString());
}

const _blockLike = {'p', 'div', 'li', 'v', 'td', 'th', 'tr', 'dt', 'dd', 'h1', 'h2', 'h3'};
