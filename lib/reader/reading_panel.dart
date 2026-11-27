import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../library/widgets.dart';
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

/// Стеклянная панель над островом: «предыдущая», подпись и прогресс, «следующая».
/// В тексте главы кнопки листают главы; плеер (этап 3) поставит сюда свои
/// кнопки и добавит ряд управления сверху через [top].
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
    this.top,
  });

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

  /// Ряд над прогрессом (для плеера).
  final Widget? top;

  static const maxWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 12, color: Graphite.textMuted);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Glass(
        radius: 26,
        fill: Graphite.islandFill,
        border: Graphite.islandBorder,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?top,
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
          ],
        ),
      ),
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
