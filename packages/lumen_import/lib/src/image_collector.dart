import 'dart:typed_data';

/// Иллюстрации книги: каждая картинка сохраняется один раз под коротким именем
/// `img<номер>.<расширение>`, даже если стоит в книге несколько раз.
final class ImageCollector {
  final files = <String, Uint8List>{};
  final _names = <String, String>{};

  /// Картинки меньше этого — значки и завитушки между главами, их пропускаем.
  static const minBytes = 1024;

  static const _formats = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  /// Имя картинки в книге или `null`, если картинку не берём
  /// (неподходящий формат, например SVG, или слишком маленькая).
  String? add(String key, List<int> bytes, String extension) {
    final known = _names[key];
    if (known != null) return known;
    final ext = sniffExtension(bytes) ?? extension.toLowerCase();
    if (!_formats.contains(ext) || bytes.length < minBytes) return null;
    final name = 'img${_names.length + 1}.${ext == 'jpeg' ? 'jpg' : ext}';
    _names[key] = name;
    files[name] = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    return name;
  }

  /// Формат по первым байтам: расширению в файле книги верить нельзя.
  static String? sniffExtension(List<int> b) {
    if (b.length < 12) return null;
    if (b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
    if (b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'webp';
    }
    return null;
  }
}
