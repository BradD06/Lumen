import 'package:flutter/services.dart';
import 'package:lumen_voice/lumen_voice.dart';
import 'package:material_ui/material_ui.dart';

import '../narration/narration_controller.dart';
import '../narration/narration_scope.dart';
import '../narration/narration_sheets.dart';
import '../theme/glass.dart';
import '../theme/graphite.dart';
import 'tab_page.dart';

/// «Голоса»: сервер голоса (ссылка из его окна) и голос диктора для всех книг.
/// Озвученные заранее книги появятся здесь на этапе 8.
class VoicesScreen extends StatelessWidget {
  const VoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final n = NarrationScope.of(context);
    return TabPage(
      title: 'Голоса',
      children: [
        _ServerCard(narration: n),
        _VoicesCard(narration: n),
      ],
    );
  }
}

class _ServerCard extends StatefulWidget {
  const _ServerCard({required this.narration});

  final NarrationController narration;

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  final _field = TextEditingController();
  var _busy = false;
  VoiceError? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final input = _field.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.narration.connect(input);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) _field.clear();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _field.text = text;
    await _connect();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    await widget.narration.refreshServer();
    if (mounted) setState(() => _busy = false);
  }

  static String _status(ServerState state) => switch (state) {
    ServerState.notSet => 'Не подключён',
    ServerState.connected => 'Подключён',
    ServerState.notResponding => 'Не отвечает',
    ServerState.noInternet => 'Нет интернета',
    ServerState.wrongKey => 'Ключ не подходит',
  };

  @override
  Widget build(BuildContext context) {
    final n = widget.narration;
    final link = n.serverLink;
    final problem = _error ?? n.serverError;
    return Glass(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Сервер голоса',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                _status(n.serverState),
                style: TextStyle(
                  fontSize: 13,
                  color: n.serverState == ServerState.connected
                      ? Graphite.text
                      : Graphite.textMuted,
                ),
              ),
            ],
          ),
          if (link != null)
            Text(
              link.baseUrl.host,
              style: const TextStyle(fontSize: 13, color: Graphite.textMuted),
            ),
          if (link == null)
            const Text(
              'Голос Lumen читает книги нейроголосом с вашего сервера. Скопируйте ссылку с '
              'ключом из окна сервера и вставьте её сюда. Без сервера книги читает системный '
              'голос устройства.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Graphite.textMuted),
            ),
          TextField(
            controller: _field,
            enabled: !_busy,
            autocorrect: false,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _connect(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: link == null ? 'https://…/#key=…' : 'Новая ссылка сервера',
              hintStyle: const TextStyle(color: Graphite.textFaint),
              filled: true,
              fillColor: Graphite.glassFillStrong,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Graphite.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Graphite.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Graphite.text),
              ),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AccentButton(
                label: _busy ? 'Проверяю…' : 'Подключить',
                onPressed: _busy ? null : _connect,
              ),
              _Quiet(label: 'Вставить ссылку', onPressed: _busy ? null : _paste),
              if (link != null) _Quiet(label: 'Проверить', onPressed: _busy ? null : _check),
              if (link != null)
                _Quiet(
                  label: 'Отключить',
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _error = null);
                          n.disconnect();
                        },
                ),
            ],
          ),
          if (problem != null) ServerProblem(error: problem),
          const Text(
            'Ключ хранится только в защищённом хранилище системы.',
            style: TextStyle(fontSize: 12, color: Graphite.textFaint),
          ),
        ],
      ),
    );
  }
}

class _VoicesCard extends StatelessWidget {
  const _VoicesCard({required this.narration});

  final NarrationController narration;

  @override
  Widget build(BuildContext context) {
    final n = narration;
    final system = n.systemOnly || n.voices.isEmpty;
    return Glass(
      radius: 22,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Text(
              'Голос диктора',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Text(
              'Один диктор на всю книгу: персонажей он различает интонацией.',
              style: TextStyle(fontSize: 13, color: Graphite.textMuted),
            ),
          ),
          for (final voice in n.voices)
            _VoiceRow(
              title: voice.name,
              subtitle: 'Голос Lumen',
              selected: !system && voice.id == n.voiceId,
              onTap: () => n.chooseVoice(voice),
            ),
          _VoiceRow(
            title: 'Системный голос',
            subtitle: 'Голос устройства, без сервера',
            selected: system,
            onTap: n.voices.isEmpty ? null : n.useSystemVoice,
          ),
        ],
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    selected: selected,
    selectedColor: Graphite.text,
    title: Text(title),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Graphite.textMuted)),
    trailing: selected ? const Icon(Icons.check, size: 18) : null,
    onTap: onTap,
  );
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: Graphite.text,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: const StadiumBorder(),
      side: const BorderSide(color: Graphite.glassBorder),
    ),
    child: Text(label),
  );
}
