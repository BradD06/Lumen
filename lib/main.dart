import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'library/library_scope.dart';
import 'narration/narration_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await openLibrary();
  final narration = await openNarration();
  // Окно открывается сразу; звук, экран блокировки и сервер поднимаются после.
  runApp(LumenApp(store: library, narration: narration));
  if (narration != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(startNarration(narration, library));
    });
  }
}
