import 'dart:async';

import 'package:lumen_core/lumen_core.dart';

abstract interface class BookStore {
  /// Все книги без глав, новые сверху; новое значение после каждого изменения.
  Stream<List<Book>> watchBooks();

  /// Книга целиком, с главами и абзацами.
  Future<Book?> book(String id);

  /// Сохранить книгу. Главы переписываются, только если они в `book` есть.
  Future<void> save(Book book);

  /// Сохранить картинку обложки; вернёт путь для `Book.coverPath`.
  Future<String?> saveCover(String bookId, List<int> bytes, String extension);

  /// Сохранить иллюстрации книги (имя файла → байты). Пути к ним появятся
  /// в `ChapterImage.path` книги из `book(id)`.
  Future<void> saveImages(String bookId, Map<String, List<int>> images);

  /// Убрать книгу из библиотеки вместе с главами и обложкой.
  Future<void> delete(String id);

  /// Сколько прочитано в книге и где читатель остановился.
  Future<ReadingProgress> progress(String bookId);

  /// Запомнить место: глава [chapter] прочитана на [fraction], она теперь текущая;
  /// [place] — точное место, с которого глава откроется в следующий раз.
  Future<void> saveProgress(String bookId, int chapter, double fraction, {ChapterPlace? place});
}

/// Книги в памяти: для тестов и пока нет базы.
final class MemoryBookStore implements BookStore {
  final _books = <String, Book>{};
  final _changes = StreamController<List<Book>>.broadcast();
  final _progress = <String, ReadingProgress>{};

  List<Book> get _all => List.unmodifiable(
    _books.values.map(
      (b) => Book(
        id: b.id,
        title: b.title,
        author: b.author,
        language: b.language,
        narratorVoiceId: b.narratorVoiceId,
        coverPath: b.coverPath,
        addedAt: b.addedAt,
        sourceName: b.sourceName,
      ),
    ),
  );

  @override
  Stream<List<Book>> watchBooks() async* {
    yield _all;
    yield* _changes.stream;
  }

  @override
  Future<Book?> book(String id) async => _books[id];

  @override
  Future<void> save(Book book) async {
    final old = _books[book.id];
    _books[book.id] = book.chapters.isEmpty && old != null
        ? book.copyWith(chapters: old.chapters)
        : book;
    _changes.add(_all);
  }

  @override
  Future<String?> saveCover(String bookId, List<int> bytes, String extension) async => null;

  @override
  Future<void> saveImages(String bookId, Map<String, List<int>> images) async {}

  @override
  Future<void> delete(String id) async {
    _progress.remove(id);
    if (_books.remove(id) != null) _changes.add(_all);
  }

  @override
  Future<ReadingProgress> progress(String bookId) async =>
      _progress[bookId] ?? ReadingProgress.empty;

  @override
  Future<void> saveProgress(
    String bookId,
    int chapter,
    double fraction, {
    ChapterPlace? place,
  }) async {
    if (!_books.containsKey(bookId)) return;
    _progress[bookId] = (_progress[bookId] ?? ReadingProgress.empty).withChapter(
      chapter,
      fraction,
      place: place,
    );
  }
}
