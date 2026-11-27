import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app.dart';
import 'package:lumen/screens/home_screen.dart';
import 'package:lumen/shell/tabs.dart';

void main() {
  testWidgets('остров переключает пять разделов', (tester) async {
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

    await tester.tap(find.bySemanticsLabel(AppTab.settings.label));
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
    expect(find.text('EPUB, FB2 или TXT'), findsOneWidget);
  });

  testWidgets('Ctrl+4 открывает «Голоса» (на Mac — ⌘4)', (tester) async {
    await tester.pumpWidget(const LumenApp());
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Голоса диктора и озвученные книги'), findsOneWidget);
  });

  test('приветствие и дата по-русски', () {
    final t = DateTime(2026, 11, 26, 20);
    expect(greeting(t), 'Добрый вечер');
    expect(russianDate(t), 'Четверг, 26 ноября');
    expect(greeting(DateTime(2026, 1, 1, 3)), 'Доброй ночи');
  });
}
