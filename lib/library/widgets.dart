import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass.dart';
import '../theme/graphite.dart';

/// Иконка из контура макета (viewBox 24×24, линия 1.8).
class LineIcon extends StatelessWidget {
  const LineIcon(this.path, {super.key, this.size = 20, this.color = Graphite.text});

  final String path;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '<svg viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="1.8" '
    'stroke-linecap="round" stroke-linejoin="round"><path d="$path"/></svg>',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

abstract final class Icons24 {
  static const back = 'M15 18l-6-6 6-6';
  static const forward = 'M9 18l6-6-6-6';
  static const search = 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4';
  static const upload = 'M12 16V4M7 9l5-5 5 5M5 20h14';
  static const file = 'M14 3H6v18h12V7zM14 3v4h4';
  static const paste = 'M8 4h8v3H8zM6 6H5v15h14V6h-1';
  static const trash = 'M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3';
  static const close = 'M6 6l12 12M18 6L6 18';
  static const more = 'M5 12h.01M12 12h.01M19 12h.01';
}

/// Круглая стеклянная кнопка 44 pt с иконкой.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.label, this.onPressed});

  final String icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Glass(
          radius: 22,
          shadow: false,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(child: LineIcon(icon)),
          ),
        ),
      ),
    ),
  );
}

/// Белая рамка фокуса с клавиатуры (как у острова).
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, required this.radius, this.onActivate});

  final Widget child;
  final double radius;
  final VoidCallback? onActivate;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: widget.onActivate == null ? MouseCursor.defer : SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onActivate?.call()),
      },
      child: AnimatedSlide(
        // Книга под мышью чуть приподнимается.
        offset: _hovered && _isDesktop ? const Offset(0, -0.015) : Offset.zero,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: _focused ? Border.all(color: Graphite.text, width: 2) : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

bool get _isDesktop => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
  _ => false,
};

bool get isDesktop => _isDesktop;

/// Окно по центру с затемнением: заголовок, текст и две кнопки.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Glass(
          radius: 26,
          fill: const Color(0xE61C1C24),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(
                text,
                style: const TextStyle(fontSize: 14, height: 1.4, color: Graphite.textMuted),
              ),
              const SizedBox(height: 6),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: OutlineButton(
                      label: 'Отмена',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Graphite.accent,
                        foregroundColor: Graphite.onAccent,
                        minimumSize: const Size(0, 48),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontFamily: Graphite.font,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(action),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Кнопка с серой рамкой: второе действие рядом с белой.
class OutlineButton extends StatelessWidget {
  const OutlineButton({super.key, required this.label, this.onPressed, this.icon});

  final String label;
  final String? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: Graphite.text,
      side: const BorderSide(color: Graphite.track),
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(
        fontFamily: Graphite.font,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        if (icon != null) LineIcon(icon!, size: 18),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// Короткое сообщение внизу, над островом.
void showNotice(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        text,
        style: const TextStyle(color: Graphite.text, fontFamily: Graphite.font),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF02A2A32),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 110),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
