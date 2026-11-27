import 'package:lumen_voice/lumen_voice.dart';
import 'package:material_ui/material_ui.dart';

import '../narration/narration_scope.dart';

import 'tab_page.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final n = NarrationScope.of(context);
    return TabPage(
      title: 'Профиль и настройки',
      children: [
        SettingsGroup(
          title: 'Озвучка',
          rows: [
            SettingsRow(
              label: 'Сервер голоса',
              value: switch (n.serverState) {
                ServerState.notSet => 'не подключён',
                ServerState.connected => 'подключён',
                ServerState.notResponding => 'не отвечает',
                ServerState.noInternet => 'нет интернета',
                ServerState.wrongKey => 'ключ не подходит',
              },
            ),
            SettingsRow(label: 'Голос диктора', value: n.voiceName),
            SettingsRow(
              label: 'Музыка на фоне',
              value: n.mix.musicOn ? n.track.title : 'выкл',
              last: true,
            ),
          ],
        ),
        const SettingsGroup(
          title: 'Приложение',
          rows: [SettingsRow(label: 'О приложении', value: version, last: true)],
        ),
      ],
    );
  }
}
