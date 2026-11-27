import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen_player/lumen_player.dart';
import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

/// Системный голос, который «договаривает» каждую фразу сразу.
final class FakeSpeech implements SystemSpeech {
  final said = <String>[];
  Completer<bool>? _current;

  /// Не договаривать, пока тест не скажет.
  var hold = false;

  @override
  Future<bool> speak(
    String text, {
    String? language,
    double speed = 1,
    void Function(int start, int end)? onWord,
  }) {
    said.add(text);
    final done = _current = Completer<bool>();
    if (!hold) scheduleMicrotask(() => finish());
    return done.future;
  }

  void finish() {
    final c = _current;
    if (c != null && !c.isCompleted) c.complete(true);
  }

  @override
  Future<void> stop() async {
    final c = _current;
    if (c != null && !c.isCompleted) c.complete(false);
  }
}

/// Плеер фраз сервера: «доигрывает» сразу.
final class FakePlayer implements PhrasePlayer {
  final played = <String>[];
  final starts = <Duration>[];
  final clock = Stopwatch()..start();
  final times = <Duration>[];
  Completer<bool>? _current;

  @override
  Duration position = Duration.zero;

  @override
  Future<bool> play(PhraseAudio audio, {Duration from = Duration.zero, double speed = 1}) {
    played.add(utf8.decode(audio.data));
    starts.add(from);
    times.add(clock.elapsed);
    final done = _current = Completer<bool>();
    scheduleMicrotask(() {
      if (!done.isCompleted) done.complete(true);
    });
    return done.future;
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> stop() async {
    final c = _current;
    if (c != null && !c.isCompleted) c.complete(false);
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Подождать, пока выполнится условие (звук с сервера идёт через файлы кеша).
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final chapter = NarrationText.fromParagraphs('книга/0', [
  'Первая фраза здесь. Вторая фраза тут.',
  'Третья фраза в новом абзаце.',
]);

Narrator narrator(FakeSpeech speech, [FakePlayer? player]) =>
    Narrator(player: player ?? FakePlayer(), speech: speech, serverCheck: const Duration(hours: 1));

void main() {
  test('системный голос читает предложения по порядку и сообщает о конце главы', () async {
    final speech = FakeSpeech();
    final n = narrator(speech);
    var finished = false;
    n.onFinished = () => finished = true;
    n.load(chapter);
    expect(n.state.engine, VoiceEngine.system);
    n.play();
    await settle();
    expect(speech.said, [
      'Первая фраза здесь.',
      'Вторая фраза тут.',
      'Третья фраза в новом абзаце.',
    ]);
    expect(finished, isTrue);
    expect(n.state.playing, isFalse);
    n.dispose();
  });

  test('пауза и «Слушать» продолжают с того же предложения', () async {
    final speech = FakeSpeech()..hold = true;
    final n = narrator(speech)..load(chapter);
    n.play();
    await settle();
    speech.finish();
    await settle();
    expect(speech.said.last, 'Вторая фраза тут.');
    n.pause();
    expect(n.state.playing, isFalse);
    n.play();
    await settle();
    expect(speech.said.last, 'Вторая фраза тут.');
    n.dispose();
  });

  test('следующая и предыдущая фраза', () async {
    final speech = FakeSpeech()..hold = true;
    final n = narrator(speech)..load(chapter);
    n.play();
    await settle();
    n.nextPhrase();
    await settle();
    expect(speech.said.last, 'Вторая фраза тут.');
    n.nextPhrase();
    await settle();
    expect(speech.said.last, 'Третья фраза в новом абзаце.');
    n.previousPhrase();
    await settle();
    expect(speech.said.last, 'Вторая фраза тут.');
    n.dispose();
  });

  test('глава начинается с сохранённого места', () async {
    final speech = FakeSpeech()..hold = true;
    final at = chapter.text.indexOf('Третья');
    final n = narrator(speech)..load(chapter, offset: at);
    expect(n.state.sentence?.start, at);
    n.play();
    await settle();
    expect(speech.said, ['Третья фраза в новом абзаце.']);
    n.dispose();
  });

  test('вперёд на 15 секунд уходит дальше по тексту', () async {
    final speech = FakeSpeech()..hold = true;
    final long = NarrationText.fromParagraphs('к/1', [
      for (var i = 0; i < 20; i++) 'Это довольно длинное предложение номер $i для перемотки.',
    ]);
    final n = narrator(speech)..load(long);
    n.play();
    await settle();
    n.skip(15);
    await settle();
    expect(n.state.offset, greaterThan(100));
    final there = n.state.offset;
    n.skip(-15);
    await settle();
    expect(n.state.offset, lessThan(there));
    n.dispose();
  });

  group('голос сервера', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('lumen_player_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    ServerVoice voice(MockClient client) => ServerVoice(
      server: VoiceServer(
        ServerLink.parse('https://voice.example/#key=k')!,
        client: client,
        isOnline: () async => true,
      ),
      cache: PhraseCache(dir),
      voice: 'a',
    );

    test('читает частями с сервера', () async {
      final asked = <String>[];
      final client = MockClient((request) async {
        final text = (jsonDecode(request.body) as Map)['text'] as String;
        asked.add(text);
        return http.Response.bytes(Uint8List.fromList(utf8.encode(text)), 200);
      });
      final speech = FakeSpeech();
      final player = FakePlayer();
      final n = narrator(speech, player)
        ..setServer(voice(client))
        ..load(chapter);
      expect(n.state.engine, VoiceEngine.server);
      n.play();
      await until(() => player.played.join(' ').contains('Третья'));
      expect(player.played.first, 'Первая фраза здесь.');
      expect(player.played.join(' '), contains('Третья фраза'));
      expect(speech.said, isEmpty);
      n.dispose();
    });

    test('между абзацами пауза длиннее, чем между предложениями', () async {
      final client = MockClient((request) async {
        final text = (jsonDecode(request.body) as Map)['text'] as String;
        return http.Response.bytes(Uint8List.fromList(utf8.encode(text)), 200);
      });
      final player = FakePlayer();
      final n =
          Narrator(
              player: player,
              speech: FakeSpeech(),
              serverCheck: const Duration(hours: 1),
              paragraphPause: const Duration(milliseconds: 400),
              sentencePause: const Duration(milliseconds: 50),
            )
            ..setServer(voice(client))
            ..load(chapter);
      n.play();
      await until(() => player.played.any((p) => p.contains('Третья')));
      expect(player.played, hasLength(3));
      final sentenceGap = player.times[1] - player.times[0];
      final paragraphGap = player.times[2] - player.times[1];
      expect(sentenceGap, greaterThanOrEqualTo(const Duration(milliseconds: 50)));
      expect(paragraphGap, greaterThanOrEqualTo(const Duration(milliseconds: 400)));
      n.dispose();
    });

    test('ключ не подошёл — дальше читает системный голос', () async {
      final client = MockClient((_) async => http.Response('{"error":"bad key"}', 401));
      final speech = FakeSpeech()..hold = true;
      final n = narrator(speech, FakePlayer())
        ..setServer(voice(client))
        ..load(chapter);
      n.play();
      await until(() => speech.said.isNotEmpty);
      expect(n.state.engine, VoiceEngine.system);
      expect(n.state.fallback?.kind, VoiceErrorKind.wrongKey);
      expect(speech.said, ['Первая фраза здесь.']);
      n.dispose();
    });
  });

  test('таймер сна в конце главы', () {
    var fired = 0;
    final timer = SleepTimer(onFire: () => fired++);
    expect(timer.chapterEnded(), isFalse);
    timer.startEndOfChapter();
    expect(timer.isOn, isTrue);
    expect(timer.chapterEnded(), isTrue);
    expect(fired, 1);
    expect(timer.isOn, isFalse);
  });

  test('таймер сна по времени', () async {
    var fired = 0;
    final timer = SleepTimer(onFire: () => fired++)..start(const Duration(milliseconds: 10));
    expect(timer.remaining, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(fired, 1);
    expect(timer.isOn, isFalse);
  });
}
