import 'package:lumen_core/lumen_core.dart';

import 'imported_book.dart';
import 'text_decode.dart';

/// TXT: кодировку угадываем (UTF-8, UTF-16, Windows-1251), главы ищем
/// по заголовкам «Глава 1», «Часть вторая», «Chapter 3», римским цифрам.
ImportedBook parseTxt(List<int> bytes, {required String title}) =>
    parsePlainText(decodeText(bytes), title: title);

/// Текст, вставленный из буфера, или содержимое TXT-файла.
ImportedBook parsePlainText(String text, {String? title}) {
  final paragraphs = splitParagraphs(text);
  if (paragraphs.isEmpty) throw const ImportException('В тексте нет ни одного слова.');
  final bookTitle = (title != null && title.trim().isNotEmpty)
      ? title.trim()
      : _shorten(paragraphs.first, 60);
  return ImportedBook(
    title: bookTitle,
    language: guessLanguage(text),
    chapters: _chapters(paragraphs, bookTitle),
  );
}

/// Абзацы текста. Если между абзацами пустые строки — делим по ним, а переносы
/// внутри абзаца становятся пробелами. Если пустых строк почти нет, но есть
/// отступы — новый абзац с отступа. Иначе каждая строка — абзац.
List<String> splitParagraphs(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trimRight()
      .replaceFirst(RegExp(r'^(\s*\n)+'), '')
      .split('\n');
  final filled = lines.where((l) => l.trim().isNotEmpty).length;
  if (filled == 0) return const [];
  final blank = lines.length - filled;
  final indented = lines.where((l) => RegExp(r'^(\t| {2,}|\u00A0)\S').hasMatch(l)).length;

  final raw = <String>[];
  var current = StringBuffer();
  void flush() {
    final p = cleanParagraph(current.toString());
    if (p.isNotEmpty) raw.add(p);
    current = StringBuffer();
  }

  final byBlank = blank >= filled * 0.25;
  final byIndent = !byBlank && indented >= filled * 0.3 && indented < filled * 0.95;
  for (final line in lines) {
    if (line.trim().isEmpty) {
      flush();
    } else if (_isHeading(line.trim()) && (byBlank || byIndent)) {
      // Заголовок — всегда отдельный абзац, даже без пустой строки после него.
      flush();
      current.write(line);
      flush();
    } else if (byBlank) {
      current.write(' $line');
    } else if (byIndent) {
      if (RegExp(r'^(\t| {2,}|\u00A0)').hasMatch(line)) flush();
      current.write(' $line');
    } else {
      current.write(line);
      flush();
    }
  }
  flush();
  return raw;
}

final _headingWord = RegExp(
  r'^(глава|часть|книга|том|пролог|эпилог|предисловие|послесловие|вступление|заключение|'
  r'chapter|part|book|prologue|epilogue|preface|introduction)(\s|$|[.:\-—])',
  caseSensitive: false,
);
final _roman = RegExp(r'^[IVXLCDM]{1,7}\.?$');
final _number = RegExp(r'^\d{1,3}\.?$');

bool _isHeading(String p) {
  if (p.length > 80) return false;
  if (_roman.hasMatch(p) || _number.hasMatch(p)) return true;
  // С заглавной: строка «часть денег он отдал...» внутри абзаца — не заголовок.
  if (!_headingWord.hasMatch(p) || p[0] == p[0].toLowerCase()) return false;
  // «Глава 1», «Часть вторая. Буря», но не «Глава семьи встала и сказала: ...».
  return p.split(' ').length <= 8 && !p.endsWith(',');
}

/// Короткая строка без точки в конце сразу после «Глава 1» — её название.
bool _isSubtitle(String p) =>
    p.length <= 70 && !_isHeading(p) && !RegExp(r'[.,;:!?…»"]$').hasMatch(p) && hasWords(p);

List<Chapter> _chapters(List<String> paragraphs, String bookTitle) {
  final chapters = <Chapter>[];
  var title = '';
  var body = <String>[];

  void flush() {
    final hasText = body.any((p) => p != title && hasWords(p));
    if (!hasText) return;
    if (title.isEmpty) {
      chapters.addAll(
        splitLong(chapters.isEmpty ? 'Начало' : 'Глава ${chapters.length + 1}', body),
      );
    } else {
      chapters.add(Chapter.fromParagraphs(title: title, paragraphs: body));
    }
  }

  for (var i = 0; i < paragraphs.length; i++) {
    final p = paragraphs[i];
    if (_isHeading(p)) {
      flush();
      title = p.replaceAll(RegExp(r'[.:]$'), '');
      body = [p];
      if (i + 1 < paragraphs.length && _isSubtitle(paragraphs[i + 1])) {
        title = '$title. ${paragraphs[i + 1]}';
        body.add(paragraphs[++i]);
      }
    } else {
      body.add(p);
    }
  }
  flush();

  // Заголовков не нашлось: одна глава с названием книги (или части, если текст длинный).
  if (chapters.length == 1 && chapters.first.title == 'Начало') {
    return splitLong(bookTitle, chapters.first.paragraphTexts);
  }
  return chapters;
}

String _shorten(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1).trim()}…';

/// Язык по буквам: кириллица — `ru`, иначе `en`.
String guessLanguage(String text) {
  final sample = text.length > 5000 ? text.substring(0, 5000) : text;
  final cyrillic = RegExp('[а-яёА-ЯЁ]').allMatches(sample).length;
  final latin = RegExp('[a-zA-Z]').allMatches(sample).length;
  if (RegExp('[іїєґІЇЄҐ]').allMatches(sample).length > 5) return 'uk';
  return cyrillic >= latin ? 'ru' : 'en';
}
