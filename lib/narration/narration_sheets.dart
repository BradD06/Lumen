import 'package:lumen_player/lumen_player.dart';
import 'package:lumen_voice/lumen_voice.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass.dart';
import '../theme/graphite.dart';
import 'narration_controller.dart';
import 'narration_scope.dart';

/// Окно в стиле «Графит»: прозрачное стекло, заголовок, список.
Future<T?> _sheet<T>(BuildContext context, {required String title, required WidgetBuilder body}) =>
    showGlassDialog<T>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ),
          Flexible(child: body(context)),
        ],
      ),
    );

Widget _row({
  required String title,
  String? subtitle,
  bool selected = false,
  VoidCallback? onTap,
  Widget? trailing,
}) => ListTile(
  selected: selected,
  selectedColor: Graphite.text,
  selectedTileColor: Graphite.islandOn,
  title: Text(title),
  subtitle: subtitle == null
      ? null
      : Text(subtitle, style: const TextStyle(fontSize: 12, color: Graphite.textMuted)),
  trailing: trailing ?? (selected ? const Icon(Icons.check, size: 18) : null),
  onTap: onTap,
);

/// Таймер сна: выключить, через 5–60 минут или в конце главы.
Future<void> showSleepTimer(BuildContext context, NarrationController narration) => _sheet<void>(
  context,
  title: 'Таймер сна',
  body: (context) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.only(bottom: 10),
    children: [
      _row(
        title: 'Выключен',
        selected: !narration.sleep.isOn,
        onTap: () {
          narration.cancelSleep();
          Navigator.of(context).pop();
        },
      ),
      for (final after in SleepTimer.choices)
        _row(
          title: '${after.inMinutes} мин',
          onTap: () {
            narration.startSleep(after);
            Navigator.of(context).pop();
          },
        ),
      _row(
        title: 'До конца главы',
        selected: narration.sleep.endOfChapter,
        onTap: () {
          narration.sleepAtChapterEnd();
          Navigator.of(context).pop();
        },
      ),
      if (narration.sleep.remaining case final left?)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Text(
            'Сейчас: пауза через ${left.inMinutes + 1} мин',
            style: const TextStyle(fontSize: 12, color: Graphite.textMuted),
          ),
        ),
    ],
  ),
);

/// Голос диктора: голоса сервера и системный; если сервера нет или он молчит — почему.
Future<void> showVoicePicker(
  BuildContext context,
  NarrationController narration, {
  VoidCallback? openServer,
}) => _sheet<void>(
  context,
  title: 'Голос диктора',
  body: (context) => _VoiceList(openServer: openServer),
);

class _VoiceList extends StatelessWidget {
  const _VoiceList({this.openServer});

  final VoidCallback? openServer;

  @override
  Widget build(BuildContext context) {
    final n = NarrationScope.of(context);
    final error = n.serverError ?? n.state.fallback;
    final system = n.systemOnly || n.serverLink == null || n.voices.isEmpty;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 10),
      children: [
        for (final voice in n.voices)
          _row(
            title: voice.name,
            subtitle: 'Голос Lumen с сервера',
            selected: !system && voice.id == n.voiceId,
            onTap: () {
              n.chooseVoice(voice);
              Navigator.of(context).pop();
            },
          ),
        _row(
          title: 'Системный голос',
          subtitle: 'Голос устройства, работает без сервера',
          selected: system,
          onTap: n.voices.isEmpty
              ? null
              : () {
                  n.useSystemVoice();
                  Navigator.of(context).pop();
                },
        ),
        if (error != null) ServerProblem(error: error),
        if (n.serverLink == null || error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Graphite.text,
                side: const BorderSide(color: Graphite.glassBorder),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                openServer?.call();
              },
              child: Text(n.serverLink == null ? 'Подключить сервер голоса' : 'Сервер голоса'),
            ),
          ),
      ],
    );
  }
}

/// «Сервер не отвечает» / «Нет интернета» и что проверить.
class ServerProblem extends StatelessWidget {
  const ServerProblem({super.key, required this.error});

  final VoiceError error;

  static List<String> checksFor(VoiceError error) => switch (error.kind) {
    VoiceErrorKind.noInternet => const [
      'Wi-Fi или мобильная сеть включены',
      'Режим полёта выключен',
      'Голос Lumen вернётся сам, когда сеть появится',
    ],
    VoiceErrorKind.wrongKey => const [
      'Скопируйте ссылку с ключом из окна сервера заново',
      'Вставьте её во вкладке «Голоса» целиком',
    ],
    VoiceErrorKind.starting => const ['Подождите минуту: модель голоса загружается'],
    _ => const [
      'Сервер голоса запущен',
      'Устройство и сервер в одной сети или в Tailscale',
      'Адрес сервера не поменялся',
      'Пока читает системный голос, голос Lumen вернётся сам',
    ],
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Graphite.glassFillStrong,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Graphite.glassBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(error.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        Text(
          error.message,
          style: const TextStyle(fontSize: 13, height: 1.35, color: Graphite.textMuted),
        ),
        for (final check in checksFor(error))
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 6, right: 8),
                child: SizedBox(
                  width: 5,
                  height: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Graphite.textMuted, shape: BoxShape.circle),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  check,
                  style: const TextStyle(fontSize: 13, height: 1.35, color: Graphite.textMuted),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
