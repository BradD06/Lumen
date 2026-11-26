import 'package:material_ui/material_ui.dart';

import 'tab_page.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    return const TabPage(
      title: 'Профиль и настройки',
      children: [
        SettingsGroup(
          title: 'Озвучка',
          rows: [
            SettingsRow(label: 'Сервер озвучки', value: 'не подключён'),
            SettingsRow(label: 'Музыка на фоне', value: 'выкл', last: true),
          ],
        ),
        SettingsGroup(
          title: 'Приложение',
          rows: [SettingsRow(label: 'О приложении', value: version, last: true)],
        ),
      ],
    );
  }
}
