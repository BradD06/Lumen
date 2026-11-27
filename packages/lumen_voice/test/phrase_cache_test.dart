import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('lumen_cache'));
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('второй раз фраза берётся из кеша', () async {
    var fetches = 0;
    final cache = PhraseCache(dir);
    Future<Uint8List> fetch() async {
      fetches++;
      return Uint8List.fromList([1, 2, 3]);
    }

    final first = await cache.audio('k', 'текст', fetch);
    final second = await PhraseCache(dir).audio('k', 'текст', fetch);
    expect(fetches, 1);
    expect(second.data, first.data);
    expect(await cache.has('k'), isTrue);
    expect(File('${dir.path}/k.mp3').existsSync(), isTrue);
  });

  test('одна загрузка на фразу, даже если её просят дважды', () async {
    var fetches = 0;
    final gate = Completer<Uint8List>();
    final cache = PhraseCache(dir);
    Future<Uint8List> fetch() {
      fetches++;
      return gate.future;
    }

    final a = cache.audio('k', 'т', fetch);
    final b = cache.audio('k', 'т', fetch);
    gate.complete(Uint8List.fromList([9]));
    expect((await a).data, [9]);
    expect((await b).data, [9]);
    expect(fetches, 1);
  });

  test('время слов хранится рядом со звуком', () async {
    final cache = PhraseCache(
      dir,
      align: (text, _) => const [SpeechWord(location: 0, length: 3, time: 0.5)],
    );
    await cache.audio('k', 'раз', () async => Uint8List.fromList([1]));
    final read = await PhraseCache(dir, align: (_, _) => null).read('k', 'раз');
    expect(read!.words, const [SpeechWord(location: 0, length: 3, time: 0.5)]);
  });

  test('«Очистить кеш» и размер', () async {
    final cache = PhraseCache(dir);
    await cache.write('a', PhraseAudio(data: Uint8List(100)));
    expect(await cache.size(), 100);
    await cache.clear();
    expect(await cache.size(), 0);
    expect(await cache.has('a'), isFalse);
  });

  test('старые фразы удаляются, когда кеш перерос предел', () async {
    final cache = PhraseCache(dir, limit: 250);
    for (final key in ['old', 'mid', 'new']) {
      await cache.write(key, PhraseAudio(data: Uint8List(100)));
    }
    File('${dir.path}/old.mp3').setLastModifiedSync(DateTime(2020));
    File('${dir.path}/mid.mp3').setLastModifiedSync(DateTime(2021));
    await cache.trim();
    expect(await cache.has('old'), isFalse);
    expect(await cache.has('new'), isTrue);
    expect(await cache.size(), lessThanOrEqualTo(250));
  });

  test('wav ложится с расширением wav', () async {
    final cache = PhraseCache(dir);
    final wav = Uint8List.fromList('RIFF\x00\x00\x00\x00WAVE'.codeUnits);
    await cache.write('w', PhraseAudio(data: wav));
    expect(File('${dir.path}/w.wav').existsSync(), isTrue);
  });
}
