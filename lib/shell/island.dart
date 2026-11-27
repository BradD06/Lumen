import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/graphite.dart';
import 'tabs.dart';

/// Размеры острова. Открытый раздел выпрыгивает над капсулой белым кружком,
/// под кружком в капсуле вырез; при переключении кружок с вырезом едет по острову
/// (как `BubbleBar` в Lumen_exemple).
abstract final class IslandMetrics {
  static const buttonWidth = 66.0;
  static const buttonHeight = 56.0;
  static const spacing = 2.0;
  static const padding = 6.0;
  static const height = buttonHeight + padding * 2;

  /// Диаметр кружка.
  static const bubble = 46.0;

  /// Зазор между кружком и краем выреза.
  static const gap = 6.0;

  /// Центр кружка ниже верхнего края капсулы: кружок сидит в ней, а не висит над ней.
  static const centerY = 6.0;

  /// Скруглённые плечики, которыми вырез переходит в верхний край.
  static const shoulder = 12.0;

  /// Насколько кружок выступает над капсулой: столько места оставлено сверху.
  static const lift = bubble / 2 - centerY;

  static const move = Duration(milliseconds: 460);

  static double get width {
    final n = AppTab.island.length;
    return padding * 2 + n * buttonWidth + (n - 1) * spacing;
  }

  /// Центр кнопки раздела от левого края капсулы.
  static double centerOf(AppTab tab) =>
      padding + AppTab.island.indexOf(tab) * (buttonWidth + spacing) + buttonWidth / 2;
}

/// Плавающий стеклянный остров внизу по центру — на всех системах, без бокового меню.
/// Когда открыт раздел не из острова (профиль), кружок опускается в остров и вырез затягивается.
class NavIsland extends StatefulWidget {
  const NavIsland({super.key, required this.selected, required this.onSelect});

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  State<NavIsland> createState() => _NavIslandState();
}

class _NavIslandState extends State<NavIsland> with TickerProviderStateMixin {
  late final _move = AnimationController(vsync: this, duration: IslandMetrics.move, value: 1);
  late final _curve = CurvedAnimation(parent: _move, curve: Curves.easeInOutCubicEmphasized);

  /// 1 — кружок над островом и вырез целиком, 0 — ровная капсула без кружка.
  late final _notch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.selected.inIsland ? 1 : 0,
  );
  late final _notchCurve = CurvedAnimation(parent: _notch, curve: Curves.easeOutCubic);
  late final _both = Listenable.merge([_curve, _notchCurve]);

  late double _from = _targetX(widget.selected);
  late double _to = _from;

  /// Последний раздел острова: пока открыт профиль, кружок прячется на его месте.
  late AppTab _shown = widget.selected.inIsland ? widget.selected : AppTab.home;

  double _targetX(AppTab tab) => IslandMetrics.centerOf(tab.inIsland ? tab : AppTab.home);

  double get _x => lerpDouble(_from, _to, _curve.value)!;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didUpdateWidget(NavIsland old) {
    super.didUpdateWidget(old);
    final tab = widget.selected;
    if (tab == old.selected) return;
    if (!tab.inIsland) {
      _still ? _notch.value = 0 : _notch.reverse();
      return;
    }
    final target = IslandMetrics.centerOf(tab);
    if (_notch.value == 0) {
      // Кружок появляется сразу на месте раздела и вырастает из острова, а не едет от края.
      _move.value = 1;
      _from = _to = target;
    } else if (target != _to) {
      // Едем от того места, где кружок сейчас, даже если прошлый переезд не закончился.
      _from = _x;
      _to = target;
      _still ? _move.value = 1 : _move.forward(from: 0);
    }
    setState(() => _shown = tab);
    _still ? _notch.value = 1 : _notch.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _move.dispose();
    _notchCurve.dispose();
    _notch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const lift = IslandMetrics.lift;
    final width = IslandMetrics.width;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: width,
        height: IslandMetrics.height + lift,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: lift,
              width: width,
              height: IslandMetrics.height,
              child: AnimatedBuilder(
                animation: _both,
                builder: (context, _) => _NotchedGlass(notchX: _x, notch: _notchCurve.value),
              ),
            ),
            Positioned(
              left: IslandMetrics.padding,
              top: lift + IslandMetrics.padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: IslandMetrics.spacing,
                children: [
                  for (final tab in AppTab.island)
                    _IslandButton(
                      tab: tab,
                      selected: tab == widget.selected,
                      onTap: () => widget.onSelect(tab),
                    ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _both,
              builder: (context, child) {
                // В пути кружок чуть сжимается, как капля, и снова набирает размер на месте.
                final t = _move.isAnimating ? _curve.value.clamp(0.0, 1.0) : 1.0;
                final squeeze = 1 - 0.08 * math.sin(math.pi * t);
                final shown = _notchCurve.value;
                return Positioned(
                  key: const Key('island-bubble'),
                  left: _x - IslandMetrics.bubble / 2,
                  top: (1 - shown) * 14,
                  width: IslandMetrics.bubble,
                  height: IslandMetrics.bubble,
                  child: Opacity(
                    opacity: shown.clamp(0.0, 1.0),
                    child: Transform.scale(scale: squeeze * (0.7 + 0.3 * shown), child: child),
                  ),
                );
              },
              child: _Bubble(tab: _shown),
            ),
          ],
        ),
      ),
    );
  }
}

/// Стеклянная капсула острова с круглым вырезом под кружком.
class _NotchedGlass extends StatelessWidget {
  const _NotchedGlass({required this.notchX, required this.notch});

  final double notchX;
  final double notch;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      // Тень только снаружи формы: под полупрозрачным стеклом она его не темнит.
      painter: _IslandShadow(notchX, notch),
      child: ClipPath(
        clipper: _NotchClipper(notchX, notch),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: CustomPaint(painter: _IslandFill(notchX, notch), child: const SizedBox.expand()),
        ),
      ),
    );
  }
}

/// Капсула минус вырез: круг под кружком и плечики к верхнему краю.
/// `notch` от 0 (ровная капсула) до 1 (вырез целиком): пока вырез появляется,
/// его круг поднимается из-за верхнего края.
Path notchedIsland(Size size, double notchX, [double notch = 1]) {
  final capsule = Path()
    ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)));
  if (notch < 0.01) return capsule;
  const r = IslandMetrics.bubble / 2 + IslandMetrics.gap;
  const c0 = IslandMetrics.centerY;
  final cy = c0 - (1 - notch) * (r + c0 + 2);
  if (cy <= -r) return capsule;
  final x = notchX;
  final circle = Path()..addOval(Rect.fromCircle(center: Offset(x, cy), radius: r));
  final y1 = math.max(5.0, cy + 2);
  if (y1 - cy >= r) return Path.combine(PathOperation.difference, capsule, circle);

  // Где круг пересекает верхний край, и откуда к нему идут плечики.
  final edge = math.sqrt(r * r - cy * cy);
  final side = math.sqrt(r * r - (y1 - cy) * (y1 - cy));
  final shoulder = IslandMetrics.shoulder * notch;
  final cut = Path()
    ..moveTo(x - edge - shoulder, -60)
    ..lineTo(x - edge - shoulder, 0)
    ..quadraticBezierTo(x - edge, 0, x - side, y1)
    ..lineTo(x + side, y1)
    ..quadraticBezierTo(x + edge, 0, x + edge + shoulder, 0)
    ..lineTo(x + edge + shoulder, -60)
    ..close();
  return Path.combine(
    PathOperation.difference,
    capsule,
    Path.combine(PathOperation.union, cut, circle),
  );
}

class _NotchClipper extends CustomClipper<Path> {
  const _NotchClipper(this.notchX, this.notch);

  final double notchX;
  final double notch;

  @override
  Path getClip(Size size) => notchedIsland(size, notchX, notch);

  @override
  bool shouldReclip(_NotchClipper old) => old.notchX != notchX || old.notch != notch;
}

class _IslandShadow extends CustomPainter {
  const _IslandShadow(this.notchX, this.notch);

  final double notchX;
  final double notch;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      notchedIsland(size, notchX, notch).shift(const Offset(0, 10)),
      Paint()
        ..color = Graphite.glassShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 15),
    );
  }

  @override
  bool shouldRepaint(_IslandShadow old) => old.notchX != notchX || old.notch != notch;
}

/// Заливка, светлая кромка сверху и тонкая рамка по форме выреза.
class _IslandFill extends CustomPainter {
  const _IslandFill(this.notchX, this.notch);

  final double notchX;
  final double notch;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = Graphite.islandFill);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment(0, -0.6),
          colors: [Graphite.glassHighlight, Color(0x00FFFFFF)],
          stops: [0, 0.08],
        ).createShader(rect),
    );
    // Половина линии обрезается формой, внутри остаётся рамка в 1 точку.
    canvas.drawPath(
      notchedIsland(size, notchX, notch),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Graphite.islandBorder,
    );
  }

  @override
  bool shouldRepaint(_IslandFill old) => old.notchX != notchX || old.notch != notch;
}

/// Кружок открытого раздела: значок раздела, тёмный на белом.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Graphite.accent,
            boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6))],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.6, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: SvgPicture.string(
                tab.iconSvg,
                key: ValueKey(tab),
                width: 21,
                height: 21,
                colorFilter: const ColorFilter.mode(Graphite.onAccent, BlendMode.srcIn),
              ),
            ),
          ),
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
    final on = widget.selected;
    const fade = Duration(milliseconds: 260);
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
          borderRadius: BorderRadius.circular(28),
          focusColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: IslandMetrics.buttonWidth,
            height: IslandMetrics.buttonHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              // Фокус клавиатуры — белая рамка.
              border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 3,
              children: [
                // У открытого раздела значок уезжает вверх, в кружок; подпись остаётся.
                AnimatedSlide(
                  offset: on ? const Offset(0, -0.6) : Offset.zero,
                  duration: fade,
                  curve: Curves.easeOutCubic,
                  child: AnimatedScale(
                    scale: on ? 0.7 : 1,
                    duration: fade,
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: on ? 0 : 1,
                      duration: fade,
                      child: SvgPicture.string(
                        tab.iconSvg,
                        width: 22,
                        height: 22,
                        colorFilter: const ColorFilter.mode(
                          Graphite.islandOffText,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedDefaultTextStyle(
                  duration: fade,
                  style: TextStyle(
                    fontFamily: Graphite.font,
                    fontSize: 10,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                    color: on ? Colors.white : Graphite.islandOffText,
                    height: 1.1,
                  ),
                  child: Text(tab.label, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
