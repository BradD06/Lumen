import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/graphite.dart';
import 'tabs.dart';

/// Профиль — стеклянный кружок в левом верхнем углу (Брэд, 27.11.2026).
/// Когда профиль открыт, кружок белый с тёмным значком, как кружок раздела над островом.
class ProfileButton extends StatefulWidget {
  const ProfileButton({super.key, required this.selected, required this.onTap});

  static const size = 44.0;

  /// Место кружка: левый край и отступ под полосой окна (на Mac — под тремя кнопками окна).
  static const left = 20.0;
  static const top = 14.0;

  final bool selected;
  final VoidCallback onTap;

  @override
  State<ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends State<ProfileButton> {
  bool _focused = false;

  static bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    const tab = AppTab.profile;
    const duration = Duration(milliseconds: 220);
    return Tooltip(
      message: '${tab.label}  ${_apple ? '⌘' : 'Ctrl+'}${tab.keyLabel}',
      child: Semantics(
        selected: on,
        button: true,
        label: tab.label,
        excludeSemantics: true,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          customBorder: const CircleBorder(),
          focusColor: Colors.transparent,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Graphite.glassShadow,
                  blurRadius: 18,
                  offset: Offset(0, 6),
                  blurStyle: BlurStyle.outer,
                ),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: ProfileButton.size,
                  height: ProfileButton.size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? Graphite.accent : Graphite.islandFill,
                    // Фокус клавиатуры — белая рамка.
                    border: Border.all(
                      color: _focused
                          ? Colors.white
                          : (on ? Graphite.accent : Graphite.islandBorder),
                      width: _focused ? 1.5 : 1,
                    ),
                  ),
                  child: TweenAnimationBuilder<Color?>(
                    duration: duration,
                    tween: ColorTween(end: on ? Graphite.onAccent : Graphite.text),
                    builder: (context, color, _) => SvgPicture.string(
                      tab.iconSvg,
                      width: 21,
                      height: 21,
                      colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
