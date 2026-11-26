import 'package:material_ui/material_ui.dart';

import 'tab_page.dart';

class AddBookScreen extends StatelessWidget {
  const AddBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabPage(
      title: 'Добавить книгу',
      children: [
        EmptyCard(
          iconPath: 'M14 3H6v18h12V7zM14 3v4h4',
          title: 'EPUB, FB2 или TXT',
          text:
              'Скоро здесь можно будет выбрать файл книги или перетащить его в это поле. '
              'Lumen разберёт её на главы и подготовит к озвучке.',
        ),
      ],
    );
  }
}
