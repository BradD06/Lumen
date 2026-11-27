import 'dart:io';

import 'package:lumen_core/lumen_core.dart';
import 'package:material_ui/material_ui.dart';

/// Обложка книги, 2:3. Картинка из файла книги в полном цвете, а если её нет —
/// цветная обложка с названием (цвета из макета «Графит»).
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.radius = 14, this.titleSize = 12});

  final Book book;
  final double radius;
  final double titleSize;

  static const _palette = [
    (Color(0xFF8C3B2E), Color(0xFFFFF1E6)),
    (Color(0xFF2F6B5A), Color(0xFFE6FFF6)),
    (Color(0xFF7A2E5C), Color(0xFFFFE6F4)),
    (Color(0xFF2E4F8C), Color(0xFFE6EEFF)),
    (Color(0xFFB8862E), Color(0xFF1F1400)),
    (Color(0xFF4A3A8C), Color(0xFFEEE9FF)),
  ];

  /// Цвет обложки не меняется между запусками: считаем от id сами,
  /// `String.hashCode` в Dart от запуска к запуску разный.
  static (Color, Color) colorsFor(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final path = book.coverPath;
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: path != null
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 400,
                errorBuilder: (_, _, _) => _drawn(),
              )
            : _drawn(),
      ),
    );
  }

  Widget _drawn() {
    final (bg, fg) = colorsFor(book.id);
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: EdgeInsets.all(titleSize * .85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              book.author ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: titleSize * .8, color: fg.withValues(alpha: .8)),
            ),
            Text(
              book.title,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: titleSize,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
