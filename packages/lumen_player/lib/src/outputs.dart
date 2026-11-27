import 'package:lumen_voice/lumen_voice.dart';

/// Звук фразы с сервера голоса. В приложении — just_audio (`lib/narration/audio_outputs.dart`),
/// в тестах — подделка.
abstract interface class PhrasePlayer {
  /// Играть фразу с секунды `from`. Готово `true`, когда фраза доиграла до конца, и `false`,
  /// когда её остановили (`stop`, новая `play`) или система прервала звук.
  Future<bool> play(PhraseAudio audio, {Duration from = Duration.zero, double speed = 1});

  /// Где звук сейчас (время самой записи, скорость на него не влияет).
  Duration get position;

  Future<void> setSpeed(double speed);

  /// Остановить: незаконченная `play` отдаёт `false`.
  Future<void> stop();
}

/// Системный голос телефона или компьютера: запасной, работает без сервера.
abstract interface class SystemSpeech {
  /// Сказать `text`. `true` — договорил, `false` — остановили. `onWord` получает места слова
  /// в `text` (UTF-16), если система их сообщает; иначе плеер раскладывает слова по времени.
  Future<bool> speak(
    String text, {
    String? language,
    double speed = 1,
    void Function(int start, int end)? onWord,
  });

  Future<void> stop();
}

/// Голос с сервера для диктора: сервер, кеш фраз и id голоса.
final class ServerVoice {
  const ServerVoice({required this.server, required this.cache, required this.voice});

  final VoiceServer server;
  final PhraseCache cache;
  final String voice;
}
