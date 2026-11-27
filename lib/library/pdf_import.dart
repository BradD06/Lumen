import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:lumen_import/lumen_import.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF читает PDFium (пакет pdfrx, работает на всех четырёх системах): текст
/// страниц с местами букв, оглавление и картинку первой страницы для обложки.
/// Абзацы и главы из этого собирает `buildPdfBook` (packages/lumen_import).
Future<ImportedBook> importPdf(String fileName, Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final PdfDocument document;
  try {
    document = await PdfDocument.openData(
      bytes,
      sourceName: 'import:$fileName:${bytes.length}',
      firstAttemptByEmptyPassword: true,
    );
  } on PdfPasswordException {
    throw const ImportException('PDF защищён паролем. Снимите пароль и добавьте книгу снова.');
  } catch (error) {
    debugPrint('PDF не открылся: $error');
    throw const ImportException('Файл PDF повреждён и не открывается.');
  }
  try {
    final pages = <PdfPageLines>[];
    for (final page in document.pages) {
      final text = await page.loadText();
      pages.add(_lines(text, page.width, page.height));
    }
    final outline = _outline(await document.loadOutline());
    final cover = await _cover(document);
    final title = _titleFromName(fileName);
    return await Isolate.run(
      () => buildPdfBook(
        title: title,
        pages: pages,
        outline: outline,
        cover: cover,
        coverExtension: cover == null ? null : 'jpg',
      ),
    );
  } finally {
    await document.dispose();
  }
}

/// Строки страницы: PDFium отдаёт текст с переносами строк и прямоугольник
/// каждой буквы (снизу вверх) — переводим в строки сверху вниз.
PdfPageLines _lines(PdfPageRawText? raw, double width, double height) {
  final lines = <PdfLine>[];
  if (raw != null) {
    final text = raw.fullText;
    var buffer = StringBuffer();
    double? left, right, top, bottom;
    void flush() {
      final line = buffer.toString();
      if (line.trim().isNotEmpty && left != null) {
        lines.add(PdfLine(line, left: left!, right: right!, top: top!, bottom: bottom!));
      }
      buffer = StringBuffer();
      left = right = top = bottom = null;
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '\n' || ch == '\r') {
        flush();
        continue;
      }
      buffer.write(ch);
      if (i >= raw.charRects.length) continue;
      final r = raw.charRects[i];
      if (r.isEmpty || ch.trim().isEmpty) continue;
      final t = height - r.top;
      final b = height - r.bottom;
      left = left == null ? r.left : (r.left < left! ? r.left : left);
      right = right == null ? r.right : (r.right > right! ? r.right : right);
      top = top == null ? t : (t < top! ? t : top);
      bottom = bottom == null ? b : (b > bottom! ? b : bottom);
    }
    flush();
  }
  return PdfPageLines(width: width, height: height, lines: lines);
}

List<PdfOutlineEntry> _outline(List<PdfOutlineNode> nodes) => [
  for (final n in nodes)
    PdfOutlineEntry(n.title, (n.dest?.pageNumber ?? 0) - 1, children: _outline(n.children)),
];

/// Обложка — первая страница, 600 px в ширину, JPEG.
Future<Uint8List?> _cover(PdfDocument document) async {
  if (document.pages.isEmpty) return null;
  final page = document.pages.first;
  const width = 600;
  final height = (width * page.height / page.width).round();
  final image = await page.render(
    fullWidth: width.toDouble(),
    fullHeight: height.toDouble(),
    width: width,
    height: height,
    backgroundColor: 0xFFFFFFFF,
  );
  if (image == null) return null;
  try {
    final pixels = Uint8List.fromList(image.pixels);
    final w = image.width;
    final h = image.height;
    return await Isolate.run(
      () => img.encodeJpg(
        img.Image.fromBytes(
          width: w,
          height: h,
          bytes: pixels.buffer,
          numChannels: 4,
          order: img.ChannelOrder.bgra,
        ),
        quality: 85,
      ),
    );
  } catch (error) {
    debugPrint('Обложка PDF не получилась: $error');
    return null;
  } finally {
    image.dispose();
  }
}

String _titleFromName(String fileName) {
  var name = fileName.split(RegExp(r'[/\\]')).last;
  if (name.toLowerCase().endsWith('.pdf')) name = name.substring(0, name.length - 4);
  name = name.replaceAll('_', ' ').trim();
  return name.isEmpty ? 'Без названия' : name;
}
