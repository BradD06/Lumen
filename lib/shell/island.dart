import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass.dart';
import '../theme/graphite.dart';
import 'tabs.dart';

/// Плавающий стеклянный остров внизу по центру — на всех системах, без бокового меню.
class NavIsland extends StatelessWidget {
  const NavIsland({super.key, required this.selected, required this.onSelect});

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Glass(
        radius: 36,
        blur: 36,
        fill: Graphite.islandFill,
        border: Graphite.islandBorder,
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final tab in AppTab.values)
              _IslandButton(tab: tab, selected: tab == selected, onTap: () => onSelect(tab)),
          ],
        ),
      ),
    );
  }
}

class _IslandButton extends StatefulWidget {
  const _IslandButton({required this.tab, required this.selected, required this.onTap});

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_IslandButton> createState() => _IslandButtonState();
}

class _IslandButtonState extends State<_IslandButton> {
  bool _focused = false;

  static bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final fg = widget.selected ? Colors.white : Graphite.islandOffText;
    return Tooltip(
      message: '${tab.label}  ${_apple ? '⌘' : 'Ctrl+'}${tab.index + 1}',
      child: Semantics(
        selected: widget.selected,
        button: true,
        label: tab.label,
        excludeSemantics: true,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          borderRadius: BorderRadius.circular(28),
          focusColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 66,
            height: 56,
            decoration: BoxDecoration(
              color: widget.selected ? Graphite.islandOn : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              // Фокус клавиатуры — белая рамка.
              border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 3,
              children: [
                SvgPicture.string(
                  tab.iconSvg,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                ),
                Text(
                  tab.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: fg,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
