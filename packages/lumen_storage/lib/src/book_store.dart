import 'dart:async';

import 'package:lumen_core/lumen_core.dart';

abstract interface class BookStore {
  /// Все книги; новое значение после каждого изменения.
  Stream<List<Book>> watchBooks();
  Future<Book?> book(String id);
  Future<void> save(Book book);
  Future<void> delete(String id);
}

/// Книги в памяти: для тестов и пока нет базы.
final class MemoryBookStore implements BookStore {
  final _books = <String, Book>{};
  final _changes = StreamController<List<Book>>.broadcast();

  List<Book> get _all => List.unmodifiable(_books.values);

  @override
  Stream<List<Book>> watchBooks() async* {
    yield _all;
    yield* _changes.stream;
  }

  @override
  Future<Book?> book(String id) async => _books[id];

  @override
  Future<void> save(Book book) async {
    _books[book.id] = book;
    _changes.add(_all);
  }

  @override
  Future<void> delete(String id) async {
    if (_books.remove(id) != null) _changes.add(_all);
  }
}
