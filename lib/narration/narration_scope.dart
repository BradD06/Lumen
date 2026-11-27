import 'dart:io';

import 'package:lumen_storage/lumen_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_outputs.dart';
import 'media_session.dart';
import 'narration_controller.dart';
import 'prefs.dart';
import 'secure_secret_store.dart';

/// Озвучка на устройстве: настоящий звук, системный голос. Ничего не ждёт от системы
/// дольше пары секунд: окно приложения не должно оставаться белым из-за звука.
/// Сессию звука и экран блокировки поднимает `startNarration` уже после первого кадра.
Future<NarrationController?> openNarration() async {
  try {
    final prefs = await SystemPrefs.open().timeout(
      const Duration(seconds: 2),
      onTimeout: MemoryPrefs.new,
    );
    Future<Directory> folder(String name) async {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}${Platform.pathSeparator}$name');
      await dir.create(recursive: true);
      return dir;
    }

    return NarrationController(
      player: JustAudioPhrasePlayer(getTemporaryDirectory()),
      speech: FlutterSystemSpeech(),
      music: LoopPlayer(),
      silence: LoopPlayer(),
      secrets: SecureSecretStore(),
      prefs: prefs,
      cacheFolder: folder('phrases'),
      keepAwake: Platform.isIOS || Platform.isAndroid,
    );
  } catch (error) {
    debugPrint('Озвучка не поднялась: $error');
    return null;
  }
}

/// Сессия звука, экран блокировки и сервер голоса — в фоне, когда окно уже открыто.
Future<void> startNarration(NarrationController controller, BookStore store) async {
  controller.attachStore(store);
  try {
    await configureAudioSession().timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('Сессия звука: $error');
  }
  MediaSession? media;
  try {
    media = await startMediaSession(() => controller);
  } catch (error) {
    debugPrint('Экран блокировки: $error');
  }
  await controller.start(store: store, media: media);
}

/// Даёт экранам озвучку: одна на всё приложение.
class NarrationScope extends StatefulWidget {
  const NarrationScope({super.key, this.controller, required this.child});

  /// `null` — без звука (тесты).
  final NarrationController? controller;
  final Widget child;

  /// Озвучка; экран перестраивается при каждом её изменении.
  static NarrationController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NarrationInherited>()!.notifier!;

  /// Озвучка без подписки на изменения (для кнопок).
  static NarrationController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_NarrationInherited>()!.notifier!;

  @override
  State<NarrationScope> createState() => _NarrationScopeState();
}

class _NarrationScopeState extends State<NarrationScope> {
  late final NarrationController _controller = widget.controller ?? NarrationController.silent();

  @override
  void dispose() {
    // Своя (беззвучная) озвучка живёт вместе с окном; настоящую закрывает приложение.
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _NarrationInherited(notifier: _controller, child: widget.child);
}

class _NarrationInherited extends InheritedNotifier<NarrationController> {
  const _NarrationInherited({required super.notifier, required super.child});
}
