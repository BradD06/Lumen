import 'package:lumen_voice/src/sentences.dart';
import 'package:test/test.dart';

List<String> split(String text) => [
  for (final s in sentenceSpans(text)) text.substring(s.start, s.end).trim(),
];

void main() {
  test('обычные предложения', () {
    expect(split('Привет. Как дела? Отлично!'), ['Привет.', 'Как дела?', 'Отлично!']);
  });

  test('предложения идут подряд без зазоров', () {
    const text = '  Раз.  Два!   Три';
    final spans = sentenceSpans(text);
    expect(spans.first.start, 0);
    expect(spans.last.end, text.length);
    for (var i = 0; i + 1 < spans.length; i++) {
      expect(spans[i].end, spans[i + 1].start);
    }
  });

  test('многоточие, «?!» и закрывающие кавычки', () {
    expect(split('Ну и ну... Правда?! «Да.» Потом (тихо.) Ушёл.'), [
      'Ну и ну...',
      'Правда?!',
      '«Да.»',
      'Потом (тихо.)',
      'Ушёл.',
    ]);
  });

  test('после точки со строчной буквы — то же предложение', () {
    expect(split('Это т. е. пример. Далее.'), ['Это т. е. пример.', 'Далее.']);
    expect(split('Цена 3.14 рубля. Всё.'), ['Цена 3.14 рубля.', 'Всё.']);
  });

  test('реплика с тире: «— Да! — сказал он.» одно предложение', () {
    expect(split('— Да! — сказал он. — Куда? — Домой.'), [
      '— Да! — сказал он.',
      '— Куда?',
      '— Домой.',
    ]);
  });

  test('инициалы и сокращения', () {
    expect(split('Писал А. С. Пушкин. Читал проф. Иванов. Mr. Smith came.'), [
      'Писал А. С. Пушкин.',
      'Читал проф. Иванов.',
      'Mr. Smith came.',
    ]);
  });

  test('китайская точка', () {
    expect(split('你好。我很好。'), ['你好。', '我很好。']);
  });

  test('пустой текст — одно пустое предложение', () {
    expect(sentenceSpans(''), [(start: 0, end: 0)]);
    expect(split('без точки'), ['без точки']);
  });
}
