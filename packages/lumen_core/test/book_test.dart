import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  test('реплика хранит говорящего и чувство, место в UTF-16', () {
    const text = '«Привет 👋», — сказала Аня.';
    final start = text.indexOf('Привет');
    final line = Line(
      range: TextRange(start, 'Привет 👋'.length),
      speaker: 'Аня',
      emotion: Emotion.joy,
    );
    expect(line.range.of(text), 'Привет 👋');
    expect(line.range.length, 9, reason: 'эмодзи — две кодовые единицы UTF-16');
    expect(line.isNarration, isFalse);
  });

  test('повествование — строка без говорящего', () {
    const line = Line(range: TextRange(0, 5));
    expect(line.isNarration, isTrue);
    expect(line.emotion, Emotion.neutral);
  });

  test('неизвестное чувство читается как нейтральное', () {
    expect(Emotion.parse('joy'), Emotion.joy);
    expect(Emotion.parse('ярость'), Emotion.neutral);
    expect(Emotion.parse(null), Emotion.neutral);
  });

  test('один диктор на книгу', () {
    const book = Book(id: '1', title: 'Капитанская дочка');
    expect(book.copyWith(narratorVoiceId: 'a').narratorVoiceId, 'a');
    expect(book.language, 'ru');
  });
}
