import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_import/lumen_import.dart';
import 'package:lumen_storage/lumen_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// Открыть библиотеку на устройстве: `<папка приложения>/library/lumen.db`.
/// Если база не открылась, книги живут в памяти до перезапуска.
Future<BookStore> openLibrary() async {
  try {
    final support = await getApplicationSupportDirectory();
    return SqliteBookStore.open('${support.path}${Platform.pathSeparator}library');
  } catch (error) {
    debugPrint('Библиотека не открылась, книги в памяти: $error');
    return MemoryBookStore();
  }
}

/// Даёт экранам библиотеку книг и добавление книг.
class LibraryScope extends StatefulWidget {
  const LibraryScope({super.key, this.store, required this.child});

  /// `null` — книги в памяти (тесты).
  final BookStore? store;
  final Widget child;

  static Library of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LibraryInherited>()!.library;

  @override
  State<LibraryScope> createState() => _LibraryScopeState();
}

class _LibraryScopeState extends State<LibraryScope> {
  late final Library _library = Library(widget.store ?? MemoryBookStore());

  @override
  Widget build(BuildContext context) => _LibraryInherited(library: _library, child: widget.child);
}

class _LibraryInherited extends InheritedWidget {
  const _LibraryInherited({required this.library, required super.child});

  final Library library;

  @override
  bool updateShouldNotify(_LibraryInherited oldWidget) => library != oldWidget.library;
}

/// Библиотека: хранилище и добавление книг. Разбор идёт в фоновом потоке,
/// чтобы большая книга не подвешивала окно.
class Library {
  Library(this.store);

  final BookStore store;

  /// Добавить книгу из файла. Бросает [ImportException] с понятным текстом.
  Future<Book> addFile(String fileName, Uint8List bytes) async {
    final imported = await _parse(() => importBook(fileName, bytes));
    return _save(imported, sourceName: fileName);
  }

  /// Добавить вставленный текст.
  Future<Book> addText(String text, {String? title}) async {
    final imported = await _parse(() => parsePlainText(text, title: title));
    return _save(imported);
  }

  Future<ImportedBook> _parse(ImportedBook Function() parse) async {
    try {
      return await Isolate.run(parse);
    } on ImportException {
      rethrow;
    } catch (error) {
      debugPrint('Книга не разобралась: $error');
      throw const ImportException('Книгу не удалось прочитать: файл повреждён или защищён.');
    }
  }

  Future<Book> _save(ImportedBook imported, {String? sourceName}) async {
    final id = newBookId();
    String? coverPath;
    if (imported.cover != null) {
      coverPath = await store.saveCover(id, imported.cover!, imported.coverExtension ?? 'jpg');
    }
    await store.saveImages(id, imported.images);
    final book = imported.toBook(
      id,
      addedAt: DateTime.now(),
      sourceName: sourceName,
      coverPath: coverPath,
    );
    await store.save(book);
    return book;
  }
}

final _random = Random();

/// Короткий id книги: время и случайная часть, без повторов между устройствами.
String newBookId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final tail = List.generate(6, (_) => _random.nextInt(36).toRadixString(36)).join();
  return '$time$tail';
}

/// Формат книги для подписи: EPUB, FB2, TXT или «Текст» для вставленного.
String bookFormat(Book book) {
  final name = book.sourceName?.toLowerCase();
  if (name == null) return 'Текст';
  if (name.endsWith('.fb2') || name.endsWith('.fb2.zip') || name.endsWith('.zip')) return 'FB2';
  final dot = name.lastIndexOf('.');
  return dot < 0 ? 'Файл' : name.substring(dot + 1).toUpperCase();
}

/// Примерная длина звука: диктор читает около 900 знаков в минуту.
String listeningTime(int characters) {
  final minutes = (characters / 900).round();
  if (minutes < 1) return '< 1 мин';
  if (minutes < 60) return '$minutes мин';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
}

/// «1 глава», «3 главы», «14 глав».
String chaptersLabel(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? 'глава'
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? 'главы' : 'глав');
  return '$n $word';
}
