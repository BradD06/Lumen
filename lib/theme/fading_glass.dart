import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'graphite.dart';

/// Стекло во всю ширину, которое у одного края сходит на нет: сильное размытие
/// и затемнение в сплошной части, всё слабее в полосе [fade] у края [fadeEdge].
/// Текст, уходящий под шапку главы или под плеер, постепенно размывается.
class FadingGlass extends StatelessWidget {
  const FadingGlass({super.key, required this.fadeEdge, this.fade = 30});

  /// Край, где стекло растворяется: [AxisDirection.down] у шапки,
  /// [AxisDirection.up] у плеера внизу.
  final AxisDirection fadeEdge;

  /// Высота полосы, где стекло сходит на нет.
  final double fade;

  /// Размытие полос в кромке: мелкие шаги, чтобы край не читался полосой.
  static const _fadeSigmas = [11.0, 8.0, 6.0, 4.0, 2.5, 1.2];

  @override
  Widget build(BuildContext context) {
    final up = fadeEdge == AxisDirection.up;
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxHeight;
        final solid = (total - fade).clamp(0.0, total);
        final step = fade / _fadeSigmas.length;
        // Позиция от «сплошного» края: у шапки это верх, у плеера — низ.
        Positioned band(double from, double height, Widget child) => up
            ? Positioned(left: 0, right: 0, bottom: from, height: height, child: child)
            : Positioned(left: 0, right: 0, top: from, height: height, child: child);
        return IgnorePointer(
          child: Stack(
            children: [
              band(0, solid, const _Blur(sigma: 14)),
              for (final (i, sigma) in _fadeSigmas.indexed)
                band(solid + i * step, step, _Blur(sigma: sigma)),
              // Затемнение фоном приложения: у сплошного края плотнее, к кромке прозрачное.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: up ? Alignment.bottomCenter : Alignment.topCenter,
                      end: up ? Alignment.topCenter : Alignment.bottomCenter,
                      stops: [0, total == 0 ? 0 : solid / total, 1],
                      colors: [
                        Graphite.background.withValues(alpha: .72),
                        Graphite.background.withValues(alpha: .45),
                        Graphite.background.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Blur extends StatelessWidget {
  const _Blur({required this.sigma});

  final double sigma;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
      child: const SizedBox.expand(),
    ),
  );
}
