import 'emotion.dart';
import 'text_span.dart';

/// Книга: один диктор (`narratorVoiceId`) на всю книгу.
final class Book {
  const Book({
    required this.id,
    required this.title,
    this.author,
    this.language = 'ru',
    this.narratorVoiceId,
    this.chapters = const [],
    this.coverPath,
    this.addedAt,
    this.sourceName,
  });

  final String id;
  final String title;
  final String? author;

  /// Код языка (ru, en, ...). Язык, которого голос не знает, читает системный голос.
  final String language;

  /// Голос диктора с сервера; `null` — голос по умолчанию.
  final String? narratorVoiceId;

  /// Главы по порядку. В списке библиотеки (`BookStore.watchBooks`) пусто:
  /// весь текст приходит только из `BookStore.book(id)`.
  final List<Chapter> chapters;

  /// Файл обложки на этом устройстве; `null` — нарисовать обложку из названия.
  final String? coverPath;

  /// Когда книгу добавили в библиотеку.
  final DateTime? addedAt;

  /// Имя файла, из которого добавили книгу (`Война и мир.epub`).
  final String? sourceName;

  Book copyWith({
    String? title,
    String? author,
    String? language,
    String? narratorVoiceId,
    List<Chapter>? chapters,
    String? coverPath,
    DateTime? addedAt,
    String? sourceName,
  }) => Book(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    language: language ?? this.language,
    narratorVoiceId: narratorVoiceId ?? this.narratorVoiceId,
    chapters: chapters ?? this.chapters,
    coverPath: coverPath ?? this.coverPath,
    addedAt: addedAt ?? this.addedAt,
    sourceName: sourceName ?? this.sourceName,
  );
}

/// Глава: чистый текст и его абзацы.
///
/// Для озвучки: `id` не меняется, пока книга в библиотеке; текст уже чистый
/// (без сносок, переносы строк внутри абзаца стали пробелами), абзацы разделены
/// пустой строкой `\n\n`, их места — `paragraphs`. Картинки (`images`) в текст
/// не входят: озвучка их не видит, экран текста ставит их между абзацами.
final class Chapter {
  const Chapter({
    this.id = '',
    this.index = 0,
    required this.title,
    required this.text,
    this.paragraphs = const [],
    this.lines = const [],
    this.images = const [],
  });

  /// Склеить главу из абзацев: текст через `\n\n` и места каждого абзаца.
  factory Chapter.fromParagraphs({
    String id = '',
    int index = 0,
    required String title,
    required List<String> paragraphs,
    List<ChapterImage> images = const [],
  }) {
    final buffer = StringBuffer();
    final ranges = <TextRange>[];
    // Пустые абзацы выпадают: места картинок сдвигаются вместе с ними.
    final positions = <int>[];
    for (final paragraph in paragraphs) {
      positions.add(ranges.length);
      if (paragraph.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n');
      ranges.add(TextRange(buffer.length, paragraph.length));
      buffer.write(paragraph);
    }
    positions.add(ranges.length);
    return Chapter(
      id: id,
      index: index,
      title: title,
      text: buffer.toString(),
      paragraphs: ranges,
      images: [
        for (final image in images)
          image.copyWith(position: positions[image.position.clamp(0, paragraphs.length)]),
      ],
    );
  }

  /// Постоянный id главы: `<id книги>/<номер>`.
  final String id;

  /// Номер главы в книге, с нуля.
  final int index;
  final String title;

  /// Весь текст главы. Места (`TextRange`) считаются от его начала.
  final String text;

  /// Абзацы главы: места в `text`.
  final List<TextRange> paragraphs;

  /// Строки главы: повествование и реплики. Пусто, пока книгу не разобрали.
  final List<Line> lines;

  /// Иллюстрации по порядку; `position` — перед каким абзацем стоит картинка.
  final List<ChapterImage> images;

  /// Тексты абзацев по порядку.
  List<String> get paragraphTexts => [for (final p in paragraphs) p.of(text)];

  static String makeId(String bookId, int index) => '$bookId/$index';

  Chapter copyWith({
    String? id,
    int? index,
    String? title,
    List<Line>? lines,
    List<ChapterImage>? images,
  }) => Chapter(
    id: id ?? this.id,
    index: index ?? this.index,
    title: title ?? this.title,
    text: text,
    paragraphs: paragraphs,
    lines: lines ?? this.lines,
    images: images ?? this.images,
  );
}

/// Иллюстрация внутри главы.
final class ChapterImage {
  const ChapterImage({required this.position, required this.name, this.path});

  /// Перед каким абзацем стоит картинка: 0 — до первого,
  /// `paragraphs.length` — после последнего.
  final int position;

  /// Имя файла картинки в книге (`img3.jpg`).
  final String name;

  /// Файл на этом устройстве; `null`, пока книга не сохранена.
  final String? path;

  ChapterImage copyWith({int? position, String? path}) =>
      ChapterImage(position: position ?? this.position, name: name, path: path ?? this.path);
}

/// Кусок текста, который читается одной интонацией: повествование или реплика.
final class Line {
  const Line({required this.range, this.speaker, this.emotion = Emotion.neutral, this.confidence});

  final TextRange range;

  /// Кто говорит: имя персонажа или `null` для повествования.
  /// Голос от этого не меняется, только интонация.
  final String? speaker;
  final Emotion emotion;

  /// Насколько анализ уверен в `speaker` (0…1); `null` — не анализировали.
  final double? confidence;

  bool get isNarration => speaker == null;
}
