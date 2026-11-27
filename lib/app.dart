import 'package:lumen_storage/lumen_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'library/library_scope.dart';
import 'narration/narration_controller.dart';
import 'narration/narration_scope.dart';
import 'shell/app_shell.dart';
import 'theme/graphite.dart';

class LumenApp extends StatelessWidget {
  const LumenApp({super.key, this.store, this.narration});

  /// Библиотека книг; `null` — в памяти (тесты).
  final BookStore? store;

  /// Озвучка; `null` — без звука (тесты).
  final NarrationController? narration;

  @override
  Widget build(BuildContext context) {
    return LibraryScope(
      store: store,
      child: NarrationScope(
        controller: narration,
        child: MaterialApp(
          title: 'Lumen',
          debugShowCheckedModeBanner: false,
          theme: Graphite.theme(),
          home: const AppShell(),
        ),
      ),
    );
  }
}
