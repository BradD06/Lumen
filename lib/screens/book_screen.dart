import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_storage/lumen_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../library/book_cover.dart';
import '../library/chapter_content.dart';
import '../library/library_scope.dart';
import '../library/widgets.dart';
import '../reader/narration_controls.dart';
import '../reader/reading_panel.dart';
import '../shell/profile_button.dart';
import '../theme/fading_glass.dart';
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

  /// Где читатель остановился; текст главы сообщает каждое новое место.
  var _progress = ReadingProgress.empty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_book == null) {
      _book = LibraryScope.of(context).store.book(widget.bookId);
      _loadProgress();
    }
  }

  Future<void> _loadProgress() async {
    final progress = await LibraryScope.of(context).store.progress(widget.bookId);
    if (mounted) setState(() => _progress = progress);
  }

  void _open(Book book, int index) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChapterTextScreen(
        book: book,
        index: index,
        progress: _progress,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      ),
    ),
  );

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
          final read = loaded && _progress.current != null
              ? _progress.ofBook([for (final c in book.chapters) c.text.length])
              : null;
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
                                if (read != null)
                                  Text(
                                    'Прочитано ${(read * 100).floor()} %',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Graphite.amber,
                                    ),
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
                              _ChapterRow(
                                chapter: chapter,
                                current: _progress.current == chapter.index,
                                fraction: _progress.of(chapter.index),
                                onTap: () => _open(book, chapter.index),
                              ),
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

/// Строка списка глав. Глава, где читатель остановился, отмечена янтарём:
/// «Вы остановились здесь», процент и полоска прочитанного (Брэд, 27.11.2026).
class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.current,
    required this.fraction,
    required this.onTap,
  });

  final Chapter chapter;
  final bool current;

  /// Прочитанная доля главы.
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = (fraction * 100).floor();
    final finished = fraction >= 0.99;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF22222A))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Row(
              spacing: 14,
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    '${chapter.index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: current ? FontWeight.w700 : null,
                      color: current ? Graphite.amber : Graphite.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        chapter.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: current ? const TextStyle(fontWeight: FontWeight.w600) : null,
                      ),
                      if (current)
                        const Text(
                          'Вы остановились здесь',
                          style: TextStyle(fontSize: 12, color: Graphite.amber),
                        ),
                    ],
                  ),
                ),
                Text(
                  current
                      ? '$percent %'
                      : finished
                      ? 'Прочитана'
                      : listeningTime(chapter.text.length),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: current ? FontWeight.w600 : null,
                    color: current ? Graphite.amber : Graphite.textMuted,
                  ),
                ),
              ],
            ),
            if (current)
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 3,
                    color: Graphite.amber,
                    backgroundColor: const Color(0xFF2A2A33),
                  ),
                ),
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
  const ChapterTextScreen({
    super.key,
    required this.book,
    required this.index,
    this.progress = ReadingProgress.empty,
    this.onProgress,
  });

  /// Книга целиком, с главами.
  final Book book;

  /// Номер открытой главы.
  final int index;

  /// Сколько уже прочитано: глава открывается на своём месте.
  final ReadingProgress progress;

  /// Новое место: карточка книги под этим экраном сразу его показывает.
  final ValueChanged<ReadingProgress>? onProgress;

  @override
  State<ChapterTextScreen> createState() => _ChapterTextScreenState();
}

class _ChapterTextScreenState extends State<ChapterTextScreen> {
  final _scroll = ScrollController();
  final _progress = ValueNotifier<double>(0);
  late int _index = widget.index;

  /// Места глав, открытых в этот раз; пишутся в библиотеку с задержкой.
  late var _places = widget.progress;

  /// Пока глава не встала на сохранённое место, прокрутку не запоминаем:
  /// иначе первый кадр (начало главы) затрёт место.
  var _restoring = true;
  Timer? _saveTimer;
  late BookStore _store;

  /// Построенные сейчас абзацы и картинки (номер → их место в дереве):
  /// по ним считается и восстанавливается точное место в главе.
  final _built = <int, BuildContext>{};

  /// Сверху место под шапку: верх видимого текста — «линия чтения».
  double _topInset = 0;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Библиотека нужна и в dispose, где искать её по дереву уже нельзя.
    _store = LibraryScope.of(context).store;
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _save(notify: false);
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  /// Записать место текущей главы сразу.
  void _save({bool notify = true}) {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_restoring) return;
    final fraction = _progress.value;
    // При закрытии экрана абзацы уже убраны: тогда остаётся последнее известное место.
    final place = notify ? _placeNow() : _places.places[_index];
    _places = _places.withChapter(_index, fraction, place: place);
    // При закрытии экрана дерево виджетов уже нельзя перестраивать.
    if (notify) widget.onProgress?.call(_places);
    _store.saveProgress(widget.book.id, _index, fraction, place: place);
  }

  /// Абзац под линией чтения и сколько его уже ушло под шапку.
  ChapterPlace? _placeNow() {
    if (!_scroll.hasClients) return null;
    final line = _scroll.position.pixels + _topInset;
    ChapterPlace? below;
    var belowItem = 1 << 30;
    for (final MapEntry(key: i, value: context) in _built.entries) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      final height = box.size.height;
      if (line >= top && line < top + height) {
        return ChapterPlace(item: i, within: height > 0 ? (line - top) / height : 0);
      }
      if (top >= line && i < belowItem) {
        belowItem = i;
        below = ChapterPlace(item: i);
      }
    }
    return below;
  }

  /// Поставить [place] на линию чтения. `false` — абзац ещё не построен:
  /// тогда прыгаем примерно к нему, точное место — в следующем кадре.
  bool _showPlace(ChapterPlace place) {
    if (!_scroll.hasClients) return false;
    final position = _scroll.position;
    final box = _built[place.item]?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      final target = top + place.within * box.size.height - _topInset;
      final clamped = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((clamped - position.pixels).abs() > 0.5) _scroll.jumpTo(clamped);
      return true;
    }
    final count = _itemsOf(_chapters[_index]).length;
    if (count > 0) _scroll.jumpTo(position.maxScrollExtent * place.item / count);
    return false;
  }

  /// Глава открывается там, где её оставили; дочитанная — с начала.
  /// Абзацы и картинки достраиваются после первого кадра (картинки ещё и
  /// грузятся), и высота текста выше места меняется. Поэтому место держим
  /// каждый кадр, пока всё не уляжется (~2 с после того, как абзац нашёлся),
  /// или пока читатель сам не начнёт листать.
  void _restore() {
    _restoring = true;
    final fraction = _places.of(_index);
    final finished = fraction >= 0.99;
    final place = finished ? null : _places.places[_index];
    // Старые записи без точного места — по доле главы.
    final estimate = finished || place != null ? 0.0 : fraction;
    if (place == null && estimate == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _endRestore());
      return;
    }
    final started = DateTime.now();
    DateTime? found;
    void frame(Duration _) {
      if (!mounted || !_restoring) return;
      final now = DateTime.now();
      bool ok;
      if (place != null) {
        ok = _showPlace(place);
      } else {
        ok = _scroll.hasClients;
        if (ok) _scroll.jumpTo(estimate * _scroll.position.maxScrollExtent);
      }
      if (ok) found ??= now;
      final done =
          (found != null && now.difference(found!) > const Duration(seconds: 2)) ||
          now.difference(started) > const Duration(seconds: 6);
      if (done) {
        _endRestore();
      } else {
        WidgetsBinding.instance.addPostFrameCallback(frame);
        WidgetsBinding.instance.scheduleFrame();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(frame);
  }

  void _endRestore() {
    if (!mounted || !_restoring) return;
    _restoring = false;
    // Открытая глава сразу становится текущей.
    _save();
  }

  void _go(int index) {
    if (index < 0 || index >= _chapters.length || index == _index) return;
    _save();
    setState(() => _index = index);
    _progress.value = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _restore();
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

  bool _onScroll(ScrollNotification n) {
    // Читатель сам начал листать — место больше не держим.
    if (n is ScrollStartNotification && n.dragDetails != null) _endRestore();
    return _onMetrics(n.metrics);
  }

  bool _onMetrics(ScrollMetrics m) {
    // Глава целиком на экране — прочитана.
    final value = m.maxScrollExtent <= 0 ? 1.0 : (m.pixels / m.maxScrollExtent).clamp(0.0, 1.0);
    if ((value - _progress.value).abs() > 0.001) {
      _progress.value = value;
      if (!_restoring) {
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 600), _save);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapters[_index];
    _topInset = _ChapterHeader.heightOf(context) + _ChapterHeader._fade + 4;
    // Абзацы и иллюстрации по порядку; считаем один раз на главу.
    final items = _itemsOf(chapter);
    // Плеер — полоса во всю ширину у низа окна (остров в книге спрятан).
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final panelInset = safeBottom > 0 ? safeBottom : 12.0;
    final panelWidth = (MediaQuery.sizeOf(context).width - 24).clamp(0.0, _panelWidth);
    // Строка прогресса 44 + блок озвучки + отступы: последние строки встают
    // целиком над плеером, вместе с его стеклянной кромкой.
    final textBottom =
        panelInset + 12 + 44 + NarrationControls.heightFor(panelWidth) + ReadingPanel.fade + 12;
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
        // Уходя к списку глав, сразу запоминаем место: список покажет его.
        child: PopScope<Object?>(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) _save();
          },
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (n) => _onMetrics(n.metrics),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: ListView.builder(
                        // Новая глава — новый список, без следов прошлой прокрутки.
                        key: ValueKey(_index),
                        controller: _scroll,
                        // Сверху место под шапку вместе с её стеклянной кромкой: в начале
                        // главы ничего не размыто, при прокрутке текст уходит под шапку.
                        padding: EdgeInsets.fromLTRB(20, _topInset, 20, textBottom),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          return _ItemSlot(
                            index: i,
                            built: _built,
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: _column),
                                child: ChapterItemView(item: items[i]),
                              ),
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
                  left: 0,
                  right: 0,
                  bottom: 0,
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
                        bottomInset: panelInset,
                        controls: controls,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Абзац или картинка в списке главы: пока построены, отмечены в [built],
/// чтобы экран мог найти и восстановить место чтения.
class _ItemSlot extends StatefulWidget {
  const _ItemSlot({required this.index, required this.built, required this.child});

  final int index;
  final Map<int, BuildContext> built;
  final Widget child;

  @override
  State<_ItemSlot> createState() => _ItemSlotState();
}

class _ItemSlotState extends State<_ItemSlot> {
  @override
  void initState() {
    super.initState();
    widget.built[widget.index] = context;
  }

  @override
  void didUpdateWidget(_ItemSlot old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (identical(old.built[old.index], context)) old.built.remove(old.index);
      widget.built[widget.index] = context;
    }
  }

  @override
  void dispose() {
    if (identical(widget.built[widget.index], context)) widget.built.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
          const Positioned.fill(
            child: FadingGlass(fadeEdge: AxisDirection.down, fade: _fade),
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
