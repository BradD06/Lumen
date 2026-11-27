import 'dart:async';
import 'dart:convert';

import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

final parts = SpeechText.parts([
  const SpeechBlock(text: 'Раз. Два. Три. Четыре. Пять. Шесть.', start: 0),
]);

PhraseAudio audio(String text) => PhraseAudio(data: utf8.encode(text));

String said(PhraseAudio? audio) => utf8.decode(audio!.data);

void main() {
  test('пока звучит фраза, следующие просятся заранее', () async {
    final asked = <String>[];
    final queue = PhraseQueue(
      load: (part) async {
        asked.add(part.spoken);
        return audio(part.spoken);
      },
      lookahead: 3,
    )..start(parts);
    final first = await queue.take(0);
    expect(said(first), 'Раз.');
    expect(asked, ['Раз.', 'Два.', 'Три.', 'Четыре.']);
    await queue.take(1);
    expect(asked.last, 'Пять.');
    expect(asked.where((s) => s == 'Два.'), hasLength(1));
  });

  test('опоздавший ответ старого перехода ничего не включает', () async {
    final gates = <String, Completer<PhraseAudio>>{};
    final queue = PhraseQueue(
      load: (part) => (gates[part.spoken] = Completer<PhraseAudio>()).future,
      lookahead: 0,
    )..start(parts);
    final old = queue.take(0);
    final jumped = queue.take(4);
    gates['Раз.']!.complete(audio('Раз.'));
    gates['Пять.']!.complete(audio('Пять.'));
    expect(await old, isNull);
    expect(said(await jumped), 'Пять.');
  });

  test('временный сбой: ждёт и пробует снова, потом сдаётся', () async {
    var calls = 0;
    final waits = <VoiceError>[];
    final queue = PhraseQueue(
      load: (part) async {
        calls++;
        if (calls < 3) throw const VoiceError(VoiceErrorKind.notResponding);
        return audio(part.spoken);
      },
      lookahead: 0,
      sleep: (_) async {},
      onWaiting: waits.add,
    )..start(parts);
    expect(await queue.take(0), isNotNull);
    expect(calls, 3);
    expect(waits, hasLength(2));

    final failing = PhraseQueue(
      load: (_) async => throw const VoiceError(VoiceErrorKind.noInternet),
      lookahead: 0,
      retryDelays: const [Duration.zero, Duration.zero],
      sleep: (_) async {},
    )..start(parts);
    await expectLater(
      failing.take(0),
      throwsA(isA<VoiceError>().having((e) => e.kind, 'kind', VoiceErrorKind.noInternet)),
    );
  });

  test('ключ не подошёл — сразу ошибка, без повторов', () async {
    var calls = 0;
    final queue = PhraseQueue(
      load: (_) async {
        calls++;
        throw const VoiceError(VoiceErrorKind.wrongKey);
      },
      lookahead: 0,
      sleep: (_) async {},
    )..start(parts);
    await expectLater(queue.take(0), throwsA(isA<VoiceError>()));
    expect(calls, 1);
  });

  test('сбой заранее просимой фразы не роняет приложение и пробуется снова', () async {
    var failNext = true;
    final queue = PhraseQueue(
      load: (part) async {
        if (part.spoken == 'Два.' && failNext) {
          failNext = false;
          throw const VoiceError(VoiceErrorKind.server, status: 500);
        }
        return audio(part.spoken);
      },
      lookahead: 1,
    )..start(parts);
    await queue.take(0);
    await Future<void>.delayed(Duration.zero);
    expect(said(await queue.take(1)), 'Два.');
  });

  test('смена голоса: приготовленное не годится', () async {
    var voice = 'a';
    final queue = PhraseQueue(load: (part) async => audio('$voice:${part.spoken}'), lookahead: 2)
      ..start(parts);
    await queue.take(0);
    voice = 'b';
    queue.invalidate();
    expect(said(await queue.take(1)), 'b:Два.');
  });

  test('загрузка показывает ожидание', () async {
    final states = <bool>[];
    final queue = PhraseQueue(
      load: (part) async => audio(part.spoken),
      lookahead: 0,
      onLoading: states.add,
    )..start(parts);
    await queue.take(0);
    expect(states, [true, false]);
  });
}
