import 'package:flutter/services.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:material_ui/material_ui.dart';

import '../library/book_cover.dart';
import '../library/library_scope.dart';
import '../library/widgets.dart';
import '../reader/reading_panel.dart';
import '../shell/app_shell.dart';
import '../shell/profile_button.dart';
import '../theme/glass.dart';
import '../theme/graphite.dart';
import 'library_screen.dart' show removeBook;
import 'tab_page.dart';

/// Верх экрана: кнопки стоят на одной высоте с кружком профиля
/// (на Mac под полосой с кнопками окна).
double _top(BuildContext context) =>
    MediaQuery.paddingOf(context).top + TabPage.windowBar + ProfileButton.top;

/// Карточка книги: обложка, сведения и главы.
class BookScreen extends StatefulWidget {
  const BookScreen({super.key, required this.bookId, this.preview});

  final String bookId;

  /// Книга из списка (без глав): показать сразу, пока грузится целиком.
  final Book? preview;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  Future<Book?>? _book;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _book ??= LibraryScope.of(context).store.book(widget.bookId);
  }

  Future<void> _more(Book book) async {
    if (await removeBook(context, book) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: FutureBuilder<Book?>(
        future: _book,
        builder: (context, snapshot) {
          final book = snapshot.data ?? widget.preview;
          if (book == null) return const SizedBox.shrink();
          final loaded = snapshot.data != null;
          final characters = book.chapters.fold(0, (sum, c) => sum + c.text.length);
          final facts = [
            bookFormat(book),
            if (loaded) chaptersLabel(book.chapters.length),
            if (loaded) '≈ ${listeningTime(characters)}',
          ].join(' · ');
          return ListView(
            padding: EdgeInsets.fromLTRB(20, _top(context), 20, 140),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 18,
                    children: [
                      ClearOfProfile(
                        maxWidth: 1100,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GlassIconButton(
                              icon: Icons24.back,
                              label: 'Назад',
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                            GlassIconButton(
                              icon: Icons24.trash,
                              label: 'Убрать из библиотеки',
                              onPressed: () => _more(book),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: 16,
                        children: [
                          SizedBox(
                            width: 120,
                            child: BookCover(book: book, radius: 16, titleSize: 13),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 6,
                              children: [
                                Text(
                                  book.title,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (book.author != null)
                                  Text(
                                    book.author!,
                                    style: const TextStyle(fontSize: 14, color: Graphite.textMuted),
                                  ),
                                Text(
                                  facts,
                                  style: const TextStyle(fontSize: 12, color: Graphite.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (loaded) ...[
                        const Text(
                          'Главы',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        Column(
                          children: [
                            for (final chapter in book.chapters)
                              _ChapterRow(book: book, chapter: chapter),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.book, required this.chapter});

  final Book book;
  final Chapter chapter;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChapterTextScreen(book: book, index: chapter.index),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF22222A))),
        ),
        child: Row(
          spacing: 14,
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '${chapter.index + 1}',
                style: const TextStyle(fontSize: 13, color: Graphite.textMuted),
              ),
            ),
            Expanded(child: Text(chapter.title, maxLines: 2, overflow: TextOverflow.ellipsis)),
            Text(
              listeningTime(chapter.text.length),
              style: const TextStyle(fontSize: 13, color: Graphite.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Текст главы, как его разобрал Lumen. Внизу над островом — прогресс главы
/// и кнопки соседних глав; главы меняются на месте, без перехода экрана.
/// Подсветка слова под голосом — отдельный этап.
class ChapterTextScreen extends StatefulWidget {
  const ChapterTextScreen({super.key, required this.book, required this.index});

  /// Книга целиком, с главами.
  final Book book;

  /// Номер открытой главы.
  final int index;

  @override
  State<ChapterTextScreen> createState() => _ChapterTextScreenState();
}

class _ChapterTextScreenState extends State<ChapterTextScreen> {
  final _scroll = ScrollController();
  final _progress = ValueNotifier<double>(0);
  late int _index = widget.index;

  static const _column = 760.0;

  List<Chapter> get _chapters => widget.book.chapters;

  @override
  void dispose() {
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index < 0 || index >= _chapters.length || index == _index) return;
    setState(() => _index = index);
    _progress.value = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _seek(double fraction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _scroll.jumpTo(fraction * position.maxScrollExtent);
  }

  bool _onMetrics(ScrollMetrics m) {
    // Глава целиком на экране — прочитана.
    final value = m.maxScrollExtent <= 0 ? 1.0 : (m.pixels / m.maxScrollExtent).clamp(0.0, 1.0);
    if ((value - _progress.value).abs() > 0.001) _progress.value = value;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapters[_index];
    final paragraphs = chapter.paragraphTexts;
    final panelBottom = islandClearance(context) + 10;
    return CallbackShortcuts(
      bindings: {
        // ⌥← / ⌥→ (Alt на Windows) — соседняя глава.
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _go(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _go(_index + 1),
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (n) => _onMetrics(n.metrics),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) => _onMetrics(n.metrics),
                  child: ListView.builder(
                    // Новая глава — новый список, без следов прошлой прокрутки.
                    key: ValueKey(_index),
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(20, _top(context), 20, panelBottom + 110),
                    itemCount: paragraphs.length + 1,
                    itemBuilder: (context, i) {
                      final Widget child;
                      if (i == 0) {
                        child = Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: ClearOfProfile(
                            maxWidth: _column,
                            child: Row(
                              spacing: 14,
                              children: [
                                GlassIconButton(
                                  icon: Icons24.back,
                                  label: 'Назад',
                                  onPressed: () => Navigator.of(context).maybePop(),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.book.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Graphite.textMuted,
                                        ),
                                      ),
                                      Text(
                                        chapter.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        child = Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            paragraphs[i - 1],
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.55,
                              color: Graphite.text,
                            ),
                          ),
                        );
                      }
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: _column),
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: panelBottom,
              child: Center(
                child: ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, value, _) => ReadingPanel(
                    title: 'Глава ${_index + 1} из ${_chapters.length}',
                    trailing: '${(value * 100).round()} %',
                    value: value,
                    onSeek: _seek,
                    onPrevious: _index > 0 ? () => _go(_index - 1) : null,
                    onNext: _index < _chapters.length - 1 ? () => _go(_index + 1) : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Стеклянная плашка «подпись / значение» (Формат, Глав, Звука).
class FactTile extends StatelessWidget {
  const FactTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Glass(
    radius: 14,
    shadow: false,
    fill: Graphite.glassFillStrong,
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Graphite.textMuted)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
