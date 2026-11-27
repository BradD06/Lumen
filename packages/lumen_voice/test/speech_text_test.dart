import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_voice/lumen_voice.dart';
import 'package:test/test.dart';

/// Часть текста главы по месту, как её подсветит плеер.
String slice(String chapter, SpeechPart part) => chapter.substring(part.start, part.end);

/// Абзац из одинаковых по длине предложений.
String paragraph(int count, {int from = 1}) =>
    [for (var i = from; i < from + count; i++) 'Это предложение номер $i в длинном абзаце.']
        .join(' ');

int dots(String s) => '.'.allMatches(s).length;

void main() {
  test('предложения помнят своё место в главе', () {
    const heading = 'Глава 4';
    const text = '\n  Аграрная революция была спорной. Одни говорят «да». Другие —\n нет! ';
    const chapter = heading + text;
    final parts = SpeechText.parts([
      const SpeechBlock(kind: SpeechBlockKind.heading, text: heading, start: 0),
      SpeechBlock(text: text, start: heading.length),
    ]);
    expect(parts.map((p) => p.spoken), [
      'Глава 4',
      'Аграрная революция была спорной.',
      'Одни говорят «да».',
      'Другие — нет!',
    ]);
    expect(parts.map((p) => p.isHeading), [true, false, false, false]);
    for (final part in parts) {
      expect(SpeechText.clean(slice(chapter, part)), part.spoken);
    }
  });

  test('места считаются в UTF-16, эмодзи — два знака', () {
    const text = '😀 Привет. Пока.';
    final parts = SpeechText.parts([const SpeechBlock(text: text, start: 10)]);
    expect(parts, hasLength(2));
    expect(parts[1].spoken, 'Пока.');
    expect(parts[1].start, 10 + '😀 Привет. '.length);
    expect(parts[1].length, 5);
  });

  test('короткие предложения склеиваются', () {
    final text = 'Раз. Два. Три. Длинно ${'длинно ' * 20}конец.';
    final parts = SpeechText.parts([SpeechBlock(text: text, start: 0)], groupLength: 40);
    expect(parts.first.spoken, 'Раз. Два. Три.');
    expect(parts, hasLength(2));
  });

  test('разгон: сначала одно предложение, дальше части растут', () {
    final text = paragraph(40);
    final parts = SpeechText.ramped([SpeechBlock(text: text, start: 0)], startingAt: 0);
    expect(parts.first.spoken, 'Это предложение номер 1 в длинном абзаце.');
    final lengths = parts.map((p) => p.spoken.length).toList();
    for (var i = 0; i + 1 < lengths.length; i++) {
      expect(lengths[i], lessThanOrEqualTo(lengths[i + 1]));
    }
    expect(lengths.every((l) => l <= SpeechText.paragraphLength), isTrue);
    expect(lengths.last, greaterThan(3 * lengths.first));
    // Ничего не потеряно и не повторено.
    expect(parts.map((p) => p.spoken).join(' '), text);
  });

  test('разгон начинается с места чтения и не захватывает два абзаца', () {
    final before = paragraph(3);
    final text = paragraph(20, from: 4);
    final blocks = [
      SpeechBlock(text: before, start: 0),
      SpeechBlock(text: text, start: before.length + 1),
    ];
    final place = blocks[1].start + text.length ~/ 2;
    final parts = SpeechText.ramped(blocks, startingAt: place);
    expect(parts[0].spoken, before);
    expect(parts[1].start, blocks[1].start);
    final index = SpeechText.indexOf(place, parts)!;
    expect(index, 2);
    expect(dots(parts[index].spoken), 1);
    expect(dots(parts[index + 1].spoken), 1);
    expect(parts.every((p) => p.end <= blocks[1].start || p.start >= blocks[1].start), isTrue);
  });

  test('подсветка идёт по предложению внутри части-абзаца', () {
    final blocks = [SpeechBlock(text: paragraph(6), start: 50)];
    final sentences = SpeechText.parts(blocks);
    final part = SpeechText.parts(blocks, groupLength: SpeechText.paragraphLength)[0];
    expect(sentences, hasLength(6));
    expect(part.start, sentences[0].start);
    expect(part.end, sentences[5].end);
    expect(SpeechText.sentenceAt(part.start, part, sentences), sentences[0].range);
    expect(SpeechText.sentenceAt(sentences[2].start + 5, part, sentences), sentences[2].range);
    // Пробел между предложениями относится к следующему.
    expect(SpeechText.sentenceAt(sentences[3].start - 1, part, sentences), sentences[3].range);
    expect(SpeechText.sentenceAt(sentences[2].start, sentences[2], sentences), sentences[2].range);
    expect(SpeechText.sentenceAt(part.start, part, const []), part.range);
  });

  test('разгон с конца — просто абзацы', () {
    final parts = SpeechText.ramped([
      SpeechBlock(text: paragraph(40), start: 0),
    ], startingAt: 1 << 30);
    expect(parts.length, lessThan(5));
    expect(parts.every((p) => p.spoken.length <= SpeechText.paragraphLength), isTrue);
  });

  test('код говорится один раз, номера страниц пропускаются', () {
    final parts = SpeechText.parts(const [
      SpeechBlock(text: 'Пример ниже.', start: 0),
      SpeechBlock(kind: SpeechBlockKind.code, text: 'let x = 1', start: 12),
      SpeechBlock(kind: SpeechBlockKind.code, text: 'print(x)', start: 22),
      SpeechBlock(text: '214', start: 30),
      SpeechBlock(text: '* * *', start: 33),
      SpeechBlock(text: 'Дальше.', start: 38),
    ]);
    expect(parts.map((p) => p.spoken), ['Пример ниже.', SpeechText.codeNotice, 'Дальше.']);
    expect(parts[1].start, 12);
    expect(parts[1].end, 30);
  });

  test('сноски и мягкие переносы не говорятся', () {
    final parts = SpeechText.parts([
      const SpeechBlock(text: 'Зем­леделие[12]   изменило   всё.', start: 0),
    ]);
    expect(parts.map((p) => p.spoken), ['Земледелие изменило всё.']);
  });

  test('длинное предложение режется по запятым', () {
    final piece = '${'слово ' * 40}и ещё, ';
    final sentence = '${piece * 3}конец.';
    final parts = SpeechText.parts([SpeechBlock(text: sentence, start: 0)]);
    expect(parts.length, greaterThan(1));
    expect(parts.every((p) => p.spoken.length <= SpeechText.maxPartLength), isTrue);
    expect(parts.take(parts.length - 1).every((p) => p.spoken.endsWith(',')), isTrue);
    for (var i = 0; i + 1 < parts.length; i++) {
      expect(parts[i].end, lessThanOrEqualTo(parts[i + 1].start));
    }
  });

  test('часть по месту в главе', () {
    final parts = SpeechText.parts([const SpeechBlock(text: 'Раз. Два. Три.', start: 100)]);
    expect(parts, hasLength(3));
    expect(SpeechText.indexOf(0, parts), 0);
    expect(SpeechText.indexOf(105, parts), 1);
    expect(SpeechText.indexOf(107, parts), 1);
    expect(SpeechText.indexOf(112, parts), 2);
    expect(SpeechText.indexOf(500, parts), isNull);
  });

  test('абзацы из мест в тексте и из строк', () {
    const text = 'Первый абзац.\n\nВторой абзац.';
    final byRanges = SpeechBlock.paragraphs(text, const [TextRange(0, 13), TextRange(15, 13)]);
    final byLines = SpeechBlock.paragraphs(text);
    for (final blocks in [byRanges, byLines]) {
      expect(blocks.map((b) => b.text), ['Первый абзац.', 'Второй абзац.']);
      expect(blocks.map((b) => b.start), [0, 15]);
    }
  });

  test('примерное время', () {
    final parts = SpeechText.parts([SpeechBlock(text: 'а' * 30, start: 0)]);
    expect(SpeechText.estimatedSeconds(parts), 2);
    expect(SpeechText.estimatedSeconds(parts, rate: 2), 1);
  });
}
