import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:xml/xml.dart';

import 'image_collector.dart';
import 'imported_book.dart';
import 'text_decode.dart';
import 'txt_parser.dart' show guessLanguage;
import 'xml_text.dart';

/// FB2 (и FB2 в ZIP): сведения из `title-info`, главы — разделы `section`,
/// обложка из `binary`. Примечания (`body name="notes"`) и ссылки на них пропускаем.
ImportedBook parseFb2(List<int> bytes, {required String fallbackTitle}) {
  final source = decodeText(bytes, declared: xmlDeclaredEncoding(bytes));
  final doc = parseXml(source);
  if (doc == null) throw const ImportException('Файл FB2 повреждён: не читается как XML.');

  final info = firstNamed(doc, 'title-info');
  final title = info == null ? '' : cleanParagraph(firstNamed(info, 'book-title')?.innerText ?? '');
  final authorElement = info == null ? null : firstNamed(info, 'author');
  String? author;
  if (authorElement != null) {
    final names = ['first-name', 'middle-name', 'last-name']
        .map((n) => cleanParagraph(firstNamed(authorElement, n)?.innerText ?? ''))
        .where((n) => n.isNotEmpty);
    author = names.isNotEmpty
        ? names.join(' ')
        : cleanParagraph(firstNamed(authorElement, 'nickname')?.innerText ?? '');
    if (author.isEmpty) author = null;
  }
  final lang = info == null ? '' : cleanParagraph(firstNamed(info, 'lang')?.innerText ?? '');

  final chapters = <Chapter>[];
  final bodies = elementsNamed(doc, 'body').where((b) {
    final name = attr(b, 'name') ?? '';
    return name != 'notes' && name != 'comments' && name != 'footnotes';
  });
  final binaries = {
    for (final b in elementsNamed(doc, 'binary'))
      if (attr(b, 'id') != null) attr(b, 'id')!: b,
  };
  final coverId = _coverId(info);
  final collector = ImageCollector();
  String? image(XmlElement e) {
    final href = attr(e, 'href');
    if (href == null) return null;
    final id = href.startsWith('#') ? href.substring(1) : href;
    if (id == coverId) return null;
    final binary = binaries[id];
    final data = binary == null ? null : _decode(binary);
    return data == null ? null : collector.add(id, data, _binaryExtension(binary!));
  }

  for (final body in bodies) {
    _collect(body, chapters, image, parentTitle: null, isBody: true);
  }
  if (chapters.isEmpty) throw const ImportException('В FB2 не нашлось текста.');

  final cover = _cover(doc, info);
  final sample = chapters.first.text;
  return ImportedBook(
    title: title.isEmpty ? fallbackTitle : title,
    author: author,
    language: lang.isEmpty ? guessLanguage(sample) : lang.split(RegExp('[-_]')).first.toLowerCase(),
    chapters: chapters,
    cover: cover?.$1,
    coverExtension: cover?.$2,
    images: collector.files,
  );
}

/// `.fb2.zip`: внутри один файл FB2.
ImportedBook parseFb2Zip(List<int> bytes, {required String fallbackTitle}) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const ImportException('Архив повреждён.');
  }
  final fb2 = zip.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('.fb2')).firstOrNull;
  if (fb2 == null) throw const ImportException('В архиве нет файла FB2.');
  return parseFb2(fb2.content, fallbackTitle: fallbackTitle);
}

bool _isNoteLink(XmlElement e) => e.name.local == 'a' && attr(e, 'type') == 'note';

String _titleOf(XmlElement section) {
  final title = section.childElements.where((e) => e.name.local == 'title').firstOrNull;
  if (title == null) return '';
  return title.childElements
      .map((p) => inlineText(p, skip: _isNoteLink))
      .where((t) => t.isNotEmpty)
      .join('. ');
}

/// Раздел с подразделами даёт главы из подразделов; его собственный текст до них
/// (эпиграф, вступление) — отдельная глава с его названием.
void _collect(
  XmlElement section,
  List<Chapter> out,
  _ImageName image, {
  required String? parentTitle,
  bool isBody = false,
}) {
  final ownTitle = isBody ? '' : _titleOf(section);
  final paragraphs = <String>[];
  final images = <ChapterImage>[];
  final subsections = <XmlElement>[];
  for (final child in section.childElements) {
    switch (child.name.local) {
      case 'section':
        subsections.add(child);
      case 'title':
        if (!isBody) {
          for (final p in child.childElements) {
            final t = inlineText(p, skip: _isNoteLink);
            if (t.isNotEmpty) paragraphs.add(t);
          }
        }
      case 'empty-line' || 'binary':
        break;
      default:
        _paragraphs(child, paragraphs, images, image);
    }
  }

  final title = ownTitle.isNotEmpty ? ownTitle : (parentTitle ?? '');
  final hasOwnText = paragraphs.where((p) => hasWords(p)).length > (ownTitle.isEmpty ? 0 : 1);
  if (hasOwnText) {
    out.add(
      Chapter.fromParagraphs(
        title: title.isEmpty ? 'Глава ${out.length + 1}' : title,
        paragraphs: paragraphs,
        images: images,
      ),
    );
  }
  for (final sub in subsections) {
    _collect(
      sub,
      out,
      image,
      parentTitle: hasOwnText ? null : (ownTitle.isEmpty ? null : ownTitle),
    );
  }
}

/// Абзацы блока: `p`, `v` (строка стиха), `subtitle`, `text-author` — каждый абзац;
/// `poem`, `stanza`, `cite`, `epigraph` — контейнеры.
void _paragraphs(XmlElement e, List<String> out, List<ChapterImage> images, _ImageName image) {
  switch (e.name.local) {
    case 'image':
      final name = image(e);
      if (name != null) images.add(ChapterImage(position: out.length, name: name));
    case 'p' || 'v' || 'subtitle' || 'text-author':
      final t = inlineText(e, skip: _isNoteLink);
      if (t.isNotEmpty && hasWords(t)) out.add(t);
      // Картинка внутри абзаца — после него.
      for (final inner in e.childElements.where((c) => c.name.local == 'image')) {
        final name = image(inner);
        if (name != null) images.add(ChapterImage(position: out.length, name: name));
      }
    case 'table':
      for (final row in e.childElements) {
        final t = inlineText(row, skip: _isNoteLink);
        if (t.isNotEmpty) out.add(t);
      }
    default:
      for (final child in e.childElements) {
        if (child.name.local == 'empty-line') continue;
        _paragraphs(child, out, images, image);
      }
  }
}

typedef _ImageName = String? Function(XmlElement image);

String? _coverId(XmlElement? info) {
  final page = info == null ? null : firstNamed(info, 'coverpage');
  final image = page == null ? null : firstNamed(page, 'image');
  final href = image == null ? null : attr(image, 'href');
  if (href == null) return null;
  return href.startsWith('#') ? href.substring(1) : href;
}

Uint8List? _decode(XmlElement binary) {
  try {
    return base64.decode(binary.innerText.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    return null;
  }
}

String _binaryExtension(XmlElement binary) {
  final type = attr(binary, 'content-type') ?? '';
  return type.contains('png') ? 'png' : (type.contains('gif') ? 'gif' : 'jpg');
}

(Uint8List, String)? _cover(XmlDocument doc, XmlElement? info) {
  final id = _coverId(info);
  if (id == null) return null;
  final binary = elementsNamed(doc, 'binary').where((b) => attr(b, 'id') == id).firstOrNull;
  final data = binary == null ? null : _decode(binary);
  return data == null ? null : (data, _binaryExtension(binary!));
}
