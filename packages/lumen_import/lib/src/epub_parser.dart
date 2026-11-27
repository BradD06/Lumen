import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:xml/xml.dart';

import 'image_collector.dart';
import 'imported_book.dart';
import 'txt_parser.dart' show guessLanguage;
import 'xml_text.dart';

/// EPUB 2 и 3: сведения из OPF, главы по порядку чтения (spine), названия глав
/// из оглавления (nav или NCX), обложка. Сноски и примечания пропускаем.
ImportedBook parseEpub(List<int> bytes, {required String fallbackTitle}) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const ImportException('Файл EPUB повреждён: не открывается как архив.');
  }
  final files = {
    for (final f in zip.files)
      if (f.isFile) f.name: f,
  };
  String? read(String path) {
    final file = files[path];
    if (file == null) return null;
    return utf8.decode(file.content, allowMalformed: true);
  }

  final container = parseXml(read('META-INF/container.xml') ?? '');
  final opfPath = container == null ? null : attr(firstNamed(container, 'rootfile')!, 'full-path');
  final opf = opfPath == null ? null : parseXml(read(opfPath) ?? '');
  if (opfPath == null || opf == null) {
    throw const ImportException('В EPUB нет описания книги (OPF).');
  }
  final base = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';

  String text(String name) => firstNamed(opf, name)?.innerText.trim() ?? '';
  final title = text('title');
  final author = text('creator');
  final language = text('language');

  // Манифест: id → файл.
  final manifest = <String, _Item>{};
  for (final item in elementsNamed(opf, 'item')) {
    final id = attr(item, 'id');
    final href = attr(item, 'href');
    if (id == null || href == null) continue;
    manifest[id] = _Item(
      path: _resolve(base, href),
      mediaType: attr(item, 'media-type') ?? '',
      properties: attr(item, 'properties') ?? '',
    );
  }

  final toc = _tableOfContents(opf, manifest, read);

  final chapters = <Chapter>[];
  final allText = StringBuffer();
  final images = ImageCollector();
  final coverItem = _coverItem(opf, manifest);
  for (final ref in elementsNamed(opf, 'itemref')) {
    if (attr(ref, 'linear') == 'no') continue;
    final item = manifest[attr(ref, 'idref')];
    if (item == null || !item.mediaType.contains('html')) continue;
    final source = read(item.path);
    if (source == null) continue;
    final doc = _parseHtml(source);
    if (_isNotes(doc, toc[item.path])) continue;
    final dir = item.path.contains('/')
        ? item.path.substring(0, item.path.lastIndexOf('/') + 1)
        : '';
    final blocks = _blocks(doc, (src) {
      final path = _resolve(dir, src);
      // Обложка уже стоит отдельно, в тексте её не повторяем.
      if (path == coverItem?.path) return null;
      final file = files[path];
      if (file == null) return null;
      return images.add(path, file.content, _extension('', path));
    });
    if (!blocks.paragraphs.any(hasWords)) continue;
    // Страница только с заголовком («Часть первая») — не отдельная глава.
    if (blocks.paragraphs.length == 1 && blocks.paragraphs.first == blocks.heading) continue;
    final chapterTitle = toc[item.path] ?? blocks.heading ?? 'Глава ${chapters.length + 1}';
    chapters.add(
      Chapter.fromParagraphs(
        title: chapterTitle,
        paragraphs: blocks.paragraphs,
        images: blocks.images,
      ),
    );
    if (allText.length < 5000) allText.writeAll(blocks.paragraphs, ' ');
  }
  if (chapters.isEmpty) throw const ImportException('В EPUB не нашлось текста.');

  final cover = _cover(coverItem, files);
  return ImportedBook(
    title: title.isEmpty ? fallbackTitle : title,
    author: author.isEmpty ? null : author,
    language: language.isEmpty ? guessLanguage(allText.toString()) : _shortLanguage(language),
    chapters: chapters,
    cover: cover?.$1,
    coverExtension: cover?.$2,
    images: images.files,
  );
}

final class _Item {
  const _Item({required this.path, required this.mediaType, required this.properties});
  final String path;
  final String mediaType;
  final String properties;
}

String _shortLanguage(String code) => code.split(RegExp('[-_]')).first.toLowerCase();

/// Путь внутри архива относительно папки OPF: `Text/../Images/a.jpg` → `Images/a.jpg`.
String _resolve(String base, String href) {
  final clean = Uri.decodeFull(href.split('#').first);
  final parts = <String>[];
  for (final part in '$base$clean'.split('/')) {
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// Файл главы → название из оглавления (первое для файла).
Map<String, String> _tableOfContents(
  XmlDocument opf,
  Map<String, _Item> manifest,
  String? Function(String) read,
) {
  final result = <String, String>{};
  void add(String dir, String? href, String label) {
    if (href == null || label.isEmpty) return;
    result.putIfAbsent(_resolve(dir, href), () => label);
  }

  String dirOf(String path) =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/') + 1) : '';

  // EPUB 3: <nav epub:type="toc">.
  final nav = manifest.values.where((i) => i.properties.split(' ').contains('nav')).firstOrNull;
  final navDoc = nav == null ? null : parseXml(read(nav.path) ?? '');
  if (nav != null && navDoc != null) {
    final tocNav =
        elementsNamed(navDoc, 'nav').where((n) => attr(n, 'type') == 'toc').firstOrNull ??
        firstNamed(navDoc, 'nav');
    if (tocNav != null) {
      for (final a in elementsNamed(tocNav, 'a')) {
        add(dirOf(nav.path), attr(a, 'href'), inlineText(a));
      }
    }
  }
  if (result.isNotEmpty) return result;

  // EPUB 2: NCX.
  final ncx = manifest.values.where((i) => i.mediaType == 'application/x-dtbncx+xml').firstOrNull;
  final ncxDoc = ncx == null ? null : parseXml(read(ncx.path) ?? '');
  if (ncx != null && ncxDoc != null) {
    for (final point in elementsNamed(ncxDoc, 'navPoint')) {
      final label = firstNamed(point, 'text');
      final content = firstNamed(point, 'content');
      if (label == null || content == null) continue;
      add(dirOf(ncx.path), attr(content, 'src'), cleanParagraph(label.innerText));
    }
  }
  return result;
}

XmlDocument _parseHtml(String source) {
  final doc = parseXml(source);
  if (doc != null) return doc;
  // Сломанный XHTML: убрать DOCTYPE и скрипты, остальное как текст абзацев <p>.
  final paragraphs = RegExp(r'<(p|h[1-6]|li|div)[^>]*>([\s\S]*?)</\1>', caseSensitive: false)
      .allMatches(source)
      .map((m) => m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ' '))
      .map((t) => const HtmlEscape().convert(_unescape(t)));
  return parseXml('<html><body>${paragraphs.map((p) => '<p>$p</p>').join()}</body></html>') ??
      XmlDocument();
}

String _unescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'&#?\w+;'), ' ');

/// Файл со сносками или примечаниями — не глава.
bool _isNotes(XmlDocument doc, String? tocLabel) {
  if (tocLabel != null &&
      RegExp(
        r'^(примечани|сноски|комментари|notes|footnotes|endnotes)',
        caseSensitive: false,
      ).hasMatch(tocLabel)) {
    return true;
  }
  final body = firstNamed(doc, 'body');
  if (body == null) return false;
  final section = firstNamed(body, 'section');
  final types = '${attr(body, 'type') ?? ''} ${section == null ? '' : attr(section, 'type') ?? ''}';
  return RegExp(r'\b(footnotes|endnotes|rearnotes)\b').hasMatch(types);
}

final class _Blocks {
  _Blocks(this.paragraphs, this.heading, this.images);
  final List<String> paragraphs;
  final String? heading;
  final List<ChapterImage> images;
}

const _blockTags = {
  'p', 'div', 'li', 'blockquote', 'pre', 'dt', 'dd', 'td', 'th', 'figcaption', //
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'section', 'article', 'body', 'ul', 'ol', 'table', 'tr',
};
const _skipTags = {'head', 'script', 'style', 'rt', 'rp', 'math', 'nav'};

bool _isFootnote(XmlElement e) {
  final type = attr(e, 'type') ?? '';
  final noteType = RegExp(r'\b(noteref|footnotes?|endnotes?|rearnotes?|note|annoref)\b');
  if (noteType.hasMatch(type)) return true;
  if (e.name.local == 'aside') return true;
  // <sup><a href="#n1">1</a></sup> — маркер сноски.
  if (e.name.local == 'sup' && elementsNamed(e, 'a').isNotEmpty) return true;
  if (e.name.local == 'a' &&
      RegExp(r'^\[?\d{1,3}\]?$|^\*+$').hasMatch(e.innerText.trim()) &&
      (attr(e, 'href') ?? '').contains('#')) {
    return true;
  }
  return false;
}

/// Абзацы документа: каждый блочный элемент — абзац, его строки склеены пробелами.
/// [image] получает адрес картинки из `src` и возвращает её имя в книге
/// (или `null`, если картинку не берём).
_Blocks _blocks(XmlDocument doc, String? Function(String src) image) {
  final paragraphs = <String>[];
  final images = <ChapterImage>[];
  String? heading;
  var buffer = StringBuffer();
  var bufferIsHeading = false;

  void flush() {
    final p = cleanParagraph(buffer.toString());
    if (p.isNotEmpty && hasWords(p)) {
      paragraphs.add(p);
      if (bufferIsHeading && heading == null) heading = p;
    }
    buffer = StringBuffer();
    bufferIsHeading = false;
  }

  void walk(XmlNode node) {
    for (final child in node.children) {
      if (child is XmlText || child is XmlCDATA) {
        buffer.write(child.value);
      } else if (child is XmlElement) {
        final tag = child.name.local.toLowerCase();
        if (_skipTags.contains(tag) || _isFootnote(child)) continue;
        if (tag == 'br') {
          buffer.write(' ');
        } else if (tag == 'img' || tag == 'image') {
          // <img src>, а в обёртке <svg> — <image xlink:href>.
          final src = attr(child, 'src') ?? attr(child, 'href');
          final name = src == null || src.startsWith('data:') ? null : image(src);
          if (name != null) {
            flush();
            images.add(ChapterImage(position: paragraphs.length, name: name));
          }
        } else if (tag == 'svg') {
          for (final inner in elementsNamed(child, 'image')) {
            final src = attr(inner, 'href');
            final name = src == null ? null : image(src);
            if (name != null) {
              flush();
              images.add(ChapterImage(position: paragraphs.length, name: name));
            }
          }
        } else if (_blockTags.contains(tag)) {
          flush();
          final isHeading = RegExp(r'^h[1-6]$').hasMatch(tag);
          walk(child);
          if (isHeading) bufferIsHeading = true;
          flush();
        } else {
          walk(child);
        }
      }
    }
  }

  walk(firstNamed(doc, 'body') ?? doc);
  flush();
  return _Blocks(paragraphs, heading, images);
}

_Item? _coverItem(XmlDocument opf, Map<String, _Item> manifest) {
  _Item? item = manifest.values
      .where((i) => i.properties.split(' ').contains('cover-image'))
      .firstOrNull;
  if (item == null) {
    final meta = elementsNamed(opf, 'meta').where((m) => attr(m, 'name') == 'cover').firstOrNull;
    final id = meta == null ? null : attr(meta, 'content');
    item = id == null ? null : manifest[id];
  }
  item ??= manifest.entries
      .where(
        (e) =>
            e.value.mediaType.startsWith('image/') &&
            '${e.key} ${e.value.path}'.toLowerCase().contains('cover'),
      )
      .firstOrNull
      ?.value;
  return item != null && item.mediaType.startsWith('image/') ? item : null;
}

(Uint8List, String)? _cover(_Item? item, Map<String, ArchiveFile> files) {
  if (item == null) return null;
  final file = files[item.path];
  if (file == null) return null;
  return (Uint8List.fromList(file.content), _extension(item.mediaType, item.path));
}

String _extension(String mediaType, String path) {
  if (mediaType.contains('png')) return 'png';
  if (mediaType.contains('gif')) return 'gif';
  if (mediaType.contains('webp')) return 'webp';
  if (mediaType.contains('jpeg') || mediaType.contains('jpg')) return 'jpg';
  final dot = path.lastIndexOf('.');
  return dot < 0 ? 'jpg' : path.substring(dot + 1).toLowerCase();
}
