import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lumen/app.dart';
import 'package:lumen/library/book_cover.dart';
import 'package:lumen/library/library_scope.dart';
import 'package:lumen/shell/tabs.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_import/lumen_import.dart';
import 'package:lumen_storage/lumen_storage.dart';

void main() {
  testWidgets('добавленная книга видна в библиотеке, открывается с главами', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = MemoryBookStore();
    final book = parsePlainText(
      'Глава 1\n\nНочь была тиха.\n\nГлава 2\n\nНаступило утро.',
      title: 'Тихая ночь',
    ).toBook('b1', addedAt: DateTime(2026, 11, 27), sourceName: 'Тихая ночь.txt');
    await store.save(book);

    await tester.pumpWidget(LumenApp(store: store));
    await tester.tap(find.bySemanticsLabel(AppTab.library.label));
    await tester.pumpAndSettle();
    expect(find.text('Тихая ночь'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Тихая ночь'));
    await tester.pumpAndSettle();
    expect(find.text('Главы'), findsOneWidget);
    expect(find.text('Глава 1'), findsWidgets);
    expect(find.textContaining('TXT · 2 главы'), findsOneWidget);
    // Остров остаётся внизу и в карточке книги.
    expect(find.bySemanticsLabel(AppTab.home.label), findsOneWidget);

    await tester.tap(find.text('Глава 2').first);
    await tester.pumpAndSettle();
    expect(find.text('Наступило утро.'), findsOneWidget);
  });

  testWidgets('поиск по названию и автору', (tester) async {
    final store = MemoryBookStore();
    await store.save(const Book(id: 'a', title: 'Мёртвые души', author: 'Гоголь'));
    await store.save(const Book(id: 'b', title: 'Капитанская дочка', author: 'Пушкин'));
    await tester.pumpWidget(LumenApp(store: store));
    await tester.tap(find.bySemanticsLabel(AppTab.library.label));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'мертвые');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Мёртвые души, Гоголь'), findsOneWidget);
    expect(find.bySemanticsLabel('Капитанская дочка, Пушкин'), findsNothing);

    await tester.enterText(find.byType(TextField), 'пушкин');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Капитанская дочка, Пушкин'), findsOneWidget);
  });

  test('Library.addText сохраняет книгу с главами', () async {
    final library = Library(MemoryBookStore());
    final book = await library.addText('Глава 1\n\nРаз.\n\nГлава 2\n\nДва.', title: 'Счёт');
    final saved = await library.store.book(book.id);
    expect(saved!.title, 'Счёт');
    expect(saved.chapters.map((c) => c.id), ['${book.id}/0', '${book.id}/1']);
    expect(bookFormat(saved), 'Текст');
  });

  test('подписи по-русски', () {
    expect(chaptersLabel(1), '1 глава');
    expect(chaptersLabel(3), '3 главы');
    expect(chaptersLabel(14), '14 глав');
    expect(chaptersLabel(22), '22 главы');
    expect(listeningTime(900 * 90), '1 ч 30 мин');
    expect(listeningTime(100), '< 1 мин');
    expect(BookCover.colorsFor('abc'), BookCover.colorsFor('abc'));
  });
}
