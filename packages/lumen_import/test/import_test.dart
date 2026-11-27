import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:lumen_import/lumen_import.dart';
import 'package:test/test.dart';

/// Ненастоящий PNG нужного размера: подпись формата и нули.
final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(2000, 0)];

List<int> zip(Map<String, Object> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final value = e.value;
    final bytes = value is String ? utf8.encode(value) : value as List<int>;
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

List<int> epub({bool epub3 = true}) => zip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
      '</rootfiles></container>',
  'OEBPS/content.opf':
      '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>Капитанская дочка</dc:title><dc:creator>Александр Пушкин</dc:creator>'
      '<dc:language>ru-RU</dc:language><meta name="cover" content="cov"/></metadata>'
      '<manifest>'
      '${epub3 ? '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' : ''}'
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
      '<item id="cov" href="Images/cover.jpg" media-type="image/jpeg"/>'
      '<item id="part" href="Text/part1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c1" href="Text/ch1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c2" href="Text/ch%202.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="notes" href="Text/notes.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine toc="ncx"><itemref idref="part"/><itemref idref="c1"/>'
      '<itemref idref="c2"/><itemref idref="notes"/></spine></package>',
  'OEBPS/nav.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
      '<nav epub:type="toc"><ol><li><a href="Text/ch1.xhtml">I. Сержант гвардии</a></li>'
      '<li><a href="Text/ch%202.xhtml#top">II. Вожатый</a></li>'
      '<li><a href="Text/notes.xhtml">Примечания</a></li></ol></nav></body></html>',
  'OEBPS/toc.ncx':
      '<ncx><navMap><navPoint><navLabel><text>Глава из NCX</text></navLabel>'
      '<content src="Text/ch1.xhtml"/></navPoint></navMap></ncx>',
  'OEBPS/Images/cover.jpg': 'JPEGDATA',
  'OEBPS/Text/part1.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Часть первая</h1></body></html>',
  'OEBPS/Text/ch1.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>x</title></head><body>'
      '<h2>I. Сержант гвардии</h2>'
      '<p>Отец мой Андрей Петрович Гринёв<a epub:type="noteref" href="notes.xhtml#n1">1</a>\n в молодости своей служил&nbsp;при графе Минихе.</p>'
      '<p>Матушка была еще мною брюхата<sup><a href="#n2">2</a></sup>, как уже я был записан.</p>'
      '<aside epub:type="footnote" id="n2"><p>Сноска внутри главы.</p></aside>'
      '</body></html>',
  'OEBPS/Text/ch 2.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><body><div><p>Ветер выл.<br/>Метель.</p></div></body></html>',
  'OEBPS/Text/notes.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p id="n1">Примечание.</p></body></html>',
});

void main() {
  group('EPUB', () {
    test('сведения, главы по оглавлению, сноски убраны', () {
      final book = importBook('pushkin.epub', epub());
      expect(book.title, 'Капитанская дочка');
      expect(book.author, 'Александр Пушкин');
      expect(book.language, 'ru');
      expect(book.chapters.map((c) => c.title), ['I. Сержант гвардии', 'II. Вожатый']);
      final first = book.chapters.first;
      expect(first.paragraphTexts, [
        'I. Сержант гвардии',
        'Отец мой Андрей Петрович Гринёв в молодости своей служил при графе Минихе.',
        'Матушка была еще мною брюхата, как уже я был записан.',
      ]);
      expect(book.chapters[1].paragraphTexts, ['Ветер выл. Метель.']);
      expect(utf8.decode(book.cover!), 'JPEGDATA');
      expect(book.coverExtension, 'jpg');
    });

    test('EPUB 2: названия из NCX, без названия — «Глава N»', () {
      final book = importBook('x.epub', epub(epub3: false));
      expect(book.chapters.take(2).map((c) => c.title), ['Глава из NCX', 'Глава 2']);
    });

    test('не архив — понятная ошибка', () {
      expect(() => importBook('broken.epub', [1, 2, 3, 4, 5]), throwsA(isA<ImportException>()));
    });
  });

  test('EPUB: иллюстрации на своих местах, значки и обложка пропущены', () {
    final book = importBook(
      'pic.epub',
      zip({
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml':
            '<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>',
        'content.opf':
            '<package><metadata><title>Картинки</title></metadata><manifest>'
            '<item id="cov" href="img/cover.png" media-type="image/png" properties="cover-image"/>'
            '<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest><spine><itemref idref="c1"/></spine></package>',
        'img/cover.png': png,
        'img/map.png': png,
        'img/star.png': png.sublist(0, 100),
        'text/c1.xhtml':
            '<html><body><p>Первый абзац.</p><div><img src="../img/map.png" alt="Карта"/></div>'
            '<p>Второй абзац.</p><img src="../img/star.png"/><img src="../img/cover.png"/>'
            '<svg xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="../img/map.png"/></svg>'
            '</body></html>',
      }),
    );
    final chapter = book.chapters.single;
    expect(chapter.paragraphTexts, ['Первый абзац.', 'Второй абзац.']);
    expect(chapter.images.map((i) => (i.position, i.name)), [(1, 'img1.png'), (2, 'img1.png')]);
    expect(book.images.keys, ['img1.png']);
    expect(book.cover, isNotNull);
  });

  group('FB2', () {
    final picture = base64.encode(png);
    final fb2 =
        '<?xml version="1.0" encoding="windows-1251"?>'
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">'
        '<description><title-info><author><first-name>Николай</first-name><last-name>Гоголь</last-name></author>'
        '<book-title>Мёртвые души</book-title><lang>ru</lang>'
        '<coverpage><image l:href="#cover.png"/></coverpage></title-info></description>'
        '<body><title><p>Мёртвые души</p></title>'
        '<section><title><p>Том первый</p></title>'
        '<section><title><p>Глава первая</p></title>'
        '<p>В ворота гостиницы<a l:href="#n1" type="note">[1]</a> губернского города NN въехала</p>'
        '<image l:href="#pic.png"/>'
        '<empty-line/><poem><stanza><v>Строка стиха</v></stanza></poem></section>'
        '<section><title><p>Глава вторая</p></title><p>Уже более недели.</p></section>'
        '</section></body>'
        '<body name="notes"><section id="n1"><p>Сноска</p></section></body>'
        '<binary id="cover.png" content-type="image/png">UE5H</binary>'
        '<binary id="pic.png" content-type="image/png">$picture</binary>'
        '</FictionBook>';

    test('Windows-1251, автор, главы, обложка, сноски', () {
      final bytes = encodeCp1251(fb2);
      final book = importBook('gogol.fb2', bytes);
      expect(book.title, 'Мёртвые души');
      expect(book.author, 'Николай Гоголь');
      expect(book.chapters.map((c) => c.title), ['Глава первая', 'Глава вторая']);
      expect(book.chapters.first.paragraphTexts, [
        'Глава первая',
        'В ворота гостиницы губернского города NN въехала',
        'Строка стиха',
      ]);
      expect(utf8.decode(book.cover!), 'PNG');
      expect(book.coverExtension, 'png');
      expect(book.chapters.first.images.single.position, 2, reason: 'после второго абзаца');
      expect(book.images.values.single, png);
    });

    test('FB2 в ZIP', () {
      final book = importBook(
        'gogol.fb2.zip',
        zip({'gogol.fb2': fb2.replaceFirst('windows-1251', 'utf-8')}),
      );
      expect(book.chapters, hasLength(2));
    });
  });

  group('TXT', () {
    test('главы по заголовкам, абзацы по пустым строкам', () {
      const text =
          'Глава 1\nВстреча\n\nОна вошла\nв комнату.\n\nОн молчал.\n\n'
          'Глава 2\n\nНаутро шёл дождь.\n';
      final book = importBook('Дождь.txt', utf8.encode(text));
      expect(book.title, 'Дождь');
      expect(book.chapters.map((c) => c.title), ['Глава 1. Встреча', 'Глава 2']);
      expect(book.chapters.first.paragraphTexts, [
        'Глава 1',
        'Встреча',
        'Она вошла в комнату.',
        'Он молчал.',
      ]);
    });

    test('Windows-1251 и абзацы по отступу', () {
      const text = '    Первый абзац\nпродолжается здесь.\n    Второй абзац.\n    Третий.\n';
      final book = importBook('a.txt', encodeCp1251(text));
      expect(book.chapters.single.paragraphTexts, [
        'Первый абзац продолжается здесь.',
        'Второй абзац.',
        'Третий.',
      ]);
      expect(book.language, 'ru');
    });

    test('без заголовков длинный текст делится на части по абзацам', () {
      final text = List.filled(400, 'Абзац из ста знаков ' * 5).join('\n\n');
      final book = parsePlainText(text, title: 'Долгая');
      expect(book.chapters.length, greaterThan(1));
      expect(book.chapters.first.title, 'Часть 1');
      expect(book.chapters.every((c) => !c.text.startsWith(' ')), isTrue);
    });

    test('вставленный текст без названия берёт первую строку', () {
      final book = parsePlainText('Короткий рассказ о море\n\nВолны шумели.');
      expect(book.title, 'Короткий рассказ о море');
      expect(book.chapters.single.paragraphs, hasLength(2));
    });

    test('пустой текст — ошибка', () {
      expect(() => parsePlainText('  \n\n '), throwsA(isA<ImportException>()));
    });

    test('места абзацев указывают в текст главы', () {
      final book = parsePlainText('Раз два.\n\nТри 👋 четыре.\n\nПять.');
      final chapter = book.chapters.single;
      expect(chapter.text, 'Раз два.\n\nТри 👋 четыре.\n\nПять.');
      expect(chapter.paragraphs[1].of(chapter.text), 'Три 👋 четыре.');
    });

    test('id глав: <книга>/<номер>', () {
      final book = parsePlainText('Глава 1\n\nА.\n\nГлава 2\n\nБ.').toBook('b1');
      expect(book.chapters.map((c) => c.id), ['b1/0', 'b1/1']);
      expect(book.chapters.map((c) => c.index), [0, 1]);
    });
  });

  test('PDF и прочее — понятная ошибка', () {
    expect(
      () => importBook('a.pdf', [1]),
      throwsA(isA<ImportException>().having((e) => e.message, 'message', contains('PDF'))),
    );
    expect(() => importBook('a.doc', [1]), throwsA(isA<ImportException>()));
  });
}

/// Для тестов: строка в Windows-1251 (только ASCII и кириллица).
List<int> encodeCp1251(String s) => [
  for (final c in s.runes)
    if (c < 0x80)
      c
    else if (c >= 0x410 && c <= 0x44F)
      c - 0x410 + 0xC0
    else if (c == 0x401)
      0xA8
    else if (c == 0x451)
      0xB8
    else
      0x3F,
];
