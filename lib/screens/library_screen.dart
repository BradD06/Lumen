import 'package:material_ui/material_ui.dart';

import '../shell/app_shell.dart';
import '../shell/tabs.dart';
import 'tab_page.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TabPage(
      title: 'Библиотека',
      children: [
        EmptyCard(
          iconPath: AppTab.library.iconPath,
          title: 'Книг пока нет',
          text: 'Здесь будут все ваши книги с цветными обложками, поиском по названию и автору.',
          action: 'Добавить книгу',
          onAction: () => TabSwitcher.of(context)(AppTab.add),
        ),
      ],
    );
  }
}
