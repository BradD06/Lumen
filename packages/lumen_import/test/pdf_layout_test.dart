import 'package:lumen_import/lumen_import.dart';
import 'package:test/test.dart';

/// Страница A5-ish: строки по 14 pt, левое поле 50, правое 370.
PdfPageLines page(List<(String, {double left, double right, double gap})> rows, {int? number}) {
  final lines = <PdfLine>[];
  var top = 60.0;
  for (final r in rows) {
    top += r.gap;
    lines.add(PdfLine(r.$1, left: r.left, right: r.right, top: top, bottom: top + 11));
    top += 14;
  }
  if (number != null) {
    lines.add(PdfLine('$number', left: 200, right: 210, top: 560, bottom: 571));
    lines.insert(0, const PdfLine('Капитанская дочка', left: 150, right: 260, top: 20, bottom: 31));
  }
  return PdfPageLines(width: 420, height: 595, lines: lines);
}

(String, {double left, double right, double gap}) row(
  String text, {
  double left = 50,
  double right = 370,
  double gap = 0,
}) => (text, left: left, right: right, gap: gap);

void main() {
  test('абзацы по отступу, переносы склеены, колонтитулы и номера убраны', () {
    final pages = [
      for (var n = 1; n <= 4; n++)
        page([
          row('Отец мой Андрей Петрович Гринёв в моло-', left: 62),
          row('дости своей служил при графе Минихе'),
          row('и вышел в отставку.', right: 160),
          row('Матушка была ещё мною брюхата, как', left: 62),
          row('уже я был записан'),
        ], number: n),
    ];
    final book = buildPdfBook(title: 'Дочка', pages: pages);
    final texts = book.chapters.single.paragraphTexts;
    expect(
      texts.first,
      'Отец мой Андрей Петрович Гринёв в молодости своей служил при графе Минихе и вышел в отставку.',
    );
    // Абзац, оборванный на странице, продолжается на следующей.
    expect(texts[1], 'Матушка была ещё мною брюхата, как уже я был записан');
    expect(texts.any((t) => t.contains('Капитанская дочка')), isFalse);
    expect(texts.any((t) => RegExp(r'^\d+$').hasMatch(t)), isFalse);
    expect(book.chapters.single.title, 'Дочка');
  });

  test('главы из оглавления PDF; один корень — берём его пункты', () {
    final pages = [
      for (var n = 0; n < 5; n++) page([row('Текст страницы ${n + 1}.')]),
    ];
    final book = buildPdfBook(
      title: 'Книга',
      pages: pages,
      outline: const [
        PdfOutlineEntry(
          'Книга',
          0,
          children: [PdfOutlineEntry('Глава первая', 1), PdfOutlineEntry('Глава вторая', 3)],
        ),
      ],
    );
    expect(book.chapters.map((c) => c.title), ['Начало', 'Глава первая', 'Глава вторая']);
    expect(book.chapters[1].paragraphTexts, ['Текст страницы 2.', 'Текст страницы 3.']);
  });

  test('без оглавления: главы по заголовкам, иначе по 20 страниц', () {
    final withHeadings = buildPdfBook(
      title: 'К',
      pages: [
        page([row('Глава 1'), row('Раз.', gap: 20), row('Ещё строка', left: 62), row('и ещё.')]),
        page([row('Глава 2'), row('Два.', gap: 20), row('Ещё строка', left: 62), row('и ещё.')]),
      ],
    );
    expect(withHeadings.chapters.map((c) => c.title), ['Глава 1', 'Глава 2']);

    final long = buildPdfBook(
      title: 'Длинная',
      pages: [
        for (var n = 0; n < 45; n++) page([row('Страница ${n + 1}.')]),
      ],
    );
    expect(long.chapters.map((c) => c.title), [
      'Страницы 1–20',
      'Страницы 21–40',
      'Страницы 41–45',
    ]);
  });

  test('скан без текста — понятная ошибка', () {
    expect(
      () => buildPdfBook(title: 'Скан', pages: [page([]), page([])]),
      throwsA(isA<ImportException>().having((e) => e.message, 'message', contains('скан'))),
    );
  });
}
