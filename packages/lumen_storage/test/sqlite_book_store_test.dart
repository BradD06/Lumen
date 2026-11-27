import 'dart:io';

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_storage/lumen_storage.dart';
import 'package:test/test.dart';

Book sample(String id) => Book(
  id: id,
  title: 'Капитанская дочка',
  author: 'Пушкин',
  addedAt: DateTime(2026, 11, 27),
  sourceName: 'pushkin.epub',
  chapters: [
    Chapter.fromParagraphs(
      id: '$id/0',
      title: 'I',
      paragraphs: ['Отец мой Андрей Петрович.', '«Привет 👋», — сказала Маша.'],
    ),
    Chapter.fromParagraphs(id: '$id/1', index: 1, title: 'II', paragraphs: ['Вожатый.']),
  ],
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lumen_store'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('книга переживает перезапуск: главы, абзацы, обложка', () async {
    var store = SqliteBookStore.open(dir.path);
    final cover = await store.saveCover('b1', [1, 2, 3], 'png');
    await store.save(sample('b1').copyWith(coverPath: cover));
    store.close();

    store = SqliteBookStore.open(dir.path);
    final list = await store.watchBooks().first;
    expect(list.single.title, 'Капитанская дочка');
    expect(list.single.chapters, isEmpty, reason: 'в списке без текста');
    expect(File(list.single.coverPath!).readAsBytesSync(), [1, 2, 3]);

    final book = (await store.book('b1'))!;
    expect(book.author, 'Пушкин');
    expect(book.sourceName, 'pushkin.epub');
    expect(book.chapters.map((c) => c.id), ['b1/0', 'b1/1']);
    expect(book.chapters.first.paragraphTexts.last, '«Привет 👋», — сказала Маша.');
    store.close();
  });

  test('сохранение без глав не стирает главы; удаление убирает всё', () async {
    final store = SqliteBookStore.inMemory(coverDirectory: dir.path);
    final cover = await store.saveCover('b1', [9], 'jpg');
    await store.save(sample('b1').copyWith(coverPath: cover));
    await store.save(const Book(id: 'b1', title: 'Новое название').copyWith(coverPath: cover));
    final book = (await store.book('b1'))!;
    expect(book.title, 'Новое название');
    expect(book.chapters, hasLength(2));

    await store.delete('b1');
    expect(await store.book('b1'), isNull);
    expect(File(cover!).existsSync(), isFalse);
    store.close();
  });

  test('иллюстрации: места в главе, файлы рядом с базой, удаляются с книгой', () async {
    var store = SqliteBookStore.open(dir.path);
    final base = sample('b3');
    final chapter = base.chapters.first.copyWith(
      images: const [ChapterImage(position: 1, name: 'img1.png')],
    );
    await store.saveImages('b3', {
      'img1.png': [7, 7, 7],
      '../evil.png': [1],
    });
    await store.save(base.copyWith(chapters: [chapter, base.chapters.last]));
    store.close();

    store = SqliteBookStore.open(dir.path);
    final image = (await store.book('b3'))!.chapters.first.images.single;
    expect(image.position, 1);
    expect(File(image.path!).readAsBytesSync(), [7, 7, 7]);
    expect(File('${dir.path}/evil.png').existsSync(), isFalse);

    await store.delete('b3');
    expect(File(image.path!).existsSync(), isFalse);
    store.close();
  });

  test('реплики хранят говорящего и чувство', () async {
    final store = SqliteBookStore.inMemory(coverDirectory: dir.path);
    final base = sample('b2');
    final chapter = base.chapters.first.copyWith(
      lines: [
        const Line(range: TextRange(0, 5)),
        const Line(range: TextRange(27, 9), speaker: 'Маша', emotion: Emotion.joy, confidence: .8),
      ],
    );
    await store.save(base.copyWith(chapters: [chapter]));
    final line = (await store.book('b2'))!.chapters.single.lines.last;
    expect(line.speaker, 'Маша');
    expect(line.emotion, Emotion.joy);
    expect(line.confidence, closeTo(.8, 1e-9));
    store.close();
  });

  test('список обновляется после изменений, новые книги сверху', () async {
    final store = SqliteBookStore.inMemory(coverDirectory: dir.path);
    final seen = <List<String>>[];
    final sub = store.watchBooks().listen((b) => seen.add([for (final x in b) x.id]));
    await pumpEventQueue();
    await store.save(sample('old').copyWith(addedAt: DateTime(2026, 1, 1)));
    await store.save(sample('new').copyWith(addedAt: DateTime(2026, 11, 1)));
    await pumpEventQueue();
    expect(seen.last, ['new', 'old']);
    await sub.cancel();
    store.close();
  });

  test('место чтения переживает перезапуск и пересохранение книги, уходит с книгой', () async {
    var store = SqliteBookStore.open(dir.path);
    await store.save(sample('b1'));
    expect((await store.progress('b1')).current, isNull);
    await store.saveProgress('b1', 0, 1);
    await store.saveProgress('b1', 1, 0.4, place: const ChapterPlace(item: 7, within: 0.25));
    store.close();

    store = SqliteBookStore.open(dir.path);
    var progress = await store.progress('b1');
    expect(progress.current, 1);
    expect(progress.of(0), 1);
    expect(progress.of(1), closeTo(0.4, 1e-9));
    expect(progress.places[1], const ChapterPlace(item: 7, within: 0.25));
    expect(progress.places[0], isNull);

    // Вернулись к первой главе — она снова текущая.
    await store.saveProgress('b1', 0, 0.2);
    await store.save(sample('b1'));
    progress = await store.progress('b1');
    expect(progress.current, 0);
    expect(progress.of(0), closeTo(0.2, 1e-9));

    await store.delete('b1');
    expect((await store.progress('b1')).current, isNull);
    // Для книги, которой нет, ничего не пишется.
    await store.saveProgress('b1', 0, 0.5);
    expect((await store.progress('b1')).chapters, isEmpty);
    store.close();
  });
}
