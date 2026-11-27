import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lumen/app.dart';
import 'package:lumen/library/book_cover.dart';
import 'package:lumen/reader/narration_controls.dart';
import 'package:lumen/reader/reading_panel.dart';
import 'package:lumen/shell/island.dart';
import 'package:lumen/theme/fading_glass.dart';
import 'package:lumen/shell/profile_button.dart';
import 'package:lumen/shell/tabs.dart';
import 'package:lumen_import/lumen_import.dart';
import 'package:lumen_storage/lumen_storage.dart';

Future<void> _openChapter(WidgetTester tester, String chapter) async {
  final store = MemoryBookStore();
  final text = [
    for (var c = 1; c <= 3; c++) ...[
      'Глава $c',
      for (var p = 0; p < 40; p++) 'Абзац $p главы $c. Ночь была тиха, и город спал.',
    ],
  ].join('\n\n');
  await store.save(parsePlainText(text, title: 'Тихая ночь').toBook('b1'));
  await tester.pumpWidget(LumenApp(store: store));
  await tester.tap(find.bySemanticsLabel(AppTab.library.label));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Тихая ночь'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(chapter).first);
  await tester.pumpAndSettle();
}

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  for (final (name, size) in [('телефон', Size(390, 844)), ('окно', Size(1280, 800))]) {
    testWidgets('$name: в книге профиля нет, «Назад» на его месте', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openChapter(tester, 'Глава 2');

      Finder profile() => find.byTooltip('Профиль  Ctrl+,');
      expect(profile().hitTestable(), findsNothing);
      expect(find.byType(NavIsland).hitTestable(), findsNothing);
      final back = _rect(tester, find.byTooltip('Назад').last);
      // На месте кружка профиля (на телефоне) или левее колонки текста нет ничего.
      expect(back.top, closeTo(_rect(tester, find.byType(ProfileButton)).top, 1));

      // Обратно к списку книг — профиль снова виден.
      await tester.tap(find.byTooltip('Назад').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Назад').last);
      await tester.pumpAndSettle();
      expect(profile().hitTestable(), findsOneWidget);
      expect(find.byType(NavIsland).hitTestable(), findsOneWidget);
    });
  }

  testWidgets(
    'во весь экран «Назад» и заголовок по началу текста, в узком окне — на месте профиля',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openChapter(tester, 'Глава 2');

      final back = tester.getRect(find.byTooltip('Назад').last);
      final text = tester.getRect(find.textContaining('Абзац 0 главы 2.'));
      expect(back.left, closeTo(text.left, 1));

      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      final narrowBack = tester.getRect(find.byTooltip('Назад').last);
      expect(narrowBack.left, ProfileButton.left);
    },
  );

  testWidgets('карточка книги во весь экран: «Назад» по краю обложки', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryBookStore();
    await store.save(parsePlainText('Глава 1\n\nРаз.', title: 'Тихая ночь').toBook('b1'));
    await tester.pumpWidget(LumenApp(store: store));
    await tester.tap(find.bySemanticsLabel(AppTab.library.label));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Тихая ночь'));
    await tester.pumpAndSettle();

    final back = tester.getRect(find.byTooltip('Назад').last);
    final cover = tester.getRect(find.byType(BookCover).last);
    expect(back.left, closeTo(cover.left, 1));
    // В списке глав острова тоже нет.
    expect(find.byType(NavIsland).hitTestable(), findsNothing);
  });

  for (final (name, size) in [('телефон', Size(390, 844)), ('окно', Size(1440, 900))]) {
    testWidgets('$name: шапка главы закреплена сверху, название по центру', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openChapter(tester, 'Глава 2');

      Rect back() => tester.getRect(find.byTooltip('Назад').last);
      final before = back();
      final title = tester.getRect(find.text('Глава 2').last);
      expect(title.center.dx, closeTo(size.width / 2, 1));

      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(back(), before);
      expect(tester.getRect(find.text('Глава 2').last), title);
    });
  }

  testWidgets('в списке глав видно, где остановился и сколько прочитано', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openChapter(tester, 'Глава 2');

    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    final percent = tester.widget<ReadingPanel>(find.byType(ReadingPanel)).trailing!;
    expect(percent, isNot('0 %'));

    await tester.tap(find.byTooltip('Назад').last);
    await tester.pumpAndSettle();
    expect(find.text('Вы остановились здесь'), findsOneWidget);
    final row = find.ancestor(
      of: find.text('Вы остановились здесь'),
      matching: find.byType(InkWell),
    );
    expect(find.descendant(of: row, matching: find.text('Глава 2')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('%')), findsOneWidget);
    expect(find.textContaining('Прочитано'), findsOneWidget);

    // Глава открывается на том же месте.
    await tester.tap(find.text('Глава 2').first);
    await tester.pumpAndSettle();
    final reopened = tester.widget<ReadingPanel>(find.byType(ReadingPanel)).trailing!;
    final a = int.parse(percent.split(' ').first);
    final b = int.parse(reopened.split(' ').first);
    expect((a - b).abs(), lessThanOrEqualTo(5));
  });

  testWidgets('прогресс над островом, кнопки листают главы', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openChapter(tester, 'Глава 2');

    final panel = find.byType(ReadingPanel);
    expect(find.text('Глава 2 из 3'), findsOneWidget);
    expect(find.text('0 %'), findsOneWidget);
    // Остров спрятан, плеер — полоса во всю ширину у низа окна.
    expect(find.byType(NavIsland).hitTestable(), findsNothing);
    final bar = _rect(tester, panel);
    expect((bar.left, bar.right, bar.bottom), (0, 390, 844));
    // Над кнопками — стеклянная кромка, через неё виден (размытый) текст.
    expect(find.byType(FadingGlass), findsNWidgets(2));

    // Прокрутка двигает прогресс.
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('0 %'), findsNothing);

    await tester.tap(find.byTooltip('Следующая глава'));
    await tester.pumpAndSettle();
    expect(find.text('Глава 3 из 3'), findsOneWidget);
    expect(find.text('0 %'), findsOneWidget);
    expect(find.textContaining('главы 3.'), findsWidgets);

    // На последней главе «Следующая» погашена.
    await tester.tap(find.byTooltip('Следующая глава'));
    await tester.pumpAndSettle();
    expect(find.text('Глава 3 из 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Предыдущая глава'));
    await tester.tap(find.byTooltip('Предыдущая глава'));
    await tester.pumpAndSettle();
    expect(find.text('Глава 1 из 3'), findsOneWidget);
  });

  testWidgets('нажатие на полосу переносит по главе', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openChapter(tester, 'Глава 1');

    final bar = find.byType(ReadingProgressBar);
    final r = _rect(tester, bar);
    await tester.tapAt(Offset(r.left + r.width / 2, r.center.dy));
    await tester.pumpAndSettle();
    final label = tester.widget<ReadingPanel>(find.byType(ReadingPanel)).trailing!;
    // Длина списка уточняется по мере прокрутки: около середины.
    expect(int.parse(label.split(' ').first), inInclusiveRange(40, 60));
  });

  testWidgets('блок озвучки: пауза, скорость, музыка, главы', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openChapter(tester, 'Глава 1');

    expect(find.byType(NarrationControls), findsOneWidget);
    for (final label in [
      'Назад на 15 секунд',
      'Предыдущая фраза',
      'Следующая фраза',
      'Вперёд на 15 секунд',
      'Скорость',
      'Таймер сна',
      'Голос',
      'Главы',
      'Вид текста',
    ]) {
      expect(find.byTooltip(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.byTooltip('Слушать  Пробел'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Пауза  Пробел'), findsOneWidget);

    await tester.tap(find.text('1,0×'));
    await tester.pumpAndSettle();
    // Пункт меню: текст внутри галочки, нажатие попадает в сам пункт.
    await tester.tap(find.text('1,5×').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('1,5×'), findsOneWidget);

    await tester.tap(find.byTooltip('Музыка на фоне'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Музыка на фоне: играет'), findsOneWidget);

    await tester.tap(find.byTooltip('Главы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Глава 3').last);
    await tester.pumpAndSettle();
    expect(find.text('Глава 3 из 3'), findsOneWidget);
  });

  testWidgets('окно: плеер по центру панели, остальные кнопки слева и справа', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openChapter(tester, 'Глава 1');

    final panel = tester.getRect(find.byType(ReadingPanel));
    final play = tester.getRect(find.byTooltip('Слушать  Пробел'));
    expect(play.center.dx, closeTo(panel.center.dx, 1));
    final back15 = tester.getRect(find.byTooltip('Назад на 15 секунд'));
    final forward15 = tester.getRect(find.byTooltip('Вперёд на 15 секунд'));
    for (final label in ['Скорость', 'Таймер сна', 'Голос']) {
      expect(tester.getRect(find.byTooltip(label)).right, lessThan(back15.left), reason: label);
    }
    for (final label in ['Музыка на фоне', 'Главы', 'Вид текста']) {
      expect(
        tester.getRect(find.byTooltip(label)).left,
        greaterThan(forward15.right),
        reason: label,
      );
    }
    // Все в одном ряду.
    expect(tester.getRect(find.byTooltip('Скорость')).center.dy, closeTo(play.center.dy, 1));
  });

  test('подписи скорости как в макете', () {
    expect(NarrationView.speedLabel(1), '1,0×');
    expect(NarrationView.speedLabel(0.75), '0,75×');
    expect(NarrationView.speedLabel(1.5), '1,5×');
  });
}
