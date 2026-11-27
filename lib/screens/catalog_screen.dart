import 'package:material_ui/material_ui.dart';

import '../shell/tabs.dart';
import 'tab_page.dart';

/// Каталог: книги, которые уже есть в приложении, их можно сразу слушать.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TabPage(
      title: 'Каталог',
      children: [
        EmptyCard(
          iconPath: AppTab.catalog.iconPath,
          title: 'Книги, готовые к прослушиванию',
          text:
              'Здесь будут книги, которые уже есть в приложении: выберите любую, '
              'и её можно сразу слушать, ничего не загружая.',
        ),
      ],
    );
  }
}
