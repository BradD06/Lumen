import 'package:flutter/widgets.dart';

import 'app.dart';
import 'library/library_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await openLibrary();
  runApp(LumenApp(store: library));
}
