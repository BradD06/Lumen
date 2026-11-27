import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass.dart';
import '../theme/graphite.dart';

/// Общая раскладка раздела: заголовок сверху (под кружком профиля в углу),
/// колонка до 1100 px по центру, снизу место под остров.
class TabPage extends StatelessWidget {
  const TabPage({super.key, required this.title, this.overline, required this.children});

  final String title;
  final String? overline;
  final List<Widget> children;

  /// На Mac кнопки окна лежат поверх приложения (прозрачный заголовок).
  static double get windowBar => defaultTargetPlatform == TargetPlatform.macOS ? 28 : 0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + windowBar;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, top + 76, 20, 140),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 22,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    if (overline != null)
                      Text(
                        overline!,
                        style: const TextStyle(fontSize: 13, color: Graphite.textMuted),
                      ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Пустое место раздела: что здесь будет и (по желанию) одна кнопка.
class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.iconPath,
    required this.title,
    required this.text,
    this.action,
    this.onAction,
  });

  final String iconPath;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        spacing: 12,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Graphite.glassFillStrong,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SvgPicture.string(
              '<svg viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.8" '
              'stroke-linecap="round" stroke-linejoin="round"><path d="$iconPath"/></svg>',
              width: 26,
              height: 26,
              colorFilter: const ColorFilter.mode(Graphite.text, BlendMode.srcIn),
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45, color: Graphite.textMuted),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 4),
            AccentButton(label: action!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// Белая кнопка: акцент интерфейса «Графита».
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Graphite.accent,
        foregroundColor: Graphite.onAccent,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: Graphite.font,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Строка настроек в стеклянной группе.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Graphite.line)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Text(value, style: const TextStyle(fontSize: 15, color: Graphite.textMuted)),
        ],
      ),
    );
  }
}

/// Группа настроек: подпись и стеклянный блок строк.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Graphite.textMuted,
          ),
        ),
      ),
      Glass(radius: 22, child: Column(children: rows)),
    ],
  );
}
