import 'dart:io';

import 'package:lumen_storage/lumen_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_outputs.dart';
import 'media_session.dart';
import 'narration_controller.dart';
import 'prefs.dart';
import 'secure_secret_store.dart';

/// Озвучка на устройстве: настоящий звук, системный голос, экран блокировки.
Future<NarrationController> openNarration(BookStore store) async {
  await configureAudioSession();
  final prefs = await SystemPrefs.open();
  Future<Directory> folder(String name) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}$name');
    await dir.create(recursive: true);
    return dir;
  }

  final phrases = getTemporaryDirectory();
  final controller = NarrationController(
    player: JustAudioPhrasePlayer(phrases),
    speech: FlutterSystemSpeech(),
    music: LoopPlayer(),
    silence: LoopPlayer(),
    secrets: SecureSecretStore(),
    prefs: prefs,
    cacheFolder: folder('phrases'),
    keepAwake: Platform.isIOS || Platform.isAndroid,
  );
  final media = await startMediaSession(() => controller);
  // Сервер проверяется в фоне: окно открывается сразу.
  controller.start(store: store, media: media);
  return controller;
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
