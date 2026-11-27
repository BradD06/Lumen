import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lumen/app.dart';
import 'package:lumen/reader/reading_panel.dart';
import 'package:lumen/shell/island.dart';
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
    testWidgets('$name: «Назад» не прячется под кружком профиля', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openChapter(tester, 'Глава 2');

      final profile = _rect(tester, find.byType(ProfileButton));
      final back = _rect(tester, find.byTooltip('Назад').last);
      expect(profile.overlaps(back), isFalse);
      // На одной высоте с профилем.
      expect(back.center.dy, closeTo(profile.center.dy, 1));
    });
  }

  testWidgets('прогресс над островом, кнопки листают главы', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openChapter(tester, 'Глава 2');

    final panel = find.byType(ReadingPanel);
    expect(find.text('Глава 2 из 3'), findsOneWidget);
    expect(find.text('0 %'), findsOneWidget);
    // Панель выше острова и его кружка.
    expect(_rect(tester, panel).bottom, lessThan(_rect(tester, find.byType(NavIsland)).top));

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

  test('сдвиг строки от профиля: узкая колонка — сдвиг, широкая — нет', () {
    expect(ClearOfProfile.indent(350, 760, 20), ProfileButton.clearance - 20);
    expect(ClearOfProfile.indent(1240, 760, 20), 0);
  });
}
