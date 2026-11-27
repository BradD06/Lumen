import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:material_ui/material_ui.dart';

import '../library/book_cover.dart';
import '../library/chapter_content.dart';
import '../library/library_scope.dart';
import '../library/widgets.dart';
import '../reader/narration_controls.dart';
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
                      // «Назад» — на месте кружка профиля (профиль в книге скрыт).
                      Row(
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

  /// Блок озвучки пока только для вида: кнопки меняют то, что видно,
  /// звук подключит плеер (этап 3).
  var _narration = const NarrationView();

  static const _column = 760.0;
  static const _panelWidth = 680.0;

  List<Chapter> get _chapters => widget.book.chapters;

  Chapter? _itemsChapter;
  List<ChapterItem> _items = const [];

  List<ChapterItem> _itemsOf(Chapter chapter) {
    if (!identical(chapter, _itemsChapter)) {
      _itemsChapter = chapter;
      _items = chapterItems(chapter);
    }
    return _items;
  }

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

  void _narrate(NarrationView view) => setState(() => _narration = view);

  // Перемотка и фразы появятся с плеером (этап 3).
  static void _soon() {}

  NarrationActions get _actions => NarrationActions(
    playPause: () => _narrate(_narration.copyWith(playing: !_narration.playing)),
    back15: _soon,
    forward15: _soon,
    previousPhrase: _soon,
    nextPhrase: _soon,
    speed: (v) => _narrate(_narration.copyWith(speed: v)),
    sleepTimer: _soon,
    voice: _soon,
    music: (on) => _narrate(_narration.copyWith(musicOn: on)),
    musicVolume: (v) => _narrate(_narration.copyWith(musicVolume: v)),
    chapters: _pickChapter,
    textLook: _soon,
  );

  Future<void> _pickChapter() async {
    final picked = await showDialog<int>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (context) => Dialog(
        backgroundColor: const Color(0xF21A1A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('Главы', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: _chapters.length,
                  itemBuilder: (context, i) => ListTile(
                    selected: i == _index,
                    selectedColor: Graphite.text,
                    selectedTileColor: Graphite.islandOn,
                    leading: Text(
                      '${i + 1}',
                      style: const TextStyle(fontSize: 13, color: Graphite.textMuted),
                    ),
                    title: Text(_chapters[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop(i),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _go(picked);
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
    // Абзацы и иллюстрации по порядку; считаем один раз на главу.
    final items = _itemsOf(chapter);
    // Остров в открытой книге спрятан: плеер стоит на его месте.
    final panelBottom = islandBottom(context);
    final panelWidth = (MediaQuery.sizeOf(context).width - 24).clamp(0.0, _panelWidth);
    // Текст прокручивается до конца над панелью: прогресс 56 + блок озвучки.
    final textBottom = panelBottom + 56 + NarrationControls.heightFor(panelWidth) + 40;
    return CallbackShortcuts(
      bindings: {
        // ⌥← / ⌥→ (Alt на Windows) — соседняя глава.
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _go(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _go(_index + 1),
        const SingleActivator(LogicalKeyboardKey.space): () => _actions.playPause!(),
      },
      // Свой фокус, чтобы клавиши экрана работали; ⌘1…⌘5 окна выше по дереву.
      child: Focus(
        autofocus: true,
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
                      // Сверху место под закреплённую шапку: текст уходит под неё.
                      padding: EdgeInsets.fromLTRB(
                        20,
                        _ChapterHeader.heightOf(context) + 8,
                        20,
                        textBottom,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final child = ChapterItemView(item: items[i]);
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
                left: 0,
                right: 0,
                top: 0,
                child: _ChapterHeader(
                  bookTitle: widget.book.title,
                  chapterTitle: chapter.title,
                  column: _column,
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: panelBottom,
                child: Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    // Блок озвучки строится один раз на кадр экрана, а не на каждый
                    // шаг прокрутки: прогресс меняется 60 раз в секунду.
                    child: NarrationControls(view: _narration, actions: _actions),
                    builder: (context, value, controls) => ReadingPanel(
                      title: 'Глава ${_index + 1} из ${_chapters.length}',
                      trailing: '${(value * 100).round()} %',
                      value: value,
                      onSeek: _seek,
                      onPrevious: _index > 0 ? () => _go(_index - 1) : null,
                      onNext: _index < _chapters.length - 1 ? () => _go(_index + 1) : null,
                      maxWidth: _panelWidth,
                      controls: controls,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Шапка текста главы, закреплённая сверху (Брэд, 27.11.2026): «Назад» в строке
/// с кружком профиля, название книги и главы по центру экрана. Под шапкой
/// жидкое стекло: текст, уходящий под неё при прокрутке, размывается, а нижний
/// край стекла плавно сходит на нет.
class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({required this.bookTitle, required this.chapterTitle, required this.column});

  final String bookTitle;
  final String chapterTitle;

  /// Ширина колонки текста: «Назад» стоит по её левому краю, когда окно широкое.
  final double column;

  /// Высота строки кнопок вместе с отступом сверху (под ней начинается текст).
  static double heightOf(BuildContext context) => _top(context) + _bar + _gap;

  static const _bar = 44.0;
  static const _gap = 12.0;

  /// Полоса, где стекло сходит на нет.
  static const _fade = 30.0;

  /// Размытие полос в нижней кромке: мелкие шаги, чтобы край не читался полосой.
  static const _fadeSigmas = [11.0, 8.0, 6.0, 4.0, 2.5, 1.2];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = heightOf(context);
    // «Назад» на месте кружка профиля (профиль в книге скрыт), а в широком
    // окне — по левому краю колонки текста.
    final backLeft = 20 + ((width - 40 - column).clamp(0, double.infinity) / 2);
    // Название по центру экрана: поля с двух сторон одинаковые, чтобы не наехать на «Назад».
    final side = backLeft + _bar + 12;
    return SizedBox(
      height: height + _fade,
      child: Stack(
        children: [
          // Стекло: сильное размытие под шапкой и всё слабее в полосе снизу.
          Positioned(left: 0, right: 0, top: 0, height: height, child: _Blur(sigma: 14)),
          for (final (i, sigma) in _fadeSigmas.indexed)
            Positioned(
              left: 0,
              right: 0,
              top: height + i * _fade / _fadeSigmas.length,
              height: _fade / _fadeSigmas.length,
              child: _Blur(sigma: sigma),
            ),
          // Затемнение фоном приложения: сверху плотнее, к низу прозрачное.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, height / (height + _fade), 1],
                    colors: [
                      Graphite.background.withValues(alpha: .72),
                      Graphite.background.withValues(alpha: .45),
                      Graphite.background.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: backLeft,
            top: _top(context),
            child: GlassIconButton(
              icon: Icons24.back,
              label: 'Назад',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            left: side,
            right: side,
            top: _top(context),
            height: _bar,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  bookTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Graphite.textMuted),
                ),
                Text(
                  chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Blur extends StatelessWidget {
  const _Blur({required this.sigma});

  final double sigma;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
      child: const SizedBox.expand(),
    ),
  );
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
