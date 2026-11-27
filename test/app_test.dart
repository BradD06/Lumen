import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Key, Opacity;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app.dart';
import 'package:lumen/screens/home_screen.dart';
import 'package:lumen/shell/island.dart';
import 'package:lumen/shell/tabs.dart';

void main() {
  testWidgets('остров переключает разделы, профиль — кружок в углу', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LumenApp());
    for (final tab in AppTab.values) {
      expect(find.bySemanticsLabel(tab.label), findsOneWidget);
    }
    expect(find.text('Здесь будет «Слушаю сейчас»'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(AppTab.library.label));
    await tester.pumpAndSettle();
    expect(find.text('Книг пока нет'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(AppTab.catalog.label));
    await tester.pumpAndSettle();
    expect(find.text('Книги, готовые к прослушиванию'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(AppTab.profile.label));
    await tester.pumpAndSettle();
    expect(find.text('Профиль и настройки'), findsOneWidget);
    expect(find.text('Сервер озвучки'), findsOneWidget);
    // В интерфейсе нет слова «ПК», только «сервер».
    expect(find.textContaining('ПК'), findsNothing);
  });

  testWidgets('кнопка на главной открывает «Добавить книгу»', (tester) async {
    await tester.pumpWidget(const LumenApp());
    await tester.tap(find.text('Добавить книгу').first);
    await tester.pumpAndSettle();
    expect(find.text('Выберите файл книги'), findsOneWidget);
  });

  testWidgets('Ctrl+5 открывает «Голоса» (на Mac — ⌘5)', (tester) async {
    await tester.pumpWidget(const LumenApp());
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Голоса диктора и озвученные книги'), findsOneWidget);
  });

  testWidgets('кружок выбранного раздела плавно едет по острову', (tester) async {
    await tester.pumpWidget(const LumenApp());
    final bubble = find.byKey(const Key('island-bubble'));
    final island = find.byType(NavIsland);
    double bubbleX() => tester.getCenter(bubble).dx - tester.getTopLeft(island).dx;
    // Остров не сжат FittedBox: тестовое окно шире него.
    expect(bubbleX(), closeTo(IslandMetrics.centerOf(AppTab.home), 0.5));

    await tester.tap(find.bySemanticsLabel(AppTab.voices.label));
    await tester.pump();
    await tester.pump(IslandMetrics.move ~/ 2);
    final middle = bubbleX();
    expect(middle, greaterThan(IslandMetrics.centerOf(AppTab.home) + 10));
    expect(middle, lessThan(IslandMetrics.centerOf(AppTab.voices) - 10));

    await tester.pumpAndSettle();
    expect(bubbleX(), closeTo(IslandMetrics.centerOf(AppTab.voices), 0.5));
  });

  testWidgets('в профиле кружок прячется в остров и возвращается', (tester) async {
    await tester.pumpWidget(const LumenApp());
    double bubbleOpacity() => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byKey(const Key('island-bubble')),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;
    expect(bubbleOpacity(), 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Профиль и настройки'), findsOneWidget);
    expect(bubbleOpacity(), 0);

    await tester.tap(find.bySemanticsLabel(AppTab.catalog.label));
    await tester.pumpAndSettle();
    expect(bubbleOpacity(), 1);
    final x =
        tester.getCenter(find.byKey(const Key('island-bubble'))).dx -
        tester.getTopLeft(find.byType(NavIsland)).dx;
    expect(x, closeTo(IslandMetrics.centerOf(AppTab.catalog), 0.5));
  });

  testWidgets('порядок острова: Главная, Каталог, Добавить, Библиотека, Голоса', (tester) async {
    await tester.pumpWidget(const LumenApp());
    final order = ['Главная', 'Каталог', 'Добавить', 'Библиотека', 'Голоса'];
    expect(AppTab.island.map((t) => t.label), order);
    final xs = [for (final label in order) tester.getCenter(find.bySemanticsLabel(label)).dx];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]));
    }
  });

  test('приветствие и дата по-русски', () {
    final t = DateTime(2026, 11, 26, 20);
    expect(greeting(t), 'Добрый вечер');
    expect(russianDate(t), 'Четверг, 26 ноября');
    expect(greeting(DateTime(2026, 1, 1, 3)), 'Доброй ночи');
  });
}
