import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app.dart';
import 'package:lumen/narration/narration_controller.dart';
import 'package:lumen/shell/mini_player.dart';
import 'package:lumen/shell/tabs.dart';
import 'package:lumen/theme/graphite.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_import/lumen_import.dart';
import 'package:lumen_storage/lumen_storage.dart';
import 'package:material_ui/material_ui.dart' hide TextRange;

Future<void> _openChapter(WidgetTester tester) async {
  final store = MemoryBookStore();
  final text = [
    for (var c = 1; c <= 2; c++) ...[
      'Глава $c',
      for (var p = 0; p < 30; p++) 'Абзац $p главы $c. Ночь была тиха, и город спал.',
    ],
  ].join('\n\n');
  await store.save(parsePlainText(text, title: 'Тихая ночь').toBook('b1'));
  await tester.pumpWidget(LumenApp(store: store));
  await tester.tap(find.bySemanticsLabel(AppTab.library.label));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Тихая ночь'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Глава 1').first);
  await tester.pumpAndSettle();
}

/// Есть ли в тексте подсветка голоса (янтарь).
bool _highlighted(WidgetTester tester) {
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    var found = false;
    text.text.visitChildren((span) {
      final color = span.style?.backgroundColor;
      if (color == Graphite.amber || color == Graphite.amberSoft) found = true;
      return !found;
    });
    if (found) return true;
  }
  return false;
}

void main() {
  testWidgets('«Слушать» подсвечивает предложение, после выхода из книги — мини-плеер', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openChapter(tester);
    expect(_highlighted(tester), isFalse);

    await tester.tap(find.byTooltip('Слушать  Пробел'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_highlighted(tester), isTrue);
    // Кнопки перемотки работают, когда глава играет.
    await tester.tap(find.byTooltip('Следующая фраза'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Пауза  Пробел'), findsOneWidget);

    // Выходим к списку книг: книга играет дальше, над островом мини-плеер.
    await tester.tap(find.byTooltip('Назад').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад').last);
    await tester.pumpAndSettle();
    expect(find.byType(MiniPlayer).hitTestable(), findsOneWidget);
    expect(find.byTooltip('Пауза'), findsOneWidget);
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pump();
    expect(find.byTooltip('Слушать'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pump();
    expect(find.text('Абзац 0 главы 1. Ночь была тиха, и город спал.'), findsNothing);
    expect(find.byTooltip('Слушать'), findsNothing);
  });

  testWidgets('«Голоса»: не ссылка — понятная ошибка', (tester) async {
    await tester.pumpWidget(const LumenApp());
    await tester.tap(find.bySemanticsLabel(AppTab.voices.label));
    await tester.pumpAndSettle();
    expect(find.text('Сервер голоса'), findsOneWidget);
    expect(find.text('Не подключён'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'просто текст');
    await tester.tap(find.text('Подключить'));
    await tester.pumpAndSettle();
    expect(find.text('Нет адреса сервера'), findsOneWidget);
    expect(find.text('Системный голос'), findsOneWidget);
  });

  test('место экрана текста и место голоса переводятся друг в друга', () {
    final chapter = Chapter.fromParagraphs(
      title: 'Глава',
      paragraphs: ['Первый абзац текста.', 'Второй абзац, подлиннее первого.', 'Третий.'],
      images: [const ChapterImage(position: 1, name: 'a.png')],
    );
    // Пункты экрана: абзац 0, картинка, абзац 1, абзац 2.
    final second = chapter.paragraphs[1];
    final offset = second.start + 7;
    final place = placeOfOffset(chapter, offset)!;
    expect(place.item, 2);
    expect(offsetOfPlace(chapter, place), offset);
    // Место на картинке — голос начинает со следующего абзаца.
    expect(offsetOfPlace(chapter, const ChapterPlace(item: 1, within: .5)), second.start);
    expect(offsetOfPlace(chapter, null), 0);
  });
}
