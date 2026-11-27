import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

/// Громкость по 10 мс: куски тишины и речи.
List<double> levels(List<(double, bool)> pieces) => [
  for (final (seconds, loud) in pieces) ...List.filled((seconds * 100).round(), loud ? 0.5 : 0.0),
];

/// wav 16 бит моно: куски тишины и звука.
Uint8List wav(List<(double, bool)> pieces, {int rate = 8000}) {
  final samples = <int>[
    for (final (seconds, loud) in pieces)
      for (var i = 0; i < (seconds * rate).round(); i++) loud ? (i.isEven ? 16000 : -16000) : 0,
  ];
  final bytes = ByteData(44 + samples.length * 2);
  void text(int at, String s) {
    for (var i = 0; i < 4; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + samples.length * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  test('слова — буквы и цифры, мягкий перенос внутри слова', () {
    expect(SpeechTiming.wordRanges('Кто-то, 12 при­мер!'), const [
      TextRange(0, 3),
      TextRange(4, 2),
      TextRange(8, 2),
      TextRange(11, 7),
    ]);
  });

  test('звучит последнее начавшееся слово', () {
    const words = [
      SpeechWord(location: 0, length: 2, time: 0),
      SpeechWord(location: 3, length: 4, time: 0.4),
      SpeechWord(location: 8, length: 3, time: 1.1),
    ];
    expect(SpeechTiming.indexAt(0, words), 0);
    expect(SpeechTiming.indexAt(0.39, words), 0);
    expect(SpeechTiming.indexAt(0.4, words), 1);
    expect(SpeechTiming.indexAt(5, words), 2);
    expect(SpeechTiming.indexAt(1, const []), isNull);
  });

  test('без времени слова идут равномерно', () {
    final words = SpeechTiming.estimated('раз два', 2);
    expect(words.map((w) => w.time), [0, 2.0 * 4 / 7]);
  });

  test('сказанное слово находит своё место в главе', () {
    const raw = 'Слово[12] при­мер  тут';
    final part = SpeechPart(
      spoken: SpeechText.clean(raw),
      raw: raw,
      start: 100,
      length: raw.length,
    );
    expect(part.spoken, 'Слово пример тут');
    final places = SpeechTiming.places(part);
    expect(places.map((p) => p.chapter), const [
      TextRange(100, 5),
      TextRange(110, 7),
      TextRange(119, 3),
    ]);
    expect(SpeechTiming.chapterRange(const TextRange(6, 6), places), const TextRange(110, 7));
    expect(SpeechTiming.chapterRange(const TextRange(6, 10), places), const TextRange(110, 12));
    expect(SpeechTiming.chapterRange(const TextRange(5, 1), places), isNull);
  });

  group('время слов по громкости', () {
    test('тишина в начале не сдвигает слова, пауза ложится на запятую', () {
      final sound = levels([(0.2, false), (0.5, true), (0.3, false), (0.6, true), (0.2, false)]);
      final words = SpeechAlignment.wordsFromLevels('Раз, два три.', sound);
      expect(words.map((w) => w.location), [0, 5, 9]);
      expect(words[0].time, closeTo(0.2, 0.001));
      expect(words[1].time, closeTo(1.0, 0.001));
      expect(words[2].time, closeTo(1.3, 0.001));
    });

    test('без пауз слова идут по длине', () {
      final sound = levels([(0.1, false), (1.0, true), (0.3, false)]);
      final words = SpeechAlignment.wordsFromLevels('один два', sound);
      expect(words[0].time, closeTo(0.1, 0.001));
      expect(words[1].time, closeTo(0.1 + 1.0 * 5 / 8, 0.001));
    });

    test('тишина — нет слов', () {
      expect(SpeechAlignment.wordsFromLevels('тишина', [0, 0, 0]), isEmpty);
    });

    test('по самому wav', () {
      final audio = wav([(0.2, false), (0.5, true), (0.3, false), (0.6, true), (0.2, false)]);
      expect(AudioLevels.duration(audio), closeTo(1.8, 0.001));
      final words = SpeechAlignment.words('Раз, два три.', audio)!;
      expect(words[0].time, closeTo(0.2, 0.011));
      expect(words[1].time, closeTo(1.0, 0.011));
    });

    test('mp3 без декодера — времени нет, длительность по кадрам', () {
      // Два кадра MPEG-1 Layer III, 128 кбит/с, 44,1 кГц: по 417 байт, 1152 сэмпла.
      final frame = Uint8List(417)
        ..[0] = 0xFF
        ..[1] = 0xFB
        ..[2] = 0x90
        ..[3] = 0x00;
      final mp3 = Uint8List.fromList([...frame, ...frame]);
      expect(SpeechAlignment.words('слово', mp3), isNull);
      expect(AudioLevels.duration(mp3), closeTo(2 * 1152 / 44100, 1e-6));
    });
  });

  group('звучащая часть', () {
    const sentenceText = 'Первое предложение. Второе тут.';
    final sentences = SpeechText.parts([const SpeechBlock(text: sentenceText, start: 0)]);
    final part = SpeechText.parts([
      const SpeechBlock(text: sentenceText, start: 0),
    ], groupLength: 600).single;

    test('слово с опережением 0,12 с и предложение под ним', () {
      final words = SpeechTiming.wordRanges(part.spoken)
          .asMap()
          .entries
          .map(
            (e) => SpeechWord(location: e.value.start, length: e.value.length, time: e.key * 1.0),
          )
          .toList();
      final spoken = SpokenPart(part, words);
      expect(spoken.wordAt(0.5), const TextRange(0, 6));
      // За 0,12 с до «Второе» подсветка уже на нём.
      expect(spoken.wordAt(1.9), const TextRange(20, 6));
      expect(spoken.sentenceAt(1.9, sentences), sentences[1].range);
      expect(spoken.sentenceAt(0, sentences), sentences[0].range);
      expect(spoken.placeAt(2.5), 20);
    });

    test('без времени слов — равномерно по длительности', () {
      final spoken = SpokenPart(part, null, duration: 4);
      expect(spoken.words, hasLength(4));
      expect(spoken.wordAt(3.9), const TextRange(27, 3));
    });
  });
}
