import 'package:flutter/services.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:material_ui/material_ui.dart';

import '../library/book_cover.dart';
import '../library/library_scope.dart';
import '../library/widgets.dart';
import '../shell/app_shell.dart';
import '../shell/tabs.dart';
import '../theme/glass.dart';
import '../theme/graphite.dart';
import 'book_screen.dart';
import 'tab_page.dart';

/// Вкладка «Библиотека»: свой стек экранов (список → карточка книги → текст главы),
/// чтобы остров оставался внизу.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      onPopWithResult: (_) => _navigator.currentState?.maybePop(),
      child: Navigator(
        key: _navigator,
        // Фокус остаётся у окна, иначе ⌘1…⌘5 перестают работать.
        requestFocus: false,
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => const _LibraryList(),
          transitionDuration: Duration.zero,
        ),
      ),
    );
  }
}

class _LibraryList extends StatefulWidget {
  const _LibraryList();

  @override
  State<_LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends State<_LibraryList> {
  final _search = TextEditingController();
  Stream<List<Book>>? _books;
  Library? _library;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final library = LibraryScope.of(context);
    if (library != _library) {
      _library = library;
      _books = library.store.watchBooks();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Book>>(
      stream: _books,
      builder: (context, snapshot) {
        final books = snapshot.data;
        if (books == null) return const SizedBox.shrink();
        if (books.isEmpty) {
          return TabPage(
            title: 'Библиотека',
            children: [
              EmptyCard(
                iconPath: AppTab.library.iconPath,
                title: 'Книг пока нет',
                text: 'Здесь будут все ваши книги с цветными обложками, поиском по названию и автору.',
                action: 'Добавить книгу',
                onAction: () => TabSwitcher.of(context)(AppTab.add),
              ),
            ],
          );
        }
        return ListenableBuilder(
          listenable: _search,
          builder: (context, _) {
            final found = _filter(books, _search.text);
            return TabPage(
              title: 'Библиотека',
              children: [
                _SearchField(controller: _search),
                if (found.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Ничего не нашлось',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Graphite.textMuted),
                    ),
                  )
                else
                  _BookGrid(books: found),
              ],
            );
          },
        );
      },
    );
  }

  static List<Book> _filter(List<Book> books, String query) {
    final q = query.trim().toLowerCase().replaceAll('ё', 'е');
    if (q.isEmpty) return books;
    return [
      for (final b in books)
        if ('${b.title} ${b.author ?? ''}'.toLowerCase().replaceAll('ё', 'е').contains(q)) b,
    ];
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Glass(
    radius: 23,
    shadow: false,
    child: SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 16),
          const LineIcon(Icons24.search, size: 18, color: Graphite.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 15, color: Graphite.text),
              cursorColor: Graphite.text,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Название или автор',
                hintStyle: TextStyle(color: Graphite.textMuted),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Очистить',
              onPressed: controller.clear,
              icon: const LineIcon(Icons24.close, size: 16, color: Graphite.textMuted),
            ),
          const SizedBox(width: 6),
        ],
      ),
    ),
  );
}

class _BookGrid extends StatelessWidget {
  const _BookGrid({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Телефон — 3 колонки, планшет — 4–5, компьютер — 6 (макет «Графит»).
        final width = constraints.maxWidth;
        final columns = width >= 900 ? 6 : (width >= 640 ? 5 : (width >= 480 ? 4 : 3));
        return GridView.builder(
          shrinkWrap: true,
          // Без своего отступа: иначе сетка добавляет сверху высоту «чёлки» iPhone.
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 18,
            // Обложка 2:3 и две строки подписи.
            mainAxisExtent: (width - 12 * (columns - 1)) / columns * 1.5 + 62,
          ),
          itemCount: books.length,
          itemBuilder: (context, i) => BookTile(book: books[i]),
        );
      },
    );
  }
}

/// Книга в сетке: обложка, название, автор. Нажатие — карточка книги;
/// правая кнопка или долгое нажатие — меню книги.
class BookTile extends StatelessWidget {
  const BookTile({super.key, required this.book});

  final Book book;

  void _open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BookScreen(bookId: book.id, preview: book),
    ),
  );

  Future<void> _menu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      color: const Color(0xF2202028),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'open', child: Text('Открыть')),
        PopupMenuItem(value: 'remove', child: Text('Убрать из библиотеки')),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'open':
        _open(context);
      case 'remove':
        await removeBook(context, book);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${book.title}${book.author == null ? '' : ', ${book.author}'}',
      excludeSemantics: true,
      child: FocusRing(
        radius: 14,
        onActivate: () => _open(context),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(context),
          onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
          onLongPressStart: (d) {
            HapticFeedback.mediumImpact();
            _menu(context, d.globalPosition);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(book: book),
              const SizedBox(height: 6),
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600),
              ),
              if (book.author != null)
                Text(
                  book.author!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Graphite.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Спросить и убрать книгу из библиотеки. Вернёт `true`, если убрали.
Future<bool> removeBook(BuildContext context, Book book) async {
  final library = LibraryScope.of(context);
  final ok = await confirm(
    context,
    title: 'Убрать книгу?',
    text: '«${book.title}» пропадёт из библиотеки вместе с главами. Файл книги на диске останется.',
    action: 'Убрать',
  );
  if (!ok) return false;
  await library.store.delete(book.id);
  return true;
}
