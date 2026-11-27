import 'package:material_ui/material_ui.dart';

import '../library/book_cover.dart';
import '../library/widgets.dart';
import '../narration/narration_scope.dart';
import '../screens/library_screen.dart' show openBookInLibrary;
import '../theme/glass.dart';
import '../theme/graphite.dart';
import 'app_shell.dart' show TabSwitcher;
import 'tabs.dart';

/// Мини-плеер над островом: книга играет, пока ходишь по разделам. Обложка, глава,
/// янтарная полоска главы, пауза и крестик. Нажатие — текст главы.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    final n = NarrationScope.of(context);
    final book = n.book;
    final text = n.text;
    if (book == null || text == null) return const SizedBox.shrink();
    final s = n.state;
    final chapter = book.chapters[n.chapterIndex];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Semantics(
        container: true,
        label: 'Мини-плеер',
        child: Glass(
          radius: 22,
          fill: Graphite.islandFill,
          border: Graphite.islandBorder,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                TabSwitcher.of(context)(AppTab.library);
                openBookInLibrary(book, n.chapterIndex);
              },
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
                      child: Row(
                        spacing: 10,
                        children: [
                          SizedBox(
                            width: 30,
                            height: 44,
                            child: BookCover(book: book, radius: 6, titleSize: 5),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chapter.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  s.waiting?.title ?? book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Graphite.textMuted),
                                ),
                              ],
                            ),
                          ),
                          _MiniButton(
                            label: s.playing ? 'Пауза' : 'Слушать',
                            loading: s.playing && s.loading,
                            filled: true,
                            path: s.playing ? 'M7 4h4v16H7zM13 4h4v16h-4z' : 'M7 4l13 8-13 8z',
                            onPressed: n.toggle,
                          ),
                          _MiniButton(label: 'Закрыть', path: Icons24.close, onPressed: n.close),
                        ],
                      ),
                    ),
                    // Сколько главы прослушано — тонкая янтарная полоска снизу.
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 3,
                      height: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Graphite.track),
                            ValueListenableBuilder(
                              valueListenable: n.live,
                              builder: (context, live, bar) => FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: text.progressAt(live.offset),
                                child: bar,
                              ),
                              child: const ColoredBox(color: Graphite.amber),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.path,
    required this.onPressed,
    this.filled = false,
    this.loading = false,
  });

  final String label;
  final String path;
  final VoidCallback onPressed;
  final bool filled;
  final bool loading;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Material(
              color: filled ? Graphite.accent : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: LineIcon(
                      path,
                      size: filled ? 18 : 20,
                      color: filled ? Graphite.onAccent : Graphite.text,
                      filled: filled,
                    ),
                  ),
                ),
              ),
            ),
            if (loading)
              const IgnorePointer(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Graphite.amber),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
