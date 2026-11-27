import 'dart:async';

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_voice/lumen_voice.dart';

import 'outputs.dart';

/// Кто сейчас читает.
enum VoiceEngine {
  /// Голос Lumen с сервера.
  server,

  /// Системный голос: запасной, без сервера.
  system,
}

/// Что видно на экране: играет ли, что звучит, почему читает системный голос.
final class NarratorState {
  const NarratorState({
    this.playing = false,
    this.loading = false,
    this.sounding = false,
    this.engine = VoiceEngine.system,
    this.offset = 0,
    this.word,
    this.sentence,
    this.speed = 1,
    this.waiting,
    this.fallback,
  });

  /// Пользователь нажал «Слушать» (а не паузу).
  final bool playing;

  /// Голос сервера ещё готовит фразу.
  final bool loading;

  /// Голос звучит прямо сейчас: под ним приглушается музыка.
  final bool sounding;
  final VoiceEngine engine;

  /// Место в главе (UTF-16): начало звучащего слова.
  final int offset;

  /// Звучащее слово и его предложение в главе.
  final TextRange? word;
  final TextRange? sentence;
  final double speed;

  /// Связь моргнула: голос ждёт сервер и пробует снова.
  final VoiceError? waiting;

  /// Почему читает системный голос, хотя сервер задан; `null` — так и задумано.
  final VoiceError? fallback;

  NarratorState copyWith({
    bool? playing,
    bool? loading,
    bool? sounding,
    VoiceEngine? engine,
    int? offset,
    TextRange? word,
    TextRange? sentence,
    double? speed,
    VoiceError? waiting,
    VoiceError? fallback,
    bool clearWord = false,
    bool clearWaiting = false,
    bool clearFallback = false,
  }) => NarratorState(
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    sounding: sounding ?? this.sounding,
    engine: engine ?? this.engine,
    offset: offset ?? this.offset,
    word: clearWord ? null : (word ?? this.word),
    sentence: clearWord ? null : (sentence ?? this.sentence),
    speed: speed ?? this.speed,
    waiting: clearWaiting ? null : (waiting ?? this.waiting),
    fallback: clearFallback ? null : (fallback ?? this.fallback),
  );
}

/// Диктор: читает одну главу (`NarrationText`) голосом сервера, а без него — системным.
///
/// Голос сервера читает частями с разгоном (`NarrationText.serverParts`): первая фраза
/// быстро, дальше абзацами; пока звучит часть, следующие готовятся (`PhraseQueue`). Сбой,
/// который не прошёл за минуту, или неподходящий ключ — дальше читает системный голос, а
/// голос сервера возвращается сам, когда сервер снова отвечает.
///
/// Каждая пауза, переход и новая глава — новый «проход» (`_run`): старый цикл, дождавшись
/// своего звука, видит чужой номер и молча выходит (опоздавшие загрузки).
final class Narrator {
  Narrator({
    required this._player,
    required this._speech,
    this.tick = const Duration(milliseconds: 50),
    this.serverCheck = const Duration(seconds: 20),
    this.paragraphPause = const Duration(milliseconds: 600),
    this.sentencePause = const Duration(milliseconds: 150),
  });

  final PhrasePlayer _player;
  final SystemSpeech _speech;

  /// Как часто подсветка смотрит, какое слово звучит.
  final Duration tick;

  /// Как часто после сбоя проверять, ожил ли сервер.
  final Duration serverCheck;

  /// Пауза голоса сервера между абзацами, сверх тишины в конце самой фразы. Как у дикторов
  /// аудиокниг (в ElevenReader между абзацами 0,9–1,5 с, между предложениями 0,4–0,6 с):
  /// без неё абзацы шли подряд, будто одно длинное предложение.
  final Duration paragraphPause;

  /// Пауза между частями одного абзаца (в начале чтения части идут по предложению).
  final Duration sentencePause;

  /// Пауза перед частью `next`: между абзацами длиннее, внутри абзаца короче.
  Duration _pauseBefore(int next) {
    final text = _text?.text;
    if (text == null || next <= 0 || next >= _parts.length) return Duration.zero;
    final from = _parts[next - 1].end.clamp(0, text.length);
    final to = _parts[next].start.clamp(from, text.length);
    return text.substring(from, to).contains('\n') ? paragraphPause : sentencePause;
  }

  /// Глава дочитана до конца.
  void Function()? onFinished;

  var _state = const NarratorState();
  NarratorState get state => _state;

  final _listeners = <void Function()>[];
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  NarrationText? _text;
  NarrationText? get text => _text;

  ServerVoice? _server;
  PhraseQueue? _queue;

  /// Сервер не ответил: читает системный голос, пока он не оживёт.
  var _serverDown = false;
  Timer? _watch;

  List<SpeechPart> _parts = const [];
  var _index = 0;

  /// С какого места начать часть `_index` (внутри части голоса сервера).
  int? _startAt;
  var _run = 0;

  /// Сейчас звучащая часть и её слова.
  SpokenPart? _spoken;
  double? _audioSeconds;
  Stopwatch? _clock;
  TextRange? _systemWord;
  Timer? _ticker;

  bool get _wantServer => _server != null && !_serverDown && (_text?.serverVoiceSupports ?? false);

  /// Части, которыми сейчас читается глава.
  List<SpeechPart> get parts => _parts;

  void _set(NarratorState value) {
    _state = value;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Голос сервера; `null` — только системный голос. Другой голос того же сервера
  /// звучит со следующей фразы, без остановки.
  void setServer(ServerVoice? voice) {
    final old = _server;
    _server = voice;
    if (old != null &&
        voice != null &&
        identical(old.server, voice.server) &&
        identical(old.cache, voice.cache)) {
      if (old.voice != voice.voice) _queue?.invalidate();
      return;
    }
    _serverDown = false;
    _watch?.cancel();
    _makeQueue();
    _set(_state.copyWith(clearFallback: true, clearWaiting: true));
    // Сервер появился или пропал: та же глава с того же места другим голосом.
    if (_text != null) _relayout(_state.offset);
  }

  void _makeQueue() {
    final voice = _server;
    _queue = voice == null
        ? null
        : serverPhraseQueue(
            server: voice.server,
            cache: voice.cache,
            voice: () => _server?.voice ?? voice.voice,
            language: _text?.language,
            onWaiting: _onWaiting,
            onLoading: _onLoading,
          );
  }

  /// Новая глава с места `offset`. Не включает звук сама.
  void load(NarrationText text, {int offset = 0}) {
    _halt();
    _text = text;
    _serverDown = false;
    _watch?.cancel();
    // Язык новой главы может быть другим.
    _makeQueue();
    _set(_state.copyWith(playing: false, clearFallback: true, clearWaiting: true));
    _relayout(offset);
  }

  /// Части заново с места `offset` (голос сервера: новый разгон).
  void _relayout(int offset) {
    final text = _text!;
    final wasPlaying = _state.playing;
    _halt();
    final server = _wantServer;
    if (server) {
      _parts = text.serverParts(offset);
      _queue!.start(_parts);
    } else {
      _parts = text.sentences;
    }
    _index = SpeechText.indexOf(offset, _parts) ?? _parts.length;
    _startAt = offset;
    _set(
      _state.copyWith(
        engine: server ? VoiceEngine.server : VoiceEngine.system,
        offset: offset,
        clearWord: true,
        loading: false,
        sounding: false,
      ),
    );
    _markSentence(offset);
    if (wasPlaying) play();
  }

  /// Сразу подсветить предложение под местом, ещё до звука.
  void _markSentence(int offset) {
    final text = _text;
    if (text == null) return;
    final i = SpeechText.indexOf(offset, text.sentences);
    if (i == null) return;
    final sentence = text.sentences[i];
    _set(_state.copyWith(sentence: sentence.range));
  }

  void play() {
    if (_text == null) return;
    if (_index >= _parts.length) {
      // Дослушано до конца: «Слушать» начинает главу сначала.
      _relayout(0);
    }
    final run = ++_run;
    _set(_state.copyWith(playing: true));
    _startTicker();
    unawaited(_loop(run));
  }

  void pause() {
    if (!_state.playing) return;
    _halt();
    _set(_state.copyWith(playing: false, loading: false, sounding: false));
  }

  void toggle() => _state.playing ? pause() : play();

  /// Остановить звук и текущий проход; место остаётся.
  void _halt() {
    _run++;
    _ticker?.cancel();
    _ticker = null;
    final at = _state.offset;
    // Продолжим с того же слова (голос сервера) или с начала предложения (системный).
    if (_index < _parts.length) _startAt = at;
    unawaited(_player.stop());
    unawaited(_speech.stop());
  }

  void setSpeed(double speed) {
    _set(_state.copyWith(speed: speed));
    if (_state.engine == VoiceEngine.server) unawaited(_player.setSpeed(speed));
    // Системный голос — со следующего предложения.
  }

  /// Перейти к месту главы. Рядом — те же части (они уже готовятся), далеко — новый разгон.
  void jumpTo(int offset) {
    final text = _text;
    if (text == null) return;
    final target = offset.clamp(0, text.text.length);
    final wasPlaying = _state.playing;
    final index = SpeechText.indexOf(target, _parts);
    final near = index != null && index >= _index - 1 && index <= _index + 3;
    if (_state.engine == VoiceEngine.server && !near) {
      _relayout(target);
      return;
    }
    _halt();
    _index = index ?? _parts.length;
    _startAt = target;
    _set(_state.copyWith(offset: target, clearWord: true, loading: false, sounding: false));
    _markSentence(target);
    if (wasPlaying) play();
  }

  /// Следующее предложение.
  void nextPhrase() {
    final sentences = _text?.sentences ?? const [];
    final i = SpeechText.indexOf(_state.offset, sentences);
    if (i == null || i + 1 >= sentences.length) return;
    jumpTo(sentences[i + 1].start);
  }

  /// Начало предложения, а если оно только началось — предыдущее.
  void previousPhrase() {
    final sentences = _text?.sentences ?? const [];
    final i = SpeechText.indexOf(_state.offset, sentences);
    if (i == null) {
      if (sentences.isNotEmpty) jumpTo(sentences.last.start);
      return;
    }
    final into = _state.offset - sentences[i].start;
    jumpTo(into > 12 || i == 0 ? sentences[i].start : sentences[i - 1].start);
  }

  /// Назад или вперёд на `seconds` секунд записи.
  void skip(double seconds) {
    final text = _text;
    if (text == null) return;
    // Внутри звучащей части голоса сервера время точное.
    final spoken = _spoken;
    final length = _audioSeconds;
    if (_state.engine == VoiceEngine.server && spoken != null && length != null) {
      final now = _player.position.inMilliseconds / 1000;
      final target = now + seconds;
      if (target >= 0 && target < length) {
        jumpTo(spoken.placeAt(target < 0.05 ? 0 : target - SpeechTiming.wordLead));
        return;
      }
    }
    jumpTo(_offsetAfter(text, _state.offset, seconds));
  }

  /// Место через `seconds` секунд речи от `offset` (по прикидке длительности предложений).
  static int _offsetAfter(NarrationText text, int offset, double seconds) {
    final sentences = text.sentences;
    if (sentences.isEmpty) return 0;
    var i = SpeechText.indexOf(offset, sentences) ?? sentences.length - 1;
    double length(SpeechPart p) => SpeechText.estimatedSeconds([p]);
    final s = sentences[i];
    var into = s.length == 0 ? 0.0 : length(s) * ((offset - s.start) / s.length).clamp(0.0, 1.0);
    var left = into + seconds;
    if (seconds >= 0) {
      while (i < sentences.length - 1 && left >= length(sentences[i])) {
        left -= length(sentences[i]);
        i++;
      }
    } else {
      while (i > 0 && left < 0) {
        i--;
        left += length(sentences[i]);
      }
      if (left < 0) left = 0;
    }
    final at = sentences[i];
    final share = (left / length(at)).clamp(0.0, 1.0);
    // Слово внутри предложения; системный голос всё равно начнёт с начала предложения.
    return at.start + (share * at.length).floor();
  }

  Future<void> _loop(int run) async {
    while (run == _run) {
      if (_index >= _parts.length) {
        _finish();
        return;
      }
      final part = _parts[_index];
      final from = _startAt;
      _startAt = null;
      final bool done;
      if (_state.engine == VoiceEngine.server) {
        final PhraseAudio? audio;
        try {
          audio = await _queue!.take(_index);
        } on VoiceError catch (error) {
          if (run != _run) return;
          _fallBack(error, part.start);
          continue;
        }
        if (run != _run || audio == null) return;
        final spoken = SpokenPart(part, audio.words, duration: audio.duration);
        _spoken = spoken;
        _audioSeconds = audio.duration ?? SpeechText.estimatedSeconds([part]);
        final at = from == null ? 0.0 : _timeOf(spoken, from);
        _set(_state.copyWith(loading: false, sounding: true, clearWaiting: true));
        done = await _player.play(
          audio,
          from: Duration(milliseconds: (at * 1000).round()),
          speed: _state.speed,
        );
      } else {
        final spoken = SpokenPart(part, null);
        _spoken = spoken;
        _audioSeconds = null;
        _systemWord = null;
        _clock = Stopwatch()..start();
        _set(_state.copyWith(loading: false, sounding: true));
        done = await _speech.speak(
          part.spoken,
          language: _text?.language,
          speed: _state.speed,
          onWord: (start, end) {
            if (run == _run && end > start) _systemWord = TextRange(start, end - start);
          },
        );
      }
      if (run != _run) return;
      if (!done) {
        // Звук прервала система (звонок, другое приложение): пауза на этом месте.
        _halt();
        _set(_state.copyWith(playing: false, sounding: false));
        return;
      }
      _index++;
      _spoken = null;
      _set(_state.copyWith(sounding: false));
      if (_state.engine == VoiceEngine.server) {
        final pause = _pauseBefore(_index);
        if (pause > Duration.zero) {
          await Future<void>.delayed(pause);
          if (run != _run) return;
        }
      }
      // Сервер ожил, пока читал системный голос: со следующего предложения — снова он.
      if (_state.engine == VoiceEngine.system && _wantServer && _index < _parts.length) {
        _relayout(_parts[_index].start);
        return;
      }
    }
  }

  /// Секунда, с которой в звуке части начинается слово на месте `offset`.
  static double _timeOf(SpokenPart spoken, int offset) {
    if (offset <= spoken.part.start) return 0;
    for (final word in spoken.words) {
      final range = SpeechTiming.chapterRange(word.range, spoken.places);
      if (range != null && range.end > offset) return word.time;
    }
    return 0;
  }

  void _finish() {
    _ticker?.cancel();
    _ticker = null;
    _spoken = null;
    final end = _text?.text.length ?? 0;
    _set(
      _state.copyWith(
        playing: false,
        loading: false,
        sounding: false,
        offset: end,
        clearWord: true,
      ),
    );
    onFinished?.call();
  }

  /// Сервер не помог: дальше читает системный голос с начала этой части.
  void _fallBack(VoiceError error, int at) {
    _serverDown = true;
    _parts = _text!.sentences;
    _index = SpeechText.indexOf(at, _parts) ?? _parts.length;
    _startAt = at;
    _set(
      _state.copyWith(
        engine: VoiceEngine.system,
        fallback: error,
        loading: false,
        clearWaiting: true,
      ),
    );
    // Неподходящий ключ сам не исправится; остальное проверяем, пока сервер не ответит.
    if (error.kind != VoiceErrorKind.wrongKey) _watchServer();
  }

  void _watchServer() {
    _watch?.cancel();
    final server = _server?.server;
    if (server == null) return;
    var asking = false;
    _watch = Timer.periodic(serverCheck, (_) async {
      if (asking) return;
      asking = true;
      final alive = await server.isAlive();
      asking = false;
      if (!alive || !identical(_server?.server, server)) return;
      _watch?.cancel();
      _serverDown = false;
      _set(_state.copyWith(clearFallback: true));
      // Если книга стоит на паузе, голос сервера начнёт со следующего «Слушать».
      if (!_state.playing) _relayout(_state.offset);
    });
  }

  void _onWaiting(Object error) {
    if (error is VoiceError) _set(_state.copyWith(waiting: error));
  }

  void _onLoading(bool loading) {
    if (_state.engine != VoiceEngine.server) return;
    _set(_state.copyWith(loading: loading, sounding: loading ? false : null));
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(tick, (_) => _follow());
  }

  /// Какое слово звучит: по месту звука (сервер) или по словам и часам (системный голос).
  void _follow() {
    final spoken = _spoken;
    final text = _text;
    if (spoken == null || text == null || !_state.sounding) return;
    TextRange? word;
    if (_state.engine == VoiceEngine.server) {
      word = spoken.wordAt(_player.position.inMilliseconds / 1000);
    } else {
      final said = _systemWord;
      if (said != null) {
        word = SpeechTiming.chapterRange(said, spoken.places);
      } else {
        final elapsed = (_clock?.elapsedMilliseconds ?? 0) / 1000 * _state.speed;
        word = spoken.wordAt(elapsed);
      }
    }
    if (word == null || word == _state.word) return;
    final sentence = SpeechText.sentenceAt(word.start, spoken.part, text.sentences);
    _set(_state.copyWith(word: word, sentence: sentence, offset: word.start));
  }

  void dispose() {
    _halt();
    _watch?.cancel();
    _listeners.clear();
  }
}
