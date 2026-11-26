import 'package:material_ui/material_ui.dart';

import '../shell/tabs.dart';
import 'tab_page.dart';

class VoicesScreen extends StatelessWidget {
  const VoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TabPage(
      title: 'Голоса',
      children: [
        EmptyCard(
          iconPath: AppTab.voices.iconPath,
          title: 'Голоса диктора и озвученные книги',
          text:
              'Когда приложение подключится к серверу голоса, здесь появятся голоса диктора '
              'и книги, озвученные заранее для прослушивания без сети.',
        ),
      ],
    );
  }
}
