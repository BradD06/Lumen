/// Разбор книг для Lumen: EPUB, FB2 (и FB2 в ZIP), TXT и вставленный текст
/// в главы и абзацы. Без Flutter.
library;

import 'src/epub_parser.dart';
import 'src/fb2_parser.dart';
import 'src/imported_book.dart';
import 'src/txt_parser.dart';

export 'src/imported_book.dart';
export 'src/txt_parser.dart' show parsePlainText, splitParagraphs, guessLanguage;
export 'src/text_decode.dart' show decodeText;

/// Форматы, которые можно добавить (расширения без точки).
const supportedExtensions = ['epub', 'fb2', 'zip', 'txt'];

/// Разобрать файл книги по имени и байтам. Бросает [ImportException].
ImportedBook importBook(String fileName, List<int> bytes) {
  final lower = fileName.toLowerCase();
  final title = _titleFromName(fileName);
  if (bytes.isEmpty) throw const ImportException('Файл пустой.');
  final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  if (lower.endsWith('.epub') || (isZip && _looksLikeEpub(bytes))) {
    return parseEpub(bytes, fallbackTitle: title);
  }
  if (lower.endsWith('.fb2.zip') || (lower.endsWith('.zip') && isZip)) {
    return parseFb2Zip(bytes, fallbackTitle: title);
  }
  if (lower.endsWith('.fb2')) return parseFb2(bytes, fallbackTitle: title);
  if (lower.endsWith('.txt')) return parseTxt(bytes, title: title);
  if (lower.endsWith('.pdf')) {
    throw const ImportException('PDF пока не поддерживается. Добавьте книгу в EPUB, FB2 или TXT.');
  }
  throw ImportException(
    'Формат «${_extension(fileName)}» не поддерживается. Подойдут EPUB, FB2 и TXT.',
  );
}

bool _looksLikeEpub(List<int> bytes) {
  // В начале EPUB-архива лежит файл mimetype с текстом application/epub+zip.
  final head = String.fromCharCodes(bytes.take(100));
  return head.contains('application/epub+zip');
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(dot + 1);
}

String _titleFromName(String fileName) {
  var name = fileName.split(RegExp(r'[/\\]')).last;
  for (final ext in ['.fb2.zip', '.epub', '.fb2', '.txt', '.zip']) {
    if (name.toLowerCase().endsWith(ext)) {
      name = name.substring(0, name.length - ext.length);
      break;
    }
  }
  return name.replaceAll('_', ' ').trim().isEmpty
      ? 'Без названия'
      : name.replaceAll('_', ' ').trim();
}
