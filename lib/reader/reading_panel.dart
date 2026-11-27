import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../library/widgets.dart';
import '../theme/fading_glass.dart';
import '../theme/glass.dart';
import '../theme/graphite.dart';

/// Полоса прогресса: янтарь по серой дорожке (DESIGN.md: янтарь — только слово
/// под голосом и прогресс). Нажатие или перетаскивание переносит на это место.
/// Общая для текста главы и будущего плеера.
class ReadingProgressBar extends StatelessWidget {
  const ReadingProgressBar({super.key, required this.value, this.onSeek, this.label});

  /// От 0 до 1.
  final double value;

  /// Куда перейти (0…1); `null` — полоса только показывает.
  final ValueChanged<double>? onSeek;

  /// Для чтения с экрана: «Прочитано 45 %».
  final String? label;

  static const height = 4.0;

  void _seekAt(BuildContext context, Offset local) {
    final width = (context.findRenderObject()! as RenderBox).size.width;
    if (width > 0) onSeek!((local.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    final bar = SizedBox(
      // Высокая зона нажатия, тонкая полоса.
      height: 20,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Graphite.track),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: const ColoredBox(color: Graphite.amber),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: label,
      value: '${(v * 100).round()} %',
      slider: onSeek != null,
      child: onSeek == null
          ? bar
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Builder(
                builder: (context) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onTapDown: (d) => _seekAt(context, d.localPosition),
                  onHorizontalDragUpdate: (d) => _seekAt(context, d.localPosition),
                  child: bar,
                ),
              ),
            ),
    );
  }
}

/// Панель чтения: «предыдущая», подпись и прогресс, «следующая».
/// Кнопки по краям листают главы; под прогрессом — [controls]
/// (управление озвучкой, `NarrationControls`).
///
/// Без [bottomInset] — стеклянный остров со скруглёнными углами. С ним —
/// полоса во всю ширину у низа экрана, как шапка главы: стекло сверху
/// растворяется, и текст под ним размывается (Брэд, 27.11.2026).
class ReadingPanel extends StatelessWidget {
  const ReadingPanel({
    super.key,
    required this.title,
    required this.value,
    this.trailing,
    this.onSeek,
    this.onPrevious,
    this.onNext,
    this.previousLabel = 'Предыдущая глава',
    this.nextLabel = 'Следующая глава',
    this.controls,
    this.maxWidth = 560,
    this.bottomInset,
  });

  /// Высота стеклянной кромки над полосой.
  static const fade = 30.0;

  /// Слева над полосой: «Глава 3 из 22».
  final String title;

  /// Справа над полосой: «45 %» или время.
  final String? trailing;
  final double value;
  final ValueChanged<double>? onSeek;

  /// `null` — кнопка видна, но погашена (первая или последняя глава).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String previousLabel;
  final String nextLabel;

  /// Ряды под прогрессом: кнопки озвучки.
  final Widget? controls;
  final double maxWidth;

  /// Отступ снизу внутри полосы (системная полоса жестов); `null` — остров.
  final double? bottomInset;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 12, color: Graphite.textMuted);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: 6,
          children: [
            _StepButton(icon: Icons24.back, label: previousLabel, onPressed: onPrevious),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                      if (trailing != null) Text(trailing!, style: small),
                    ],
                  ),
                  ReadingProgressBar(value: value, onSeek: onSeek, label: title),
                ],
              ),
            ),
            _StepButton(icon: Icons24.forward, label: nextLabel, onPressed: onNext),
          ],
        ),
        ?controls,
      ],
    );
    final inset = bottomInset;
    if (inset == null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Glass(
          radius: 26,
          fill: Graphite.islandFill,
          border: Graphite.islandBorder,
          padding: const EdgeInsets.all(6),
          child: content,
        ),
      );
    }
    return Stack(
      children: [
        const Positioned.fill(
          child: FadingGlass(fadeEdge: AxisDirection.up, fade: fade),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, fade, 12, inset),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(padding: const EdgeInsets.all(6), child: content),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.label, this.onPressed});

  final String icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: on,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: LineIcon(icon, color: on ? Graphite.text : Graphite.track)),
          ),
        ),
      ),
    );
  }
}
