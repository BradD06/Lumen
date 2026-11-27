import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

void main() {
  test('текст из абзацев: места, предложения, части для сервера', () {
    final text = NarrationText.fromParagraphs('book/0', ['Первый абзац. Ещё.', 'Второй абзац.']);
    expect(text.text, 'Первый абзац. Ещё.\n\nВторой абзац.');
    expect(text.sentences.map((s) => s.spoken), ['Первый абзац.', 'Ещё.', 'Второй абзац.']);
    expect(text.sentences.last.start, 20);
    expect(text.language, 'ru');
    final parts = text.serverParts(20);
    expect(parts.map((p) => p.spoken), ['Первый абзац. Ещё.', 'Второй абзац.']);
    expect(text.progressAt(text.text.length), 1);
  });

  test('место не пишется, пока не сдвинулось', () {
    final keeper = PlaceKeeper(id: 'book/0', openedAt: 120);
    expect(keeper.toSave(120), isNull);
    expect(keeper.toSave(150), 150);
    expect(keeper.toSave(150), isNull);
    keeper.followed(400);
    expect(keeper.toSave(400), isNull);
  });

  test('очередь сервера: кеш + сервер, голос в ключе кеша', () async {
    final dir = await Directory.systemTemp.createTemp('lumen_narration');
    // Очередь заранее подгружает следующие фразы и может ещё дописывать кеш, когда тест
    // закончился: удаляем папку, как только она перестанет меняться.
    addTearDown(() async {
      for (var attempt = 0; ; attempt++) {
        try {
          await dir.delete(recursive: true);
          return;
        } on FileSystemException {
          if (attempt >= 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });
    final spoken = <String>[];
    final server = VoiceServer(
      ServerLink.parse('https://voice.example/#key=k')!,
      client: MockClient((request) async {
        spoken.add(request.body);
        return http.Response.bytes([1], 200);
      }),
    );
    var voice = 'a';
    final text = NarrationText.fromParagraphs('b/0', ['Раз. Два.']);
    final queue = serverPhraseQueue(
      server: server,
      cache: PhraseCache(dir),
      voice: () => voice,
      language: text.language,
    )..start(text.serverParts(0));
    expect((await queue.take(0))!.data, Uint8List.fromList([1]));
    expect(spoken.first, contains('"voice":"a"'));
    expect(spoken.first, contains('"language":"ru"'));
    voice = 'b';
    queue.invalidate();
    await queue.take(0);
    expect(spoken.where((b) => b.contains('"voice":"b"')), isNotEmpty);
  });
}
