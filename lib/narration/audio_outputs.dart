import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lumen_player/lumen_player.dart';
import 'package:lumen_voice/lumen_voice.dart';

/// Громкость голоса диктора, отдельно от музыки на фоне.
abstract interface class VoiceVolume {
  /// 0…1, 1 — как есть.
  Future<void> setVolume(double volume);
}

/// Фразы голоса сервера через just_audio (на Windows — just_audio_windows).
/// Звук фразы пишется во временный файл: так он одинаково играет на всех системах.
final class JustAudioPhrasePlayer implements PhrasePlayer, VoiceVolume {
  JustAudioPhrasePlayer(this._folder);

  final Future<Directory> _folder;
  final _player = AudioPlayer();
  var _file = 0;
  double _volume = 1;
  Timer? _ramp;

  /// Фраза входит и выходит за [_fade]: без щелчка на стыке с соседней.
  static const _fade = Duration(milliseconds: 60);

  /// Плавно довести громкость до `to` за [_fade] (несколько шагов).
  Future<void> _rampTo(double to, {required double from}) {
    _ramp?.cancel();
    const steps = 6;
    final done = Completer<void>();
    var step = 0;
    unawaited(_player.setVolume(from));
    _ramp = Timer.periodic(_fade ~/ steps, (timer) {
      step++;
      unawaited(_player.setVolume(from + (to - from) * step / steps));
      if (step >= steps) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }

  Completer<bool>? _done;
  StreamSubscription<PlayerState>? _states;

  void _finish(bool value) {
    final done = _done;
    _done = null;
    _states?.cancel();
    _states = null;
    if (done != null && !done.isCompleted) done.complete(value);
  }

  @override
  Future<bool> play(PhraseAudio audio, {Duration from = Duration.zero, double speed = 1}) async {
    _finish(false);
    final done = _done = Completer<bool>();
    try {
      final folder = await _folder;
      // Четыре файла по кругу: следующая фраза не пишется поверх звучащей.
      final file = File(
        '${folder.path}${Platform.pathSeparator}phrase_${_file++ % 4}.${audio.extension}',
      );
      await file.writeAsBytes(audio.data, flush: true);
      if (done.isCompleted) return await done.future;
      await _player.setFilePath(file.path, initialPosition: from);
      await _player.setSpeed(speed);
    } catch (error) {
      // Битый звук одной фразы не должен останавливать книгу: дальше следующая.
      debugPrint('Фраза не играет: $error');
      if (identical(_done, done)) _finish(true);
      return done.future;
    }
    if (done.isCompleted) return done.future;
    var started = false;
    _states = _player.playerStateStream.listen((state) {
      if (!identical(_done, done)) return;
      if (state.processingState == ProcessingState.completed) {
        _finish(true);
      } else if (state.playing) {
        if (!started) unawaited(_rampTo(_volume, from: 0));
        started = true;
      } else if (started && state.processingState == ProcessingState.ready) {
        // Систему прервали (звонок, другое приложение): пауза.
        _finish(false);
      }
    });
    _ramp?.cancel();
    await _player.setVolume(0);
    unawaited(_player.play());
    return done.future;
  }

  @override
  Duration get position => _player.position;

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_ramp?.isActive != true && _player.playing) await _player.setVolume(_volume);
  }

  @override
  Future<void> stop() async {
    _finish(false);
    if (_player.playing) await _rampTo(0, from: _player.volume);
    await _player.pause();
  }

  Future<void> dispose() {
    _ramp?.cancel();
    return _player.dispose();
  }
}

/// Системный голос через flutter_tts: AVSpeechSynthesizer на Mac и iPhone, TextToSpeech
/// на Android, голоса Windows.
final class FlutterSystemSpeech implements SystemSpeech, VoiceVolume {
  final _tts = FlutterTts();
  Future<void>? _setup;
  Completer<bool>? _done;
  void Function(int start, int end)? _onWord;
  var _started = false;
  String? _language;
  double? _rate;
  double _volume = 1;
  double? _setVolume;

  @override
  Future<void> setVolume(double volume) async => _volume = volume.clamp(0.0, 1.0);

  Future<void> _prepare() => _setup ??= () async {
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.allowAirPlay,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ], IosTextToSpeechAudioMode.spokenAudio);
    }
    await _tts.awaitSpeakCompletion(false);
    // Конец старой фразы может прийти после начала новой: слушаем только начатую.
    _tts.setStartHandler(() => _started = true);
    _tts.setCompletionHandler(() => _complete(true));
    _tts.setCancelHandler(() => _complete(false));
    // Ошибка на одной фразе — дальше следующая.
    _tts.setErrorHandler((_) => _complete(true, force: true));
    _tts.setProgressHandler((_, start, end, _) => _onWord?.call(start, end));
  }();

  void _complete(bool value, {bool force = false}) {
    final done = _done;
    if (done == null || done.isCompleted || (!_started && !force)) return;
    _done = null;
    done.complete(value);
  }

  /// Скорость 1× для каждой системы своя.
  static double _rateFor(double speed) {
    if (Platform.isIOS || Platform.isMacOS) return (0.5 * speed).clamp(0.1, 1.0);
    if (Platform.isWindows) return (speed - 0.5).clamp(0.0, 5.5);
    return speed;
  }

  static String _locale(String? language) => switch (language) {
    'en' => 'en-US',
    'uk' => 'uk-UA',
    'de' => 'de-DE',
    'fr' => 'fr-FR',
    'es' => 'es-ES',
    'it' => 'it-IT',
    'pt' => 'pt-PT',
    'pl' => 'pl-PL',
    'ja' => 'ja-JP',
    'zh' => 'zh-CN',
    'ko' => 'ko-KR',
    _ => 'ru-RU',
  };

  @override
  Future<bool> speak(
    String text, {
    String? language,
    double speed = 1,
    void Function(int start, int end)? onWord,
  }) async {
    await _prepare();
    final old = _done;
    if (old != null && !old.isCompleted) old.complete(false);
    final done = _done = Completer<bool>();
    _onWord = onWord;
    _started = false;
    try {
      if (language != _language) {
        _language = language;
        await _tts.setLanguage(_locale(language));
      }
      final rate = _rateFor(speed);
      if (rate != _rate) {
        _rate = rate;
        await _tts.setSpeechRate(rate);
      }
      if (_volume != _setVolume) {
        _setVolume = _volume;
        await _tts.setVolume(_volume);
      }
      if (done.isCompleted) return await done.future;
      await _tts.speak(text);
    } catch (error) {
      debugPrint('Системный голос: $error');
      if (!done.isCompleted) done.complete(true);
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    final done = _done;
    _done = null;
    _onWord = null;
    if (done != null && !done.isCompleted) done.complete(false);
    if (_setup != null) await _tts.stop();
  }
}

/// Зацикленный звук: фоновая музыка или тишина, которая держит приложение живым в фоне,
/// пока голос сервера готовит фразу (iPhone и Android иначе усыпляют приложение).
final class LoopPlayer {
  LoopPlayer();

  final _player = AudioPlayer();
  String? _source;
  double _volume = -1;

  Future<void> _load(String source, {required bool asset}) async {
    if (_source == source) return;
    _source = source;
    if (asset) {
      await _player.setAsset(source);
    } else {
      await _player.setFilePath(source);
    }
    await _player.setLoopMode(LoopMode.one);
  }

  /// Играть `source` по кругу (ассет приложения или файл).
  Future<void> play(String source, {bool asset = true}) async {
    try {
      await _load(source, asset: asset);
      if (_volume < 0) await setVolume(0);
      if (!_player.playing) unawaited(_player.play());
    } catch (error) {
      debugPrint('Звук по кругу не играет: $error');
    }
  }

  Future<void> pause() async {
    if (_player.playing) await _player.pause();
  }

  Future<void> setVolume(double volume) async {
    if ((volume - _volume).abs() < 0.005) return;
    _volume = volume;
    await _player.setVolume(volume);
  }

  Future<void> dispose() => _player.dispose();
}

/// Секунда тишины в wav: её играет `LoopPlayer`, пока голос ждёт фразу.
Uint8List silentWave({int rate = 24000, double seconds = 1}) {
  final samples = (rate * seconds).round();
  final data = samples * 2;
  final bytes = ByteData(44 + data);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + data, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, data, Endian.little);
  return bytes.buffer.asUint8List();
}
