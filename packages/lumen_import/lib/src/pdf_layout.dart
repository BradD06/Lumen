import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'imported_book.dart';
import 'txt_parser.dart' show guessLanguage, chaptersByHeadings;

/// Строка текста на странице PDF. Координаты сверху вниз, в пунктах страницы.
final class PdfLine {
  const PdfLine(
    this.text, {
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;

  double get height => bottom - top;
}

/// Страница PDF: размер и строки сверху вниз.
final class PdfPageLines {
  const PdfPageLines({required this.width, required this.height, required this.lines});

  final double width;
  final double height;
  final List<PdfLine> lines;
}

/// Пункт оглавления PDF: название и страница (с нуля).
final class PdfOutlineEntry {
  const PdfOutlineEntry(this.title, this.page, {this.children = const []});

  final String title;
  final int page;
  final List<PdfOutlineEntry> children;
}

/// Сколько страниц в одной «главе», если в PDF нет ни оглавления, ни заголовков.
const pdfPagesPerPart = 20;

/// Книга из страниц PDF. Сам PDF читает приложение (PDFium), здесь — только
/// текст: колонтитулы и номера страниц убираем, переносы слов склеиваем, строки
/// собираем в абзацы по отступам и промежуткам, главы берём из оглавления PDF,
/// иначе из заголовков «Глава 1», иначе по [pdfPagesPerPart] страниц.
ImportedBook buildPdfBook({
  required String title,
  String? author,
  required List<PdfPageLines> pages,
  List<PdfOutlineEntry> outline = const [],
  Uint8List? cover,
  String? coverExtension,
}) {
  final repeated = _runningLines(pages);
  // Абзацы каждой страницы; последний абзац может продолжаться на следующей.
  final pageParagraphs = <List<_Paragraph>>[for (final page in pages) _paragraphs(page, repeated)];
  if (pageParagraphs.every((p) => p.isEmpty)) {
    throw const ImportException(
      'В этом PDF нет текста: похоже, это скан страниц. Распознавать текст на картинках Lumen пока не умеет.',
    );
  }

  // Книга с красной строкой: абзац без отступа вверху страницы — продолжение
  // прошлого, даже если строка до разрыва кончилась точкой.
  final all = [for (final p in pageParagraphs) ...p];
  final indentStyle = all.where((p) => p.indented).length >= all.length * 0.4;

  /// Абзацы со страницы [from] до [to] (не включая), склеивая абзацы на стыке страниц.
  List<String> range(int from, int to) {
    final out = <String>[];
    var open = false;
    for (var i = from; i < to && i < pageParagraphs.length; i++) {
      for (final (k, p) in pageParagraphs[i].indexed) {
        if (k == 0 && (open || indentStyle) && !p.startsNew && out.isNotEmpty) {
          out[out.length - 1] = _join(out.last, p.text);
        } else {
          out.add(p.text);
        }
      }
      if (pageParagraphs[i].isNotEmpty) open = !_endsSentence(out.last);
    }
    return out;
  }

  final chapters = <Chapter>[];
  final entries = _chapterEntries(outline, pages.length);
  if (entries.isNotEmpty) {
    if (entries.first.page > 0) {
      final before = range(0, entries.first.page);
      if (before.any(hasWords)) {
        chapters.add(Chapter.fromParagraphs(title: 'Начало', paragraphs: before));
      }
    }
    for (final (k, e) in entries.indexed) {
      final end = k + 1 < entries.length ? entries[k + 1].page : pages.length;
      final paragraphs = range(e.page, end <= e.page ? e.page + 1 : end);
      if (!paragraphs.any(hasWords)) continue;
      chapters.add(Chapter.fromParagraphs(title: e.title, paragraphs: paragraphs));
    }
  }
  if (chapters.isEmpty) {
    final all = range(0, pages.length);
    final byHeadings = chaptersByHeadings(all);
    if (byHeadings.length >= 2) {
      chapters.addAll(byHeadings);
    } else {
      for (var from = 0; from < pages.length; from += pdfPagesPerPart) {
        final to = (from + pdfPagesPerPart).clamp(0, pages.length);
        final paragraphs = range(from, to);
        if (!paragraphs.any(hasWords)) continue;
        final name = pages.length <= pdfPagesPerPart
            ? title
            : (to - from == 1 ? 'Страница ${from + 1}' : 'Страницы ${from + 1}–$to');
        chapters.add(Chapter.fromParagraphs(title: name, paragraphs: paragraphs));
      }
    }
  }

  final sample = chapters.take(3).map((c) => c.text).join(' ');
  return ImportedBook(
    title: title,
    author: author,
    language: guessLanguage(sample),
    chapters: chapters,
    cover: cover,
    coverExtension: coverExtension,
  );
}

/// Главы из оглавления: верхний уровень, а если он один — его подпункты.
List<PdfOutlineEntry> _chapterEntries(List<PdfOutlineEntry> outline, int pageCount) {
  var level = outline;
  while (level.length == 1 && level.single.children.isNotEmpty) {
    level = level.single.children;
  }
  final valid = [
    for (final e in level)
      if (e.page >= 0 && e.page < pageCount && e.title.trim().isNotEmpty)
        PdfOutlineEntry(cleanParagraph(e.title), e.page),
  ]..sort((a, b) => a.page.compareTo(b.page));
  return valid.length >= 2 ? valid : const [];
}

final class _Paragraph {
  _Paragraph(this.text, {required this.startsNew, this.indented = false});
  String text;

  /// Первая строка абзаца с красной строки.
  final bool indented;

  /// Начинается ли абзац явно заново (с отступа или после промежутка),
  /// а не продолжает текст с прошлой страницы.
  final bool startsNew;
}

final _pageNumber = RegExp(
  r'^[\s\-–—]*(стр\.?\s*)?\d{1,4}([\s/]+\d{1,4})?[\s\-–—]*$',
  caseSensitive: false,
);

/// Колонтитулы: строки у верхнего или нижнего края, которые повторяются
/// (без учёта цифр) на многих страницах.
Set<String> _runningLines(List<PdfPageLines> pages) {
  if (pages.length < 4) return const {};
  final counts = <String, int>{};
  for (final page in pages) {
    final edge = {
      for (final line in page.lines)
        if (line.top < page.height * 0.1 || line.bottom > page.height * 0.9) _key(line.text),
    };
    for (final k in edge) {
      counts[k] = (counts[k] ?? 0) + 1;
    }
  }
  return {
    for (final e in counts.entries)
      if (e.key.isNotEmpty && e.value >= pages.length * 0.4) e.key,
  };
}

String _key(String text) =>
    text.replaceAll(RegExp(r'\d+'), '#').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

List<_Paragraph> _paragraphs(PdfPageLines page, Set<String> repeated) {
  final lines = [
    for (final l in page.lines)
      if (l.text.trim().isNotEmpty &&
          !((l.top < page.height * 0.1 || l.bottom > page.height * 0.9) &&
              (_pageNumber.hasMatch(l.text) || repeated.contains(_key(l.text)))))
        l,
  ];
  if (lines.isEmpty) return [];

  final heights = _median([for (final l in lines) l.height]);
  final gaps = <double>[
    for (var i = 1; i < lines.length; i++)
      if (lines[i].top > lines[i - 1].top) lines[i].top - lines[i - 1].top,
  ];
  final lineStep = gaps.isEmpty ? heights * 1.2 : _median(gaps);
  final textLeft = _median([for (final l in lines) l.left]);
  final textRight = _median([for (final l in lines) l.right]);
  final indent = (page.width * 0.012).clamp(4.0, 40.0);

  final out = <_Paragraph>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final text = cleanParagraph(line.text);
    if (i == 0) {
      final indented = line.left > textLeft + indent && line.left - textLeft < page.width * 0.3;
      out.add(_Paragraph(text, startsNew: indented, indented: indented));
      continue;
    }
    final prev = lines[i - 1];
    final gap = line.top - prev.top;
    final bigGap = gap > lineStep * 1.45 || gap < 0;
    final indented = line.left > textLeft + indent && line.left - textLeft < page.width * 0.3;
    final prevShort = prev.right < textRight - page.width * 0.08 && _endsSentence(prev.text.trim());
    // Сильно другой размер шрифта — заголовок или подпись.
    final otherSize = heights > 0 && ((line.height - prev.height).abs() > heights * 0.35);
    if (bigGap || indented || prevShort || otherSize) {
      out.add(_Paragraph(text, startsNew: true, indented: indented));
    } else {
      out.last.text = _join(out.last.text, text);
    }
  }
  return [
    for (final p in out)
      if (hasWords(p.text)) p,
  ];
}

/// Склеить строки: «перено-» + «сы» → «переносы».
String _join(String a, String b) {
  if (a.isEmpty) return b;
  final hyphen = RegExp(r'[\p{L}][-\u00AD\u2010]$', unicode: true);
  if (hyphen.hasMatch(a) && RegExp(r'^\p{Ll}', unicode: true).hasMatch(b)) {
    return '${a.substring(0, a.length - 1)}$b';
  }
  return '$a $b';
}

bool _endsSentence(String s) => RegExp(r'[.!?…:»"”)]$').hasMatch(s);
