import 'dart:io';

import 'package:lumen_core/lumen_core.dart';
import 'package:material_ui/material_ui.dart' hide TextRange;

import '../theme/graphite.dart';
import 'widgets.dart';

/// Кусок главы на экране: абзац текста или иллюстрация.
sealed class ChapterItem {
  const ChapterItem();
}

final class ParagraphItem extends ChapterItem {
  const ParagraphItem(this.index, this.text);

  /// Номер абзаца в `Chapter.paragraphs`.
  final int index;
  final String text;
}

final class ImageItem extends ChapterItem {
  const ImageItem(this.image);

  final ChapterImage image;
}

/// Абзацы и картинки главы по порядку: картинка с `position` N стоит перед абзацем N.
List<ChapterItem> chapterItems(Chapter chapter) {
  final texts = chapter.paragraphTexts;
  final images = [...chapter.images]..sort((a, b) => a.position.compareTo(b.position));
  final items = <ChapterItem>[];
  var next = 0;
  for (var i = 0; i <= texts.length; i++) {
    while (next < images.length && images[next].position <= i) {
      items.add(ImageItem(images[next++]));
    }
    if (i < texts.length) items.add(ParagraphItem(i, texts[i]));
  }
  return items;
}

/// Абзац или картинка в тексте главы.
class ChapterItemView extends StatelessWidget {
  const ChapterItemView({super.key, required this.item, this.word, this.sentence});

  final ChapterItem item;

  /// Слово под голосом и его предложение — места внутри этого абзаца.
  final TextRange? word;
  final TextRange? sentence;

  static const textStyle = TextStyle(fontSize: 17, height: 1.55, color: Graphite.text);

  @override
  Widget build(BuildContext context) => switch (item) {
    ParagraphItem(:final text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: word == null && sentence == null
          ? Text(text, style: textStyle)
          : Text.rich(
              highlighted(text, word: word, sentence: sentence),
              style: textStyle,
            ),
    ),
    ImageItem(:final image) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 20),
      child: ChapterImageView(image: image),
    ),
  };

  /// Подсветка по макету «Графит»: слово — сплошной янтарь с тёмным текстом,
  /// остальное предложение — янтарь 16 %.
  static TextSpan highlighted(String text, {TextRange? word, TextRange? sentence}) {
    final cuts = <int>{0, text.length};
    for (final r in [word, sentence]) {
      if (r == null) continue;
      cuts
        ..add(r.start.clamp(0, text.length))
        ..add(r.end.clamp(0, text.length));
    }
    final points = cuts.toList()..sort();
    final spans = <TextSpan>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a == b) continue;
      final inWord = word != null && a >= word.start && b <= word.end;
      final inSentence = sentence != null && a >= sentence.start && b <= sentence.end;
      spans.add(
        TextSpan(
          text: text.substring(a, b),
          style: inWord
              ? const TextStyle(color: Graphite.onAmber, backgroundColor: Graphite.amber)
              : inSentence
              ? const TextStyle(backgroundColor: Graphite.amberSoft)
              : null,
        ),
      );
    }
    return TextSpan(children: spans);
  }
}

/// Иллюстрация в полном цвете, не выше ⅔ экрана. Нажатие — во весь экран с увеличением.
class ChapterImageView extends StatelessWidget {
  const ChapterImageView({super.key, required this.image});

  final ChapterImage image;

  @override
  Widget build(BuildContext context) {
    final path = image.path;
    if (path == null) return const SizedBox.shrink();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.66;
    return Semantics(
      image: true,
      button: true,
      label: 'Иллюстрация',
      child: GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: const Color(0xF2000000),
            barrierDismissible: true,
            pageBuilder: (_, _, _) => _FullImage(path: path),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                // Экономим память на больших сканах.
                cacheWidth: 1600,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
          ),
        ),
        Positioned(
          top: top + 16,
          right: 16,
          child: GlassIconButton(
            icon: Icons24.close,
            label: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
