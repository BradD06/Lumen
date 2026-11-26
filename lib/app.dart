import 'package:material_ui/material_ui.dart';

import 'shell/app_shell.dart';
import 'theme/graphite.dart';

class LumenApp extends StatelessWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: Graphite.theme(),
      home: const AppShell(),
    );
  }
}
