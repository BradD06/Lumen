import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_player/lumen_player.dart';
import 'package:lumen_storage/lumen_storage.dart';
import 'package:lumen_voice/lumen_voice.dart';

import '../library/chapter_content.dart';
import 'audio_outputs.dart';
import 'media_session.dart';
import 'music.dart';
import 'prefs.dart';

/// Озвучка книги на всё приложение: одна книга играет, пока ходишь по разделам
/// (мини-плеер над островом), в фоне и с экрана блокировки.
///
/// Диктор (`Narrator`) читает главу; здесь — какая книга и глава, голос и сервер,
/// скорость, таймер сна, фоновая музыка с приглушением под голосом, место прослушивания
/// и экран блокировки.
class NarrationController extends ChangeNotifier implements MediaCommands {
  NarrationController({
    required PhrasePlayer player,
    required SystemSpeech speech,
    this.music,
    this.silence,
    SecretStore? secrets,
    Prefs? prefs,
    this.cacheFolder,
    this.keepAwake = false,
  }) : _settings = VoiceServerSettings(secrets ?? MemorySecretStore()),
       _prefs = prefs ?? MemoryPrefs(),
       _voiceOutputs = [player, speech].whereType<VoiceVolume>().toList(),
       narrator = Narrator(player: player, speech: speech) {
    // Сначала все поля, потом подписка на диктора: его первое же изменение (скорость)
    // читает музыку и тишину. Наоборот на iPhone падало, и звук не включался.
    _speed = _prefs.getDouble(_speedKey) ?? 1;
    _voiceId = _prefs.getString(_voiceKey);
    _voiceName = _prefs.getString(_voiceNameKey);
    _mix = AudioMix(
      musicOn: _prefs.getBool(_musicKey) ?? false,
      musicVolume: _prefs.getDouble(_musicVolumeKey) ?? 0.3,
    );
    _track = MusicTrack.byId(_prefs.getString(_trackKey));
    _voiceVolume = _prefs.getDouble(_voiceVolumeKey) ?? 1;
    for (final output in _voiceOutputs) {
      unawaited(output.setVolume(_voiceVolume));
    }
    sleep = SleepTimer(onFire: pause, onChange: notifyListeners);
    narrator
      ..setSpeed(_speed)
      ..addListener(_changed)
      ..onFinished = _chapterFinished;
  }

  /// Без звука (тесты): голос «читает», пока его не остановят.
  factory NarrationController.silent({String? startupError}) =>
      NarrationController(player: _SilentPlayer(), speech: _SilentSpeech())
        ..startupError = startupError;

  /// Звук не запустился на этом устройстве: почему (показывается во вкладке «Голоса»).
  String? startupError;

  static const _speedKey = 'narration.speed';
  static const _voiceKey = 'narration.voice';
  static const _voiceNameKey = 'narration.voiceName';
  static const _musicKey = 'narration.music';
  static const _musicVolumeKey = 'narration.musicVolume';
  static const _trackKey = 'narration.musicTrack';
  static const _voiceVolumeKey = 'narration.voiceVolume';
  static const _systemKey = 'narration.systemVoice';

  final Narrator narrator;
  final VoiceServerSettings _settings;
  final Prefs _prefs;
  final LoopPlayer? music;
  final LoopPlayer? silence;

  /// Папка кеша фраз; `null` — голос сервера без кеша на диске не включается.
  final Future<Directory>? cacheFolder;

  /// Держать приложение живым тишиной, пока голос ждёт фразу (iPhone, Android).
  final bool keepAwake;

  late final SleepTimer sleep;
  MediaSession? _media;
  BookStore? _store;

  Book? _book;
  int _chapter = 0;
  NarrationText? _text;

  /// Книга, которая играет или стоит на паузе; `null` — ничего не открыто.
  Book? get book => _book;
  int get chapterIndex => _chapter;
  Chapter? get chapter => _book?.chapters[_chapter];
  NarrationText? get text => _text;
  NarratorState get state => narrator.state;

  var _speed = 1.0;
  double get speed => _speed;

  // Сервер голоса.
  ServerLink? _link;
  VoiceServer? _server;
  PhraseCache? _cache;
  ServerState _serverState = ServerState.notSet;
  VoiceError? _serverError;
  List<VoiceInfo> _voices = const [];
  String? _voiceId;
  String? _voiceName;
  late bool _systemOnly = _prefs.getBool(_systemKey) ?? false;

  ServerLink? get serverLink => _link;
  ServerState get serverState => _serverState;
  VoiceError? get serverError => _serverError;
  List<VoiceInfo> get voices => _voices;
  String? get voiceId => _voiceId;

  /// Имя голоса для кнопки: голос сервера или «Системный».
  String get voiceName {
    if (_server == null || _systemOnly) return 'Системный голос';
    return _voiceName ?? _voiceId ?? 'Голос Lumen';
  }

  // Музыка.
  late AudioMix _mix;
  late MusicTrack _track;
  AudioMix get mix => _mix;
  MusicTrack get track => _track;
  double _musicLevel = 0;
  Timer? _fader;

  // Читатели, открытые на этой книге: они сами пишут место по прокрутке.
  final _readers = <String, int>{};
  Timer? _saveTimer;
  int? _savedOffset;
  bool _wasPlaying = false;
  bool _wasLoading = false;
  DateTime _shownAt = DateTime(0);

  /// Поднять голос сервера и экран блокировки. Вызывается один раз при запуске.
  Future<void> start({BookStore? store, MediaSession? media}) async {
    _store ??= store;
    _media = media;
    final link = await _settings
        .load()
        .timeout(const Duration(seconds: 5))
        .catchError((Object _) => null);
    if (link != null) await _useServer(link, check: true);
  }

  void attachStore(BookStore store) => _store ??= store;

  // ——— Книга и глава ———

  /// Открыть главу `index` с места `place` (то, где читатель остановился). Если эта глава
  /// уже играет, ничего не меняется.
  void open(Book book, int index, {ChapterPlace? place, int? offset}) {
    if (book.chapters.isEmpty) return;
    final i = index.clamp(0, book.chapters.length - 1);
    if (_book?.id == book.id && _chapter == i && _text != null) {
      _book = book;
      return;
    }
    _saveNow();
    _book = book;
    _chapter = i;
    final chapter = book.chapters[i];
    final text = _text = NarrationText(
      id: chapter.id,
      text: chapter.text,
      paragraphs: chapter.paragraphs,
    );
    final at = offset ?? offsetOfPlace(chapter, place);
    _savedOffset = at;
    narrator.load(text, offset: at.clamp(0, text.text.length));
    notifyListeners();
  }

  /// Перейти к другой главе этой книги и продолжить, если играла.
  void goToChapter(int index, {bool? play}) {
    final book = _book;
    if (book == null || index < 0 || index >= book.chapters.length) return;
    final playing = play ?? state.playing;
    _saveNow();
    _text = null;
    open(book, index, offset: 0);
    if (playing) this.play();
  }

  /// Закрыть книгу (крестик мини-плеера).
  void close() {
    pause();
    _saveNow();
    _book = null;
    _text = null;
    _media?.clear();
    notifyListeners();
  }

  void _chapterFinished() {
    final book = _book;
    if (book == null) return;
    _store?.saveProgress(book.id, _chapter, 1, place: null);
    final stop = sleep.chapterEnded();
    if (_chapter + 1 < book.chapters.length) {
      goToChapter(_chapter + 1, play: !stop);
    } else {
      notifyListeners();
    }
  }

  // ——— Кнопки ———

  @override
  void play() {
    if (_text == null) return;
    narrator.play();
  }

  @override
  void pause() {
    narrator.pause();
    _saveNow();
  }

  void toggle() => state.playing ? pause() : play();

  @override
  void skip(double seconds) => narrator.skip(seconds);

  @override
  void nextPhrase() => narrator.nextPhrase();

  @override
  void previousPhrase() => narrator.previousPhrase();

  /// Перейти к месту главы (например, нажатием на абзац).
  void jumpTo(int offset) => narrator.jumpTo(offset);

  /// Доля главы 0…1 (полоса прогресса).
  void seekFraction(double fraction) {
    final text = _text;
    if (text == null) return;
    narrator.jumpTo((text.text.length * fraction.clamp(0.0, 1.0)).floor());
  }

  @override
  void seekTo(Duration position) {
    final total = _chapterSeconds;
    if (total <= 0) return;
    seekFraction(position.inMilliseconds / 1000 / total);
  }

  void setSpeed(double speed) {
    _speed = speed;
    narrator.setSpeed(speed);
    _prefs.setDouble(_speedKey, speed);
    notifyListeners();
  }

  // ——— Сервер голоса и голос диктора ———

  /// Подключить сервер по ссылке из его окна. `null` — получилось, иначе текст ошибки.
  Future<VoiceError?> connect(String input) async {
    final link = ServerLink.parse(input);
    if (link == null) return const VoiceError(VoiceErrorKind.badAddress);
    if (cacheFolder == null) {
      return VoiceError(VoiceErrorKind.server, detail: startupError ?? 'звук не запустился');
    }
    final server = VoiceServer(link);
    try {
      final voices = await server.voices();
      await _settings.save(link);
      await _useServer(link, server: server, voices: voices);
      return null;
    } on VoiceError catch (error) {
      server.close();
      return error;
    }
  }

  /// Забыть сервер: дальше читает системный голос.
  Future<void> disconnect() async {
    await _settings.forget();
    _server?.close();
    _server = null;
    _link = null;
    _voices = const [];
    _serverState = ServerState.notSet;
    _serverError = null;
    narrator.setServer(null);
    notifyListeners();
  }

  /// Стереть озвученные фразы на этом устройстве: после обновления сервера (другая обработка
  /// звука) книга иначе звучала бы по-старому, пока фразы не вытеснятся из кеша.
  Future<void> clearVoiceCache() async {
    final folder = cacheFolder;
    if (folder == null) return;
    await (_cache ?? PhraseCache(await folder)).clear();
  }

  /// Проверить сервер ещё раз и обновить список голосов.
  Future<void> refreshServer() async {
    final link = _link;
    if (link != null) await _useServer(link, server: _server, check: true);
  }

  Future<void> _useServer(
    ServerLink link, {
    VoiceServer? server,
    List<VoiceInfo>? voices,
    bool check = false,
  }) async {
    final folder = cacheFolder;
    if (folder == null) return;
    _link = link;
    final made = server ?? VoiceServer(link);
    if (!identical(made, _server)) _server?.close();
    _server = made;
    _cache ??= PhraseCache(await folder);
    if (check) {
      try {
        voices = await made.voices();
      } on VoiceError catch (error) {
        _serverState = error.state;
        _serverError = error;
      }
    }
    if (voices != null) {
      _voices = voices;
      _serverState = ServerState.connected;
      _serverError = null;
      final known = voices.any((v) => v.id == _voiceId);
      if (!known && voices.isNotEmpty) _rememberVoice(voices.first);
    }
    _applyServer();
    notifyListeners();
  }

  void _applyServer() {
    final server = _server;
    final cache = _cache;
    final voice = _voiceId;
    narrator.setServer(
      server == null || cache == null || voice == null || _systemOnly
          ? null
          : ServerVoice(server: server, cache: cache, voice: voice),
    );
  }

  void _rememberVoice(VoiceInfo voice) {
    _voiceId = voice.id;
    _voiceName = voice.name;
    _prefs.setString(_voiceKey, voice.id);
    _prefs.setString(_voiceNameKey, voice.name);
  }

  /// Голос диктора для всех книг. Звучит со следующей фразы.
  void chooseVoice(VoiceInfo voice) {
    _rememberVoice(voice);
    _systemOnly = false;
    _prefs.setBool(_systemKey, false);
    _applyServer();
    notifyListeners();
  }

  /// Читать системным голосом, даже если сервер есть.
  void useSystemVoice() {
    _systemOnly = true;
    _prefs.setBool(_systemKey, true);
    _applyServer();
    notifyListeners();
  }

  /// Пользователь сам выбрал системный голос.
  bool get systemOnly => _systemOnly;

  // ——— Таймер сна ———

  void startSleep(Duration after) => sleep.start(after);
  void sleepAtChapterEnd() => sleep.startEndOfChapter();
  void cancelSleep() => sleep.cancel();

  // ——— Музыка ———

  void setMusic(bool on) {
    _mix = _mix.copyWith(musicOn: on);
    _prefs.setBool(_musicKey, on);
    _updateMusic();
    notifyListeners();
  }

  void setMusicVolume(double volume) {
    _mix = _mix.copyWith(musicVolume: volume);
    _prefs.setDouble(_musicVolumeKey, volume);
    _updateMusic();
    notifyListeners();
  }

  /// Громкость диктора (голос сервера и системный), отдельно от музыки.
  double get voiceVolume => _voiceVolume;
  late double _voiceVolume;
  final List<VoiceVolume> _voiceOutputs;

  void setVoiceVolume(double volume) {
    _voiceVolume = volume.clamp(0.0, 1.0);
    _prefs.setDouble(_voiceVolumeKey, _voiceVolume);
    for (final output in _voiceOutputs) {
      unawaited(output.setVolume(_voiceVolume));
    }
    notifyListeners();
  }

  void setTrack(MusicTrack track) {
    _track = track;
    _prefs.setString(_trackKey, track.id);
    if (_mix.musicOn && state.playing) unawaited(music?.play(track.asset));
    notifyListeners();
  }

  /// Музыка играет, пока играет книга; под голосом тише. Громкость меняется плавно.
  /// Приглушение держится всю озвучку, а не по фразам: иначе в паузе между фразами музыка
  /// на миг поднималась и снова опускалась, и на стыках слышался шум. Громче она становится,
  /// только пока голос ждёт сервер.
  void _updateMusic() {
    final player = music;
    if (player == null) return;
    double goal() =>
        _mix.musicOn && state.playing ? _mix.musicLevel(speaking: state.waiting == null) : 0;
    if (_mix.musicOn && state.playing) unawaited(player.play(_track.asset));
    if ((goal() - _musicLevel).abs() < 0.001) return;
    _fader ??= Timer.periodic(const Duration(milliseconds: 40), (timer) {
      final target = goal();
      _musicLevel += (target - _musicLevel).clamp(-0.03, 0.03);
      if ((target - _musicLevel).abs() < 0.001) {
        _musicLevel = target;
        timer.cancel();
        _fader = null;
        if (target == 0) unawaited(player.pause());
      }
      unawaited(player.setVolume(_musicLevel));
    });
  }

  /// Тишина под голосом сервера: иначе в паузах система усыпит приложение в фоне (PORTING.md).
  /// Играет всё время, пока книга играет, а не только между фразами: второй плеер, который
  /// включался и выключался на каждом стыке, давал щелчок и шум.
  void _updateSilence() {
    final player = silence;
    if (player == null || !keepAwake) return;
    final needed = state.playing && !(_mix.musicOn);
    if (needed) {
      unawaited(_silenceFile().then((path) => player.play(path, asset: false)));
    } else {
      unawaited(player.pause());
    }
  }

  String? _silencePath;
  Future<String> _silenceFile() async {
    final known = _silencePath;
    if (known != null) return known;
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}lumen_silence.wav');
    await file.writeAsBytes(silentWave(), flush: true);
    return _silencePath = file.path;
  }

  // ——— Место прослушивания ———

  /// Экран текста этой книги открыт: место пишет он (по прокрутке, которая идёт за голосом).
  void attachReader(String bookId) => _readers[bookId] = (_readers[bookId] ?? 0) + 1;

  void detachReader(String bookId) {
    final n = (_readers[bookId] ?? 1) - 1;
    if (n <= 0) {
      _readers.remove(bookId);
    } else {
      _readers[bookId] = n;
    }
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final book = _book;
    final text = _text;
    final store = _store;
    if (book == null || text == null || store == null) return;
    if (_readers.containsKey(book.id)) return;
    final offset = state.offset;
    if (offset == _savedOffset) return;
    _savedOffset = offset;
    final chapter = book.chapters[_chapter];
    store.saveProgress(
      book.id,
      _chapter,
      text.progressAt(offset),
      place: placeOfOffset(chapter, offset),
    );
  }

  // ——— Изменения диктора ———

  double get _chapterSeconds {
    final text = _text;
    if (text == null) return 0;
    return SpeechText.estimatedSeconds(text.sentences);
  }

  /// Слово под голосом: меняется несколько раз в секунду, поэтому отдельно от остального.
  /// Экраны, которым не нужна подсветка, слушают только сам контроллер.
  final live = ValueNotifier<NarratorState>(const NarratorState());

  Object? _coarse;

  void _changed() {
    final s = state;
    if (s.playing && _saveTimer == null) {
      _saveTimer = Timer(const Duration(seconds: 5), _saveNow);
    }
    _updateMusic();
    _updateSilence();
    _showMedia();
    live.value = s;
    final coarse = (s.playing, s.loading, s.sounding, s.engine, s.waiting, s.fallback, s.speed);
    if (coarse != _coarse) {
      _coarse = coarse;
      notifyListeners();
    }
  }

  void _showMedia() {
    final media = _media;
    final book = _book;
    final text = _text;
    if (media == null || book == null || text == null) return;
    final s = state;
    final now = DateTime.now();
    final changed = s.playing != _wasPlaying || s.loading != _wasLoading;
    if (!changed && now.difference(_shownAt) < const Duration(seconds: 5)) return;
    _wasPlaying = s.playing;
    _wasLoading = s.loading;
    _shownAt = now;
    final total = _chapterSeconds;
    media.show(
      NowPlaying(
        id: text.id,
        title: book.chapters[_chapter].title,
        book: book.title,
        author: book.author,
        cover: book.coverPath,
        playing: s.playing,
        loading: s.loading,
        position: Duration(milliseconds: (total * text.progressAt(s.offset) * 1000).round()),
        duration: Duration(milliseconds: (total * 1000).round()),
        speed: _speed,
      ),
    );
  }

  @override
  void dispose() {
    _saveNow();
    _fader?.cancel();
    _saveTimer?.cancel();
    sleep.dispose();
    narrator.dispose();
    live.dispose();
    _server?.close();
    super.dispose();
  }
}

/// Место в главе (как его пишет экран текста) → место в тексте для голоса.
int offsetOfPlace(Chapter chapter, ChapterPlace? place) {
  if (place == null || chapter.paragraphs.isEmpty) return 0;
  final items = chapterItems(chapter);
  if (items.isEmpty) return 0;
  var i = place.item.clamp(0, items.length - 1);
  var within = place.within;
  // Картинка: голос начинает со следующего абзаца.
  while (i < items.length && items[i] is! ParagraphItem) {
    i++;
    within = 0;
  }
  if (i >= items.length) return chapter.text.length;
  final paragraph = chapter.paragraphs[(items[i] as ParagraphItem).index];
  return paragraph.start + (within.clamp(0.0, 1.0) * paragraph.length).floor();
}

/// Место в тексте → место для экрана текста (абзац и доля его высоты).
ChapterPlace? placeOfOffset(Chapter chapter, int offset) {
  if (chapter.paragraphs.isEmpty) return null;
  var p = 0;
  for (var i = 0; i < chapter.paragraphs.length; i++) {
    if (chapter.paragraphs[i].start <= offset) p = i;
  }
  final items = chapterItems(chapter);
  final item = items.indexWhere((it) => it is ParagraphItem && it.index == p);
  if (item < 0) return null;
  final range = chapter.paragraphs[p];
  final within = range.length == 0 ? 0.0 : ((offset - range.start) / range.length).clamp(0.0, 1.0);
  return ChapterPlace(item: item, within: within);
}

final class _SilentPlayer implements PhrasePlayer {
  Completer<bool>? _done;

  @override
  Future<bool> play(PhraseAudio audio, {Duration from = Duration.zero, double speed = 1}) =>
      (_done = Completer<bool>()).future;

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> stop() async {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete(false);
  }
}

final class _SilentSpeech implements SystemSpeech {
  Completer<bool>? _done;

  @override
  Future<bool> speak(
    String text, {
    String? language,
    double speed = 1,
    void Function(int start, int end)? onWord,
  }) => (_done = Completer<bool>()).future;

  @override
  Future<void> stop() async {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete(false);
  }
}
