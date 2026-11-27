import 'dart:async';
import 'dart:io';

import 'package:lumen_core/lumen_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'book_store.dart';

/// Книги в SQLite на устройстве: `lumen.db` и папка `covers/` рядом.
///
/// Таблицы: `book`, `chapter`, `paragraph` (абзацы с полями «кто говорит» и «чувство»
/// для анализа, этап 9) и `line` (реплики). Миграции только добавляются в конец
/// `_migrations`, номер — `PRAGMA user_version`.
final class SqliteBookStore implements BookStore {
  SqliteBookStore._(this._db, this._coverDir);

  /// Открыть (или создать) библиотеку в папке [directory].
  factory SqliteBookStore.open(String directory) {
    Directory(directory).createSync(recursive: true);
    final coverDir = Directory('$directory${Platform.pathSeparator}covers')
      ..createSync(recursive: true);
    final db = sqlite3.open('$directory${Platform.pathSeparator}lumen.db');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA journal_mode = WAL');
    _migrate(db);
    return SqliteBookStore._(db, coverDir);
  }

  /// База в памяти для тестов; обложки — во временной папке.
  factory SqliteBookStore.inMemory({String? coverDirectory}) {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON');
    _migrate(db);
    final dir = Directory(coverDirectory ?? Directory.systemTemp.createTempSync('lumen').path);
    return SqliteBookStore._(db, dir);
  }

  final Database _db;
  final Directory _coverDir;
  final _changes = StreamController<List<Book>>.broadcast();

  static final _migrations = <void Function(Database)>[
    // v1: книги, главы, абзацы, реплики.
    (db) => db.execute('''
      CREATE TABLE book (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        language TEXT NOT NULL DEFAULT 'ru',
        narrator_voice_id TEXT,
        cover_file TEXT,
        source_name TEXT,
        added_at INTEGER NOT NULL
      );
      CREATE TABLE chapter (
        id TEXT PRIMARY KEY NOT NULL,
        book_id TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL,
        title TEXT NOT NULL,
        text TEXT NOT NULL
      );
      CREATE INDEX chapter_book ON chapter(book_id, idx);
      CREATE TABLE paragraph (
        chapter_id TEXT NOT NULL REFERENCES chapter(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL,
        start INTEGER NOT NULL,
        length INTEGER NOT NULL,
        speaker TEXT,
        emotion TEXT,
        PRIMARY KEY (chapter_id, idx)
      );
      CREATE TABLE line (
        chapter_id TEXT NOT NULL REFERENCES chapter(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL,
        start INTEGER NOT NULL,
        length INTEGER NOT NULL,
        speaker TEXT,
        emotion TEXT,
        confidence REAL,
        PRIMARY KEY (chapter_id, idx)
      );
    '''),
    // v2: иллюстрации глав; файлы в images/<id книги>/.
    (db) => db.execute('''
      CREATE TABLE chapter_image (
        chapter_id TEXT NOT NULL REFERENCES chapter(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL,
        position INTEGER NOT NULL,
        name TEXT NOT NULL,
        PRIMARY KEY (chapter_id, idx)
      );
    '''),
  ];

  static void _migrate(Database db) {
    final version = db.select('PRAGMA user_version').first.columnAt(0) as int;
    for (var v = version; v < _migrations.length; v++) {
      db.execute('BEGIN');
      try {
        _migrations[v](db);
        db.execute('PRAGMA user_version = ${v + 1}');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  List<Book> _all() => [
    for (final row in _db.select('SELECT * FROM book ORDER BY added_at DESC, title')) _bookOf(row),
  ];

  Book _bookOf(Row row, [List<Chapter> chapters = const []]) {
    final coverFile = row['cover_file'] as String?;
    return Book(
      id: row['id'] as String,
      title: row['title'] as String,
      author: row['author'] as String?,
      language: row['language'] as String,
      narratorVoiceId: row['narrator_voice_id'] as String?,
      coverPath: coverFile == null ? null : _coverPath(coverFile),
      sourceName: row['source_name'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
      chapters: chapters,
    );
  }

  String _coverPath(String file) => '${_coverDir.path}${Platform.pathSeparator}$file';

  /// Папка иллюстраций книги: рядом с папкой обложек.
  Directory _imageDir(String bookId) => Directory(
    '${_coverDir.parent.path}${Platform.pathSeparator}images${Platform.pathSeparator}$bookId',
  );

  @override
  Stream<List<Book>> watchBooks() async* {
    yield _all();
    yield* _changes.stream;
  }

  @override
  Future<Book?> book(String id) async {
    final rows = _db.select('SELECT * FROM book WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final chapters = <Chapter>[];
    for (final c in _db.select('SELECT * FROM chapter WHERE book_id = ? ORDER BY idx', [id])) {
      final chapterId = c['id'] as String;
      chapters.add(
        Chapter(
          id: chapterId,
          index: c['idx'] as int,
          title: c['title'] as String,
          text: c['text'] as String,
          paragraphs: [
            for (final p in _db.select(
              'SELECT start, length FROM paragraph WHERE chapter_id = ? ORDER BY idx',
              [chapterId],
            ))
              TextRange(p['start'] as int, p['length'] as int),
          ],
          lines: [
            for (final l in _db.select('SELECT * FROM line WHERE chapter_id = ? ORDER BY idx', [
              chapterId,
            ]))
              Line(
                range: TextRange(l['start'] as int, l['length'] as int),
                speaker: l['speaker'] as String?,
                emotion: Emotion.parse(l['emotion'] as String?),
                confidence: (l['confidence'] as num?)?.toDouble(),
              ),
          ],
          images: [
            for (final i in _db.select(
              'SELECT position, name FROM chapter_image WHERE chapter_id = ? ORDER BY idx',
              [chapterId],
            ))
              ChapterImage(
                position: i['position'] as int,
                name: i['name'] as String,
                path: '${_imageDir(id).path}${Platform.pathSeparator}${i['name']}',
              ),
          ],
        ),
      );
    }
    return _bookOf(rows.first, chapters);
  }

  /// Сохраняет сведения книги. Главы переписываются, только если они в `book`
  /// есть: книга из списка (без глав) свои главы не теряет.
  @override
  Future<void> save(Book book) async {
    final coverFile = book.coverPath?.split(RegExp(r'[/\\]')).last;
    _db.execute('BEGIN');
    try {
      _db.execute(
        '''INSERT INTO book (id, title, author, language, narrator_voice_id, cover_file,
             source_name, added_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(id) DO UPDATE SET title = excluded.title, author = excluded.author,
             language = excluded.language, narrator_voice_id = excluded.narrator_voice_id,
             cover_file = excluded.cover_file, source_name = excluded.source_name''',
        [
          book.id,
          book.title,
          book.author,
          book.language,
          book.narratorVoiceId,
          coverFile,
          book.sourceName,
          (book.addedAt ?? DateTime.now()).millisecondsSinceEpoch,
        ],
      );
      if (book.chapters.isNotEmpty) _writeChapters(book);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _changes.add(_all());
  }

  void _writeChapters(Book book) {
    _db.execute('DELETE FROM chapter WHERE book_id = ?', [book.id]);
    final chapter = _db.prepare(
      'INSERT INTO chapter (id, book_id, idx, title, text) VALUES (?, ?, ?, ?, ?)',
    );
    final paragraph = _db.prepare(
      'INSERT INTO paragraph (chapter_id, idx, start, length) VALUES (?, ?, ?, ?)',
    );
    final line = _db.prepare(
      'INSERT INTO line (chapter_id, idx, start, length, speaker, emotion, confidence) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
    );
    final image = _db.prepare(
      'INSERT INTO chapter_image (chapter_id, idx, position, name) VALUES (?, ?, ?, ?)',
    );
    try {
      for (var i = 0; i < book.chapters.length; i++) {
        final c = book.chapters[i];
        final id = c.id.isEmpty ? Chapter.makeId(book.id, i) : c.id;
        chapter.execute([id, book.id, i, c.title, c.text]);
        for (var p = 0; p < c.paragraphs.length; p++) {
          paragraph.execute([id, p, c.paragraphs[p].start, c.paragraphs[p].length]);
        }
        for (var l = 0; l < c.lines.length; l++) {
          final x = c.lines[l];
          line.execute([
            id,
            l,
            x.range.start,
            x.range.length,
            x.speaker,
            x.emotion.name,
            x.confidence,
          ]);
        }
        for (var k = 0; k < c.images.length; k++) {
          image.execute([id, k, c.images[k].position, c.images[k].name]);
        }
      }
    } finally {
      image.close();
      chapter.close();
      paragraph.close();
      line.close();
    }
  }

  @override
  Future<String?> saveCover(String bookId, List<int> bytes, String extension) async {
    final ext = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension) ? extension : 'jpg';
    final file = File(_coverPath('$bookId.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> saveImages(String bookId, Map<String, List<int>> images) async {
    if (images.isEmpty) return;
    final dir = _imageDir(bookId)..createSync(recursive: true);
    for (final e in images.entries) {
      // Имя приходит из разбора книги (img3.jpg), но из папки книги не выпускаем.
      if (!RegExp(r'^[\w.-]+$').hasMatch(e.key) || e.key.startsWith('.')) continue;
      await File('${dir.path}${Platform.pathSeparator}${e.key}').writeAsBytes(e.value, flush: true);
    }
  }

  @override
  Future<void> delete(String id) async {
    final rows = _db.select('SELECT cover_file FROM book WHERE id = ?', [id]);
    if (rows.isEmpty) return;
    _db.execute('DELETE FROM book WHERE id = ?', [id]);
    final cover = rows.first['cover_file'] as String?;
    if (cover != null) {
      final file = File(_coverPath(cover));
      if (file.existsSync()) file.deleteSync();
    }
    final images = _imageDir(id);
    if (images.existsSync()) images.deleteSync(recursive: true);
    _changes.add(_all());
  }

  void close() {
    _changes.close();
    _db.close();
  }
}
