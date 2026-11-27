import 'dart:async';

import 'package:flutter/rendering.dart' hide TextRange;
import 'package:flutter/services.dart' hide TextRange;
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_storage/lumen_storage.dart';
import 'package:material_ui/material_ui.dart' hide TextRange;

import '../library/book_transitions.dart';
import '../library/chapter_content.dart';
import '../library/library_scope.dart';
import '../library/widgets.dart';
import '../narration/music.dart';
import '../narration/narration_controller.dart';
import '../narration/narration_scope.dart';
import '../narration/narration_sheets.dart';
import '../reader/narration_controls.dart';
import '../reader/reading_panel.dart';
import '../shell/profile_button.dart';
import '../shell/tabs.dart';
import '../shell/app_shell.dart' show TabSwitcher;
import '../theme/fading_glass.dart';
import '../theme/glass.dart';
import '../theme/graphite.dart';
import 'tab_page.dart';

/// Верх экрана: кнопки стоят на одной высоте с кружком профиля
/// (на Mac под полосой с кнопками окна).
double _top(BuildContext context) =>
    MediaQuery.paddingOf(context).top + TabPage.windowBar + ProfileButton.top;

/// Открытая книга (Брэд, 27.11.2026): сразу текст — с места, где читатель
/// остановился, или с начала книги. Отдельной страницы со списком глав нет,
/// главы — кнопкой «Главы» в плеере.
///
/// Пока обложка летит к центру и вырастает до ~85 % экрана, книга читается
/// в фоне; когда перелёт закончен и книга готова, обложка гаснет, а текст
/// (уже разложенный и стоящий на нужном абзаце) проявляется.
class BookScreen extends StatefulWidget {
  const BookScreen({super.key, required this.bookId, this.preview, this.openChapter});

  final String bookId;

  /// Открыть эту главу (мини-плеер: глава, которая звучит); `null` — где остановился.
  final int? openChapter;

  /// Книга из списка (без глав): её обложка видна сразу, пока книга грузится.
  final Book? preview;

  /// Глава, с которой открыть книгу: заданная, иначе текущая; дочитанная
  /// текущая — следующая за ней; книгу ещё не открывали — первая.
  static int startChapter(ReadingProgress progress, int chapters, [int? asked]) {
    if (chapters == 0) return 0;
    if (asked != null && asked >= 0 && asked < chapters) return asked;
    final current = progress.current;
    if (current == null || current >= chapters) return 0;
    if (progress.finished(current) && current + 1 < chapters) return current + 1;
    return current;
  }

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  Book? _book;
  ReadingProgress _progress = ReadingProgress.empty;
  var _loaded = false;

  /// Перелёт обложки закончен: можно менять её на текст.
  var _landed = false;
  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_route == null) {
      _route = ModalRoute.of(context)?.animation;
      _route?.addStatusListener(_onRoute);
      _landed = _route == null || _route!.status == AnimationStatus.completed;
      _load();
    }
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onRoute);
    super.dispose();
  }

  void _onRoute(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_landed) setState(() => _landed = true);
  }

  Future<void> _load() async {
    final store = LibraryScope.of(context).store;
    // Книга и место читаются одновременно; книга — в фоновом потоке.
    final (book, progress) = await (store.book(widget.bookId), store.progress(widget.bookId)).wait;
    if (!mounted) return;
    setState(() {
      _book = book;
      _progress = progress;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final cover = _book ?? widget.preview;
    final ready = _loaded && _landed;
    final screen = MediaQuery.sizeOf(context);
    final big = bigCoverRect(screen);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (book != null && book.chapters.isNotEmpty)
            // Текст строится сразу, как только книга прочитана, но виден только
            // после перелёта: за это время он раскладывается и встаёт на место.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !ready,
                child: AnimatedOpacity(
                  opacity: ready ? 1 : 0,
                  // Большая обложка ещё мгновение стоит, потом её сменяет текст.
                  duration: const Duration(milliseconds: 560),
                  curve: const Interval(.4, 1, curve: Curves.easeOut),
                  child: ChapterTextScreen(
                    book: book,
                    index: BookScreen.startChapter(
                      _progress,
                      book.chapters.length,
                      widget.openChapter,
                    ),
                    progress: _progress,
                  ),
                ),
              ),
            ),
          if (_loaded && (book == null || book.chapters.isEmpty))
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  const Text('В этой книге нет текста', style: TextStyle(fontSize: 17)),
                  GlassIconButton(
                    icon: Icons24.back,
                    label: 'Назад',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          // Обложка посреди экрана: сюда прилетает обложка из библиотеки
          // и сюда же возвращается при закрытии книги.
          if (cover != null)
            Positioned.fromRect(
              rect: big,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: ready ? 0 : 1,
                  duration: const Duration(milliseconds: 560),
                  curve: const Interval(.4, 1, curve: Curves.easeIn),
                  child: FlyingCover(
                    book: cover,
                    child: BigCover(book: cover),
                  ),
                ),
              ),
            ),
        ],
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

  /// Озвучка на всё приложение: эта глава может играть, а может играть другая книга.
  late NarrationController _narration;
  var _listening = false;

  /// Что видно в блоке озвучки; экран перестраивается, только когда это меняется.
  var _view = const NarrationView();

  /// Слово и предложение под голосом (места в главе) — их слушают абзацы.
  final _marks = ValueNotifier<_Marks?>(null);

  /// Глава, которую голос читал в прошлый раз: голос перешёл к следующей — экран за ним.
  int? _narratedChapter;

  /// Читатель сам листал: какое-то время текст за голосом не едет.
  var _userScrolledAt = DateTime(0);
  var _autoScroll = false;
  double _bottomInset = 0;

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
    if (!_listening) {
      _listening = true;
      _narration = NarrationScope.read(context)
        ..attachStore(_store)
        ..attachReader(widget.book.id)
        ..addListener(_onNarration);
      _narration.live.addListener(_onNarration);
      _onNarration();
    }
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _save(notify: false);
    _narration.live.removeListener(_onNarration);
    _narration
      ..removeListener(_onNarration)
      ..detachReader(widget.book.id);
    _scroll.dispose();
    _progress.dispose();
    _marks.dispose();
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
    // Время кадров, а не часов: в тестах и при паузах оно идёт вместе с кадрами.
    Duration? started;
    Duration? found;
    void frame(Duration now) {
      if (!mounted || !_restoring) return;
      started ??= now;
      bool ok;
      if (place != null) {
        ok = _showPlace(place);
      } else {
        ok = _scroll.hasClients;
        if (ok) _scroll.jumpTo(estimate * _scroll.position.maxScrollExtent);
      }
      if (ok) found ??= now;
      final done =
          (found != null && now - found! > const Duration(seconds: 2)) ||
          now - started! > const Duration(seconds: 6);
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

  void _go(int index, {bool byVoice = false}) {
    if (index < 0 || index >= _chapters.length || index == _index) return;
    // Голос читает эту главу — он тоже переходит.
    if (!byVoice && _narrated) _narration.goToChapter(index);
    _save();
    setState(() => _index = index);
    _progress.value = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _restore();
  }

  void _seek(double fraction) {
    if (_narrated && _narration.state.playing) {
      _narration.seekFraction(fraction);
      _userScrolledAt = DateTime(0);
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _scroll.jumpTo(fraction * position.maxScrollExtent);
  }

  /// Голос читает именно эту главу этой книги.
  bool get _narrated =>
      _narration.book?.id == widget.book.id &&
      _narration.chapterIndex == _index &&
      _narration.text != null;

  void _onNarration() {
    if (!mounted) return;
    final n = _narration;
    final sameBook = n.book?.id == widget.book.id;
    // Глава дочитана, голос пошёл дальше — и экран за ним.
    if (sameBook && n.state.playing && n.chapterIndex != _index && _narratedChapter == _index) {
      _narratedChapter = n.chapterIndex;
      _go(n.chapterIndex, byVoice: true);
      return;
    }
    _narratedChapter = sameBook ? n.chapterIndex : null;
    final narrated = _narrated;
    final s = n.state;
    final view = NarrationView(
      playing: narrated && s.playing,
      loading: narrated && s.playing && s.loading,
      speed: n.speed,
      voiceName: n.voiceName,
      musicOn: n.mix.musicOn,
      musicVolume: n.mix.musicVolume,
      voiceVolume: n.voiceVolume,
      musicTrack: n.track.index,
      sleepTimer: n.sleep.remaining ?? (n.sleep.endOfChapter ? Duration.zero : null),
      notice: narrated ? _noticeOf(n) : null,
    );
    if (view != _view) setState(() => _view = view);
    final marks = narrated && (s.word != null || s.sentence != null)
        ? _Marks(word: s.word, sentence: s.sentence)
        : null;
    if (marks != _marks.value) {
      _marks.value = marks;
      if (marks != null && s.playing) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _followVoice());
      }
    }
  }

  static String? _noticeOf(NarrationController n) {
    final waiting = n.state.waiting;
    if (waiting != null) return '${waiting.title} · жду';
    final fallback = n.state.fallback;
    if (fallback != null) return '${fallback.title} · читает системный голос';
    return null;
  }

  /// «Слушать» / «Пауза».
  void _playPause() {
    final n = _narration;
    _userScrolledAt = DateTime(0);
    if (!_narrated) {
      // С места, где читатель сейчас, а не с начала главы.
      n.open(widget.book, _index, place: _placeNow() ?? _places.places[_index]);
      n.play();
      return;
    }
    if (n.state.playing) {
      n.pause();
      return;
    }
    // На паузе ушёл листать далеко от голоса — читать с места на экране.
    if (_wordTop() == null || !_isVisible(_wordTop()!)) {
      final place = _placeNow();
      if (place != null) n.jumpTo(offsetOfPlace(_chapters[_index], place));
    }
    n.play();
  }

  /// Нажатие на слово в тексте: голос читает отсюда.
  void _readFrom(int offset) {
    if (!_narrated) return;
    _userScrolledAt = DateTime(0);
    _narration.jumpTo(offset);
  }

  /// Где по прокрутке стоит строка звучащего слова; `null` — абзац ещё не построен.
  double? _wordTop() {
    final marks = _marks.value;
    final range = marks?.word ?? marks?.sentence;
    if (range == null || !_scroll.hasClients) return null;
    final chapter = _chapters[_index];
    final p = _paragraphOf(chapter, range.start);
    if (p == null) return null;
    final item = _itemsOf(chapter).indexWhere((it) => it is ParagraphItem && it.index == p);
    final paragraph = _paragraphBox(_built[item]);
    if (paragraph == null || !paragraph.attached) return null;
    final start = (range.start - chapter.paragraphs[p].start).clamp(
      0,
      paragraph.text.toPlainText().length,
    );
    final caret = paragraph.getOffsetForCaret(TextPosition(offset: start), Rect.zero);
    final top = RenderAbstractViewport.of(paragraph).getOffsetToReveal(paragraph, 0).offset;
    return top + caret.dy;
  }

  bool _isVisible(double y) {
    final position = _scroll.position;
    final top = position.pixels + _topInset;
    final bottom = position.pixels + position.viewportDimension - _bottomInset;
    return y >= top && y + 24 <= bottom;
  }

  /// Текст едет за голосом: строка со словом держится в верхней трети видимого текста.
  void _followVoice() {
    if (!mounted || _restoring || !_scroll.hasClients || !_narrated) return;
    if (DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 6)) return;
    final position = _scroll.position;
    final visible = position.viewportDimension - _topInset - _bottomInset;
    final y = _wordTop();
    if (y == null) {
      // Абзац далеко и ещё не построен: прыжок к нему, точнее — на следующем слове.
      final marks = _marks.value;
      final range = marks?.word ?? marks?.sentence;
      if (range == null) return;
      final chapter = _chapters[_index];
      final p = _paragraphOf(chapter, range.start);
      if (p == null) return;
      final item = _itemsOf(chapter).indexWhere((it) => it is ParagraphItem && it.index == p);
      if (item >= 0) {
        _autoScroll = true;
        _showPlace(ChapterPlace(item: item));
        _autoScroll = false;
      }
      return;
    }
    final top = position.pixels + _topInset;
    final inZone = y >= top + visible * 0.08 && y <= top + visible * 0.62;
    if (inZone) return;
    final target = (y - _topInset - visible * 0.3).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _autoScroll = true;
    _scroll
        .animateTo(
          target,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeInOutCubic,
        )
        .whenComplete(() => _autoScroll = false);
  }

  static int? _paragraphOf(Chapter chapter, int offset) {
    int? found;
    for (var i = 0; i < chapter.paragraphs.length; i++) {
      if (chapter.paragraphs[i].start <= offset) found = i;
    }
    return found;
  }

  static RenderParagraph? _paragraphBox(BuildContext? context) {
    RenderParagraph? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    final root = context?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  NarrationActions get _actions {
    final n = _narration;
    final here = _narrated;
    return NarrationActions(
      playPause: _playPause,
      back15: here ? () => n.skip(-15) : null,
      forward15: here ? () => n.skip(15) : null,
      previousPhrase: here ? n.previousPhrase : null,
      nextPhrase: here ? n.nextPhrase : null,
      speed: n.setSpeed,
      sleepTimer: () => showSleepTimer(context, n),
      voice: () => showVoicePicker(context, n, openServer: _openServer),
      music: n.setMusic,
      musicVolume: n.setMusicVolume,
      voiceVolume: n.setVoiceVolume,
      musicTrack: (i) => n.setTrack(MusicTrack.values[i]),
      chapters: _pickChapter,
      textLook: _soon,
    );
  }

  /// «Подключить сервер» из окна голоса: вкладка «Голоса» (книга в библиотеке остаётся).
  void _openServer() => TabSwitcher.of(context)(AppTab.voices);

  // «Вид текста» — этап 5.
  static void _soon() {}

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
    // Читатель сам листает (пальцем, колесом, полосой) — текст пока не едет за голосом.
    if (n is ScrollUpdateNotification && !_autoScroll && !_restoring) {
      _userScrolledAt = DateTime.now();
    }
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
    _bottomInset = textBottom;
    return CallbackShortcuts(
      bindings: {
        // ⌥← / ⌥→ (Alt на Windows) — соседняя глава.
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _go(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _go(_index + 1),
        const SingleActivator(LogicalKeyboardKey.space): _playPause,
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
                                child: switch (items[i]) {
                                  final ParagraphItem item => _NarratedParagraph(
                                    item: item,
                                    range: chapter.paragraphs[item.index],
                                    marks: _marks,
                                    onTap: _readFrom,
                                  ),
                                  final item => ChapterItemView(item: item),
                                },
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
                      child: NarrationControls(view: _view, actions: _actions),
                      builder: (context, value, controls) => ReadingPanel(
                        title: _view.notice ?? 'Глава ${_index + 1} из ${_chapters.length}',
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

/// Слово и предложение под голосом, места в главе.
@immutable
class _Marks {
  const _Marks({this.word, this.sentence});

  final TextRange? word;
  final TextRange? sentence;

  @override
  bool operator ==(Object other) =>
      other is _Marks && other.word == word && other.sentence == sentence;

  @override
  int get hashCode => Object.hash(word, sentence);
}

/// Абзац с подсветкой голоса. Перестраивается, только когда подсветка задевает именно его,
/// а не на каждое слово главы. Нажатие на слово — голос читает отсюда.
class _NarratedParagraph extends StatefulWidget {
  const _NarratedParagraph({
    required this.item,
    required this.range,
    required this.marks,
    required this.onTap,
  });

  final ParagraphItem item;

  /// Место абзаца в главе.
  final TextRange range;
  final ValueNotifier<_Marks?> marks;
  final ValueChanged<int> onTap;

  @override
  State<_NarratedParagraph> createState() => _NarratedParagraphState();
}

class _NarratedParagraphState extends State<_NarratedParagraph> {
  _Marks? _local;

  @override
  void initState() {
    super.initState();
    _local = _localOf(widget.marks.value);
    widget.marks.addListener(_changed);
  }

  @override
  void didUpdateWidget(_NarratedParagraph old) {
    super.didUpdateWidget(old);
    if (old.marks != widget.marks) {
      old.marks.removeListener(_changed);
      widget.marks.addListener(_changed);
    }
    _local = _localOf(widget.marks.value);
  }

  @override
  void dispose() {
    widget.marks.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final local = _localOf(widget.marks.value);
    if (local != _local) setState(() => _local = local);
  }

  /// Часть подсветки внутри этого абзаца, в его местах.
  _Marks? _localOf(_Marks? marks) {
    if (marks == null) return null;
    TextRange? cut(TextRange? r) {
      if (r == null) return null;
      final start = r.start > widget.range.start ? r.start : widget.range.start;
      final end = r.end < widget.range.end ? r.end : widget.range.end;
      if (end <= start) return null;
      return TextRange(start - widget.range.start, end - start);
    }

    final word = cut(marks.word);
    final sentence = cut(marks.sentence);
    return word == null && sentence == null ? null : _Marks(word: word, sentence: sentence);
  }

  void _tap(TapUpDetails details) {
    RenderParagraph? paragraph;
    void visit(RenderObject object) {
      if (paragraph != null) return;
      if (object is RenderParagraph) {
        paragraph = object;
        return;
      }
      object.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) visit(root);
    final found = paragraph;
    if (found == null) return;
    final at = found.getPositionForOffset(found.globalToLocal(details.globalPosition)).offset;
    widget.onTap(widget.range.start + at.clamp(0, widget.range.length));
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapUp: _tap,
    child: ChapterItemView(item: widget.item, word: _local?.word, sentence: _local?.sentence),
  );
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
