import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass.dart';
import '../theme/graphite.dart';

/// Что показывает блок озвучки. Пока звука нет, экран держит это сам;
/// плеер (этап 3, `lumen_player`) будет отдавать то же из своего состояния.
@immutable
class NarrationView {
  const NarrationView({
    this.playing = false,
    this.loading = false,
    this.speed = 1.0,
    this.voiceName,
    this.musicOn = false,
    this.musicVolume = 0.3,
    this.sleepTimer,
  });

  final bool playing;

  /// Голос ещё готовит фразу: вокруг паузы крутится кольцо.
  final bool loading;
  final double speed;
  final String? voiceName;
  final bool musicOn;

  /// Громкость музыки под голосом, 0…1.
  final double musicVolume;

  /// Сколько осталось до таймера сна; `null` — таймер выключен.
  final Duration? sleepTimer;

  /// Скорости из макета.
  static const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

  /// «1,25×» — с запятой, как в макете.
  static String speedLabel(double speed) {
    final s = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(1)
        : speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return '${s.replaceAll('.', ',')}×';
  }

  NarrationView copyWith({
    bool? playing,
    bool? loading,
    double? speed,
    String? voiceName,
    bool? musicOn,
    double? musicVolume,
  }) => NarrationView(
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    speed: speed ?? this.speed,
    voiceName: voiceName ?? this.voiceName,
    musicOn: musicOn ?? this.musicOn,
    musicVolume: musicVolume ?? this.musicVolume,
    sleepTimer: sleepTimer,
  );
}

/// Что делают кнопки. Неподключённая кнопка (`null`) видна, но погашена.
/// Плеер подставит сюда свои методы.
@immutable
class NarrationActions {
  const NarrationActions({
    this.playPause,
    this.back15,
    this.forward15,
    this.previousPhrase,
    this.nextPhrase,
    this.speed,
    this.sleepTimer,
    this.voice,
    this.music,
    this.musicVolume,
    this.chapters,
    this.textLook,
  });

  final VoidCallback? playPause;
  final VoidCallback? back15;
  final VoidCallback? forward15;
  final VoidCallback? previousPhrase;
  final VoidCallback? nextPhrase;
  final ValueChanged<double>? speed;
  final VoidCallback? sleepTimer;
  final VoidCallback? voice;
  final ValueChanged<bool>? music;
  final ValueChanged<double>? musicVolume;
  final VoidCallback? chapters;

  /// «Аа» — «Вид текста».
  final VoidCallback? textLook;
}

/// Блок управления озвучкой (макет «Графит», остров плеера): перемотка на 15 с,
/// предыдущая и следующая фраза, белая пауза; ниже скорость, таймер сна, голос,
/// музыка на фоне, главы и «Аа». На широком окне всё в один ряд.
class NarrationControls extends StatelessWidget {
  const NarrationControls({super.key, required this.view, required this.actions});

  final NarrationView view;
  final NarrationActions actions;

  /// С какой ширины панели всё помещается в один ряд.
  static const oneRowWidth = 620.0;

  /// Высота блока: для отступа текста под панелью.
  static double heightFor(double panelWidth) => panelWidth >= oneRowWidth ? 60 : 60 + 46;

  @override
  Widget build(BuildContext context) {
    final transport = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        _RoundButton(
          label: 'Назад на 15 секунд',
          onPressed: actions.back15,
          child: const _Icon(_Paths.back15),
        ),
        _RoundButton(
          label: 'Предыдущая фраза',
          onPressed: actions.previousPhrase,
          child: const _Icon(_Paths.previous, filled: true),
        ),
        _PlayButton(playing: view.playing, loading: view.loading, onPressed: actions.playPause),
        _RoundButton(
          label: 'Следующая фраза',
          onPressed: actions.nextPhrase,
          child: const _Icon(_Paths.next, filled: true),
        ),
        _RoundButton(
          label: 'Вперёд на 15 секунд',
          onPressed: actions.forward15,
          child: const _Icon(_Paths.forward15),
        ),
      ],
    );
    final options = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        _SpeedButton(speed: view.speed, onChanged: actions.speed),
        _RoundButton(
          label: view.sleepTimer == null ? 'Таймер сна' : 'Таймер сна: включён',
          selected: view.sleepTimer != null,
          onPressed: actions.sleepTimer,
          child: const _Icon(_Paths.timer, size: 19),
        ),
        _RoundButton(
          label: view.voiceName == null ? 'Голос' : 'Голос: ${view.voiceName}',
          onPressed: actions.voice,
          child: const _Icon(_Paths.voice, size: 19),
        ),
        _MusicButton(view: view, actions: actions),
        _RoundButton(
          label: 'Главы',
          onPressed: actions.chapters,
          child: const _Icon(_Paths.chapters, size: 19),
        ),
        _RoundButton(
          label: 'Вид текста',
          onPressed: actions.textLook,
          child: const Text('Аа', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= oneRowWidth - 12;
        if (wide) {
          return SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [transport, options],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 60, child: Center(child: transport)),
            SizedBox(
              height: 46,
              child: FittedBox(fit: BoxFit.scaleDown, child: options),
            ),
          ],
        );
      },
    );
  }
}

abstract final class _Paths {
  static const back15 = 'M3 12a9 9 0 1 0 3-6.7M3 4v5h5';
  static const forward15 = 'M21 12a9 9 0 1 1-3-6.7M21 4v5h-5';
  static const previous = 'M18 5L8 12l10 7zM5 5h2v14H5z';
  static const next = 'M6 5l10 7-10 7zM17 5h2v14h-2z';
  static const play = 'M7 4l13 8-13 8z';
  static const pause = 'M7 4h4v16H7zM13 4h4v16h-4z';
  static const timer = 'M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z';
  static const voice =
      'M12 3a3 3 0 0 0-3 3v5a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3zM5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21';
  static const music =
      'M9 18V5l11-2v13M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0zM20 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0z';
  static const chapters = 'M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01';
}

class _Icon extends StatelessWidget {
  const _Icon(this.path, {this.size = 22, this.filled = false});

  final String path;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Graphite.text;
    final paint = filled
        ? 'fill="#FFFFFF"'
        : 'fill="none" stroke="#FFFFFF" stroke-width="1.8" '
              'stroke-linecap="round" stroke-linejoin="round"';
    return SvgPicture.string(
      '<svg viewBox="0 0 24 24" $paint><path d="$path"/></svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// Прозрачная круглая кнопка 44 pt; выбранная — с мягкой подложкой.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.child,
    this.onPressed,
    this.selected = false,
    this.width = 44,
  });

  final String label;
  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final double width;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    final color = on ? Graphite.text : Graphite.track;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: on,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: width,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? Graphite.islandOn : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(color: color),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: color),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Белая круглая пауза / воспроизведение; пока голос готовит фразу — кольцо.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.loading, this.onPressed});

  final bool playing;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = playing ? 'Пауза' : 'Слушать';
    return Tooltip(
      message: '$label  Пробел',
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Material(
                  color: onPressed == null ? Graphite.track : Graphite.accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onPressed,
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: IconTheme(
                            key: ValueKey(playing),
                            data: const IconThemeData(color: Graphite.onAccent),
                            child: _Icon(playing ? _Paths.pause : _Paths.play, filled: true),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (loading)
                  const IgnorePointer(
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Graphite.amber),
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

/// Скорость: «1,0×», нажатие открывает список скоростей.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.speed, this.onChanged});

  final double speed;
  final ValueChanged<double>? onChanged;

  Future<void> _pick(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<double>(
      context: context,
      color: const Color(0xF2202028),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: RelativeRect.fromRect(at & box.size, Offset.zero & overlay.size),
      items: [
        for (final s in NarrationView.speeds)
          CheckedPopupMenuItem(
            value: s,
            checked: s == speed,
            child: Text(NarrationView.speedLabel(s)),
          ),
      ],
    );
    if (picked != null) onChanged!(picked);
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => _RoundButton(
      label: 'Скорость',
      width: 58,
      onPressed: onChanged == null ? null : () => _pick(context),
      child: Text(
        NarrationView.speedLabel(speed),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Музыка на фоне: подсвечена, когда играет; нажатие — окно с переключателем
/// и громкостью над панелью.
class _MusicButton extends StatelessWidget {
  const _MusicButton({required this.view, required this.actions});

  final NarrationView view;
  final NarrationActions actions;

  Future<void> _open(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero, ancestor: overlay);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, _) {
        const width = 300.0;
        final left = (at.dx + box.size.width / 2 - width / 2).clamp(
          12.0,
          overlay.size.width - width - 12,
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              bottom: overlay.size.height - at.dy + 10,
              width: width,
              child: _MusicSheet(view: view, actions: actions),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => _RoundButton(
      label: view.musicOn ? 'Музыка на фоне: играет' : 'Музыка на фоне',
      selected: view.musicOn,
      onPressed: actions.music == null ? null : () => _open(context),
      child: const _Icon(_Paths.music, size: 19),
    ),
  );
}

class _MusicSheet extends StatefulWidget {
  const _MusicSheet({required this.view, required this.actions});

  final NarrationView view;
  final NarrationActions actions;

  @override
  State<_MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<_MusicSheet> {
  late bool _on = widget.view.musicOn;
  late double _volume = widget.view.musicVolume;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Glass(
        radius: 22,
        fill: const Color(0xE6202028),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Музыка на фоне',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: _on,
                  activeThumbColor: Graphite.onAccent,
                  activeTrackColor: Graphite.accent,
                  inactiveThumbColor: Graphite.textMuted,
                  inactiveTrackColor: Graphite.track,
                  onChanged: (v) {
                    setState(() => _on = v);
                    widget.actions.music?.call(v);
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text('Громкость', style: TextStyle(fontSize: 13, color: Graphite.textMuted)),
                Expanded(
                  child: SliderTheme(
                    data: const SliderThemeData(
                      activeTrackColor: Graphite.accent,
                      inactiveTrackColor: Graphite.track,
                      thumbColor: Graphite.accent,
                      overlayColor: Color(0x1FFFFFFF),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _volume,
                      onChanged: !_on || widget.actions.musicVolume == null
                          ? null
                          : (v) {
                              setState(() => _volume = v);
                              widget.actions.musicVolume!(v);
                            },
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'Тихая музыка под голосом диктора; когда он говорит, она приглушается.',
              style: TextStyle(fontSize: 12, height: 1.35, color: Graphite.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
