import 'package:flutter/widgets.dart';

import 'app.dart';
import 'library/library_scope.dart';
import 'narration/narration_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await openLibrary();
  final narration = await openNarration(library);
  runApp(LumenApp(store: library, narration: narration));
}
