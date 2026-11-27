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
  });

  final String id;
  final String title;
  final String? author;

  /// Код языка (ru, en, ...). Язык, которого голос не знает, читает системный голос.
  final String language;

  /// Голос диктора с сервера; `null` — голос по умолчанию.
  final String? narratorVoiceId;
  final List<Chapter> chapters;

  Book copyWith({
    String? title,
    String? author,
    String? narratorVoiceId,
    List<Chapter>? chapters,
  }) => Book(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    language: language,
    narratorVoiceId: narratorVoiceId ?? this.narratorVoiceId,
    chapters: chapters ?? this.chapters,
  );
}

final class Chapter {
  const Chapter({required this.title, required this.text, this.lines = const []});

  final String title;

  /// Весь текст главы. Места (`TextRange`) считаются от его начала.
  final String text;

  /// Строки главы: повествование и реплики. Пусто, пока книгу не разобрали.
  final List<Line> lines;
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
