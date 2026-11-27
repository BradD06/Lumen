import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// Что получилось из файла: сведения, главы и обложка. Id ещё нет.
final class ImportedBook {
  const ImportedBook({
    required this.title,
    this.author,
    this.language = 'ru',
    required this.chapters,
    this.cover,
    this.coverExtension,
    this.images = const {},
  });

  final String title;
  final String? author;
  final String language;

  /// Главы без id: id появится в `toBook`.
  final List<Chapter> chapters;

  /// Картинка обложки из файла (JPEG, PNG...) и её расширение без точки.
  final Uint8List? cover;
  final String? coverExtension;

  /// Иллюстрации глав: имя файла (`img3.jpg`, как в `ChapterImage.name`) → байты.
  final Map<String, Uint8List> images;

  int get characterCount => chapters.fold(0, (sum, c) => sum + c.text.length);

  /// Книга для библиотеки: главы получают постоянные id `<bookId>/<номер>`.
  Book toBook(String id, {DateTime? addedAt, String? sourceName, String? coverPath}) => Book(
    id: id,
    title: title,
    author: author,
    language: language,
    addedAt: addedAt,
    sourceName: sourceName,
    coverPath: coverPath,
    chapters: [
      for (var i = 0; i < chapters.length; i++)
        chapters[i].copyWith(id: Chapter.makeId(id, i), index: i),
    ],
  );
}

/// Книгу не удалось прочитать. `message` — для человека, по-русски.
final class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => 'ImportException: $message';
}

/// Чистый текст абзаца: любые пробелы и переносы строк — один пробел,
/// мягкие переносы и невидимые символы убраны.
String cleanParagraph(String raw) => raw
    .replaceAll(RegExp('[\u00AD\u200B\u200C\u200D\u2060\uFEFF]'), '')
    .replaceAll(RegExp(r'[\s\u00A0\u2007\u202F]+'), ' ')
    .trim();

/// Есть ли в абзаце хоть одна буква или цифра (а не только `* * *` или пусто).
bool hasWords(String text) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text);

/// Делит очень длинную главу без заголовков на части примерно по [size] знаков,
/// всегда по границе абзаца.
List<Chapter> splitLong(String title, List<String> paragraphs, {int size = 25000}) {
  final total = paragraphs.fold(0, (sum, p) => sum + p.length);
  if (total <= size * 1.5) {
    return [Chapter.fromParagraphs(title: title, paragraphs: paragraphs)];
  }
  final parts = <Chapter>[];
  var current = <String>[];
  var length = 0;
  void flush() {
    if (current.isEmpty) return;
    parts.add(Chapter.fromParagraphs(title: 'Часть ${parts.length + 1}', paragraphs: current));
    current = [];
    length = 0;
  }

  for (final p in paragraphs) {
    current.add(p);
    length += p.length;
    if (length >= size) flush();
  }
  flush();
  return parts;
}
