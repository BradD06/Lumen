import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'graphite.dart';

/// Стеклянная поверхность: размытие того, что под ней, полупрозрачная заливка,
/// тонкая рамка и светлая кромка сверху, как в макете «Графит».
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 28,
    this.fill = Graphite.glassFill,
    this.border = Graphite.glassBorder,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color fill;
  final Color border;
  final EdgeInsetsGeometry padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      // Тень — на форме, а не на содержимом.
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow
            ? const [
                // Только снаружи: под полупрозрачным стеклом тень не темнит его.
                BoxShadow(
                  color: Graphite.glassShadow,
                  blurRadius: 30,
                  offset: Offset(0, 10),
                  blurStyle: BlurStyle.outer,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: shape,
              border: Border.all(color: border),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, -0.6),
                colors: [Graphite.glassHighlight, Color(0x00FFFFFF)],
                stops: [0, 0.08],
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Фон приложения: ровный графит одним цветом, без бликов (Брэд, 27.11.2026).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Graphite.background, child: child);
  }
}
