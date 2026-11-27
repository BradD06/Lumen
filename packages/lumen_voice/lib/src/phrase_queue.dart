import 'dart:async';

import 'phrase_cache.dart';
import 'speech_text.dart';
import 'voice_error.dart';

/// Как получить звук части: обычно кеш + сервер (`PhraseQueue.forServer`).
typedef PhraseLoader = Future<PhraseAudio> Function(SpeechPart part);

/// Очередь озвучки: пока звучит фраза, следующие готовятся заранее, поэтому между ними нет
/// пауз. Сервер голоса готовит несколько частей разом быстрее, чем по одной, поэтому
/// `lookahead` частей просятся сразу.
///
/// Каждая `take` — переход: ответ для старого перехода приходит как `null` и ничего не
/// включит (опоздавшие загрузки). Начатая загрузка не отменяется, она всё равно ляжет в кеш.
/// Временный сбой (сеть моргнула, сервер запускается) — `onWaiting`, очередь ждёт и пробует
/// снова около минуты; потом ошибка уходит наверх, и плеер переходит на системный голос.
final class PhraseQueue {
  PhraseQueue({
    required this.load,
    this.lookahead = 3,
    this.retryDelays = defaultRetryDelays,
    Future<void> Function(Duration)? sleep,
    this.onWaiting,
    this.onLoading,
  }) : _sleep = sleep ?? Future<void>.delayed;

  static const defaultRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  /// Как получить звук части.
  final PhraseLoader load;
  final Future<void> Function(Duration) _sleep;

  /// Сколько следующих частей готовить, пока звучит эта.
  final int lookahead;
  final List<Duration> retryDelays;

  /// Сбой временный, очередь ждёт и пробует снова.
  final void Function(VoiceError error)? onWaiting;

  /// Звук текущей части ещё не готов (`true`) или уже пришёл (`false`): плеер показывает,
  /// что фраза готовится, а не зависла.
  final void Function(bool loading)? onLoading;

  List<SpeechPart> _parts = const [];
  final _loads = <int, Future<PhraseAudio>>{};
  var _generation = 0;

  List<SpeechPart> get parts => _parts;

  /// Растёт при каждом переходе.
  int get generation => _generation;

  /// Новые части (другая глава, другое место старта). Та же глава — готовые загрузки остаются.
  void start(List<SpeechPart> parts) {
    final same = _sameParts(parts, _parts);
    _parts = List.unmodifiable(parts);
    _generation++;
    if (!same) _loads.clear();
  }

  /// Сменили голос: всё приготовленное не годится, со следующей `take` — новый голос.
  void invalidate() {
    _generation++;
    _loads.clear();
  }

  /// Звук части `index`, заодно просит следующие. `null` — пока ждали, был другой переход.
  Future<PhraseAudio?> take(int index) async {
    if (index < 0 || index >= _parts.length) return null;
    final generation = ++_generation;
    _forget(index);
    final current = _ensure(index);
    for (var i = index + 1; i <= index + lookahead && i < _parts.length; i++) {
      _ensure(i);
    }
    onLoading?.call(true);
    try {
      final audio = await current;
      return generation == _generation ? audio : null;
    } finally {
      if (generation == _generation) onLoading?.call(false);
    }
  }

  /// Уже приготовленные части не держим вечно: только текущая и следующие.
  void _forget(int index) {
    _loads.removeWhere((i, _) => i < index || i > index + lookahead);
  }

  Future<PhraseAudio> _ensure(int index) {
    final running = _loads[index];
    if (running != null) return running;
    final part = _parts[index];
    final future = _withRetries(part);
    _loads[index] = future;
    // Сбой загрузки, которую никто не ждёт, не должен ронять приложение; провалившуюся
    // загрузку забываем, чтобы следующая `take` попробовала снова.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_loads[index], future)) _loads.remove(index);
        },
      ),
    );
    return future;
  }

  Future<PhraseAudio> _withRetries(SpeechPart part) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await load(part);
      } on VoiceError catch (error) {
        if (!error.isTemporary || attempt >= retryDelays.length) rethrow;
        onWaiting?.call(error);
        await _sleep(retryDelays[attempt]);
      }
    }
  }

  static bool _sameParts(List<SpeechPart> a, List<SpeechPart> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
