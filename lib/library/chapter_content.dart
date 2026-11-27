import 'dart:io';

import 'package:lumen_core/lumen_core.dart';
import 'package:flutter/rendering.dart' hide TextRange;
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
          : NarrationMarks(
              word: word,
              sentence: sentence,
              child: Text(text, style: textStyle),
            ),
    ),
    ImageItem(:final image) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 20),
      child: ChapterImageView(image: image),
    ),
  };
}

/// Подсветка голоса под текстом: предложение — серая плашка, слово — янтарная, у каждой
/// строки свои скруглённые углы. Рисуется за абзацем, сам текст не меняется.
class NarrationMarks extends SingleChildRenderObjectWidget {
  const NarrationMarks({super.key, this.word, this.sentence, required Text super.child});

  final TextRange? word;
  final TextRange? sentence;

  @override
  RenderNarrationMarks createRenderObject(BuildContext context) =>
      RenderNarrationMarks(word: word, sentence: sentence);

  @override
  void updateRenderObject(BuildContext context, RenderNarrationMarks renderObject) => renderObject
    ..word = word
    ..sentence = sentence;
}

class RenderNarrationMarks extends RenderProxyBox {
  RenderNarrationMarks({TextRange? word, TextRange? sentence}) {
    _word = word;
    _sentence = sentence;
  }

  static const _radius = Radius.circular(6);

  TextRange? get word => _word;
  TextRange? _word;
  set word(TextRange? value) {
    if (value == _word) return;
    _word = value;
    markNeedsPaint();
  }

  TextRange? get sentence => _sentence;
  TextRange? _sentence;
  set sentence(TextRange? value) {
    if (value == _sentence) return;
    _sentence = value;
    markNeedsPaint();
  }

  RenderParagraph? _paragraph() {
    RenderParagraph? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph) {
        found = object;
      } else {
        object.visitChildren(visit);
      }
    }

    final c = child;
    if (c != null) visit(c);
    return found;
  }

  /// Плашки по строкам: куски одной строки сливаются в одну, чуть шире самого текста.
  static List<Rect> lines(RenderParagraph paragraph, TextRange range) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    final merged = <Rect>[];
    for (final box in boxes) {
      final rect = box.toRect();
      if (rect.isEmpty) continue;
      final i = merged.indexWhere((r) => (r.center.dy - rect.center.dy).abs() < rect.height / 2);
      if (i < 0) {
        merged.add(rect);
      } else {
        merged[i] = merged[i].expandToInclude(rect);
      }
    }
    return [
      for (final r in merged) Rect.fromLTRB(r.left - 4, r.top - 2, r.right + 4, r.bottom + 2),
    ];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paragraph = _paragraph();
    if (paragraph != null && (word != null || sentence != null)) {
      final shift = offset + paragraph.localToGlobal(Offset.zero, ancestor: this);
      void draw(TextRange? range, Color color) {
        if (range == null || range.end <= range.start) return;
        final paint = Paint()..color = color;
        for (final r in lines(paragraph, range)) {
          context.canvas.drawRRect(RRect.fromRectAndRadius(r.shift(shift), _radius), paint);
        }
      }

      draw(sentence, Graphite.sentenceMark);
      draw(word, Graphite.wordMark);
    }
    super.paint(context, offset);
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
