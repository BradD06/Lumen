import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Что показать на экране блокировки и в центре управления.
@immutable
class NowPlaying {
  const NowPlaying({
    required this.id,
    required this.title,
    required this.book,
    this.author,
    this.cover,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration,
    this.speed = 1,
  });

  final String id;

  /// Глава.
  final String title;
  final String book;
  final String? author;
  final String? cover;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration? duration;
  final double speed;
}

/// Кнопки экрана блокировки, наушников и центра управления.
abstract interface class MediaCommands {
  void play();
  void pause();
  void skip(double seconds);
  void nextPhrase();
  void previousPhrase();
  void seekTo(Duration position);
}

/// Экран блокировки и фон. На iPhone, Android и Mac — audio_service; на Windows его нет,
/// там звук и так играет, пока открыто окно.
abstract interface class MediaSession {
  void show(NowPlaying now);
  void clear();
}

/// Сессия звука «чтение вслух»: под голос музыка других приложений приглушается,
/// а наушники, звонки и Bluetooth ведут себя как в аудиокнигах.
Future<void> configureAudioSession() async {
  if (!(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) return;
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  } catch (error) {
    debugPrint('Сессия звука: $error');
  }
}

/// Запустить audio_service. `null` — на этой системе экрана блокировки нет (Windows) или он
/// не поднялся; книга всё равно играет.
Future<MediaSession?> startMediaSession(MediaCommands Function() commands) async {
  if (!(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) return null;
  try {
    final handler = await AudioService.init(
      builder: () => _Handler(commands),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'io.github.bradd06.lumen.narration',
        androidNotificationChannelName: 'Озвучка книги',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        fastForwardInterval: Duration(seconds: 15),
        rewindInterval: Duration(seconds: 15),
      ),
    ).timeout(const Duration(seconds: 10));
    return handler;
  } catch (error) {
    debugPrint('Экран блокировки не подключился: $error');
    return null;
  }
}

/// Обработчик audio_service. Кнопки приходят от системы, но в Dart они всегда
/// на главном потоке (подвох из Lumen_exemple, где Swift падал, здесь не возникает).
class _Handler extends BaseAudioHandler with SeekHandler implements MediaSession {
  _Handler(this._commands);

  final MediaCommands Function() _commands;
  String? _shown;

  @override
  void show(NowPlaying now) {
    final cover = now.cover;
    final key = '${now.id}|${now.title}|${now.duration?.inSeconds}|$cover';
    if (key != _shown) {
      _shown = key;
      mediaItem.add(
        MediaItem(
          id: now.id,
          title: now.title,
          album: now.book,
          artist: now.author ?? now.book,
          duration: now.duration,
          artUri: cover == null ? null : Uri.file(cover),
        ),
      );
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          now.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: now.loading ? AudioProcessingState.buffering : AudioProcessingState.ready,
        playing: now.playing,
        updatePosition: now.position,
        speed: now.playing ? now.speed : 0,
      ),
    );
  }

  @override
  void clear() {
    _shown = null;
    playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
  }

  @override
  Future<void> play() async => _commands().play();

  @override
  Future<void> pause() async => _commands().pause();

  @override
  Future<void> stop() async => _commands().pause();

  @override
  Future<void> fastForward() async => _commands().skip(15);

  @override
  Future<void> rewind() async => _commands().skip(-15);

  @override
  Future<void> skipToNext() async => _commands().nextPhrase();

  @override
  Future<void> skipToPrevious() async => _commands().previousPhrase();

  @override
  Future<void> seek(Duration position) async => _commands().seekTo(position);
}
